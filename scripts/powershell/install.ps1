Write-Host "==========================================================" -ForegroundColor Cyan
Write-Host "0. Prerequisite & Environment Setup" -ForegroundColor Yellow
Write-Host "==========================================================" -ForegroundColor Cyan
# Loads the entire configuration from the .env file into the local PowerShell environment (process level)
if (Test-Path ".env") {
    Write-Host "Loading environment variables from .env file..." -ForegroundColor Cyan
    Get-Content ".env" | ForEach-Object {
        if ($_ -match '^\s*([^#\s][^=]+)=(.*)$') {
            $name =$matches[1].Trim()
            $value =$matches[2].Trim()
            [Environment]::SetEnvironmentVariable($name,$value, "Process")
        }
    }
    Write-Host "✅ .env loaded successfully." -ForegroundColor Green
} else {
    Write-Host "⚠️ Warning: .env file not found! Please create it before proceeding." -ForegroundColor Red
    exit
}
$WorkspaceName = if ($env:WORKSPACE_NAME) {$env:WORKSPACE_NAME } else { "npm-cicd" }
$WorkspaceDir = "/var/jenkins_home/workspace/$WorkspaceName"

# Checks for the availability of the Helm CLI and automatically installs it using winget if it is not already detected on the system.
if (-not (Get-Command helm -ErrorAction SilentlyContinue)) {
    Write-Host "Helm is not detected! Attempting to install Helm using winget..." -ForegroundColor Yellow
    try {
        winget install Helm.Helm --accept-source-agreements --accept-package-agreements
        $env:Path = [System.Environment]::GetEnvironmentVariable("Path","Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path","User")
    } catch {
        Write-Host "Failed to install/load Helm automatically." -ForegroundColor Red
        exit
    }
} else {
    Write-Host "✅ Helm is already installed." -ForegroundColor Green
}


Write-Host "`n==========================================================" -ForegroundColor Cyan
Write-Host "1. Running Jenkins, PostgreSQL, and MinIO (Docker Compose)" -ForegroundColor Yellow
Write-Host "==========================================================" -ForegroundColor Cyan
# Melakukan autentikasi ke Docker Hub dan menjalankan container untuk Jenkins, PostgreSQL, MinIO, serta Nexus.
if (-not [string]::IsNullOrWhiteSpace($env:DOCKER_USER) -and -not [string]::IsNullOrWhiteSpace($env:DOCKER_PASS)) {
    Write-Host "Logging in to Docker Hub as $($env:DOCKER_USER)..." -ForegroundColor Cyan
    $env:DOCKER_PASS | docker login --username $env:DOCKER_USER --password-stdin
    if ($LASTEXITCODE -ne 0) {
        Write-Host "❌ Docker login failed! Please check your credentials in .env" -ForegroundColor Red
        exit
    } else {
        Write-Host "✅ Docker login successful!" -ForegroundColor Green
    }
} else {
    Write-Host "⚠️ DOCKER_USER or DOCKER_PASS not found in .env, skipping explicit login..." -ForegroundColor Yellow
}

# Memperbaiki izin akses kepemilikan direktori (CHOWN) pada volume Jenkins dan Nexus, lalu mengekstrak password admin inisial Jenkins langsung dari dalam container.
Write-Host "Fixing volume permissions for Jenkins..." -ForegroundColor Cyan
docker run --rm -v npm_jenkins_home:/var/jenkins_home alpine chown -R 1000:1000 /var/jenkins_home 2>$null
docker run --rm -v nexus_data:/nexus-data alpine chown -R 200:200 /nexus-data 2>$null
$composeImageName = "npm-jenkins"

Write-Host "🔍 Checking the availability of a custom Docker image ($composeImageName)..." -ForegroundColor Yellow
$imageExists = docker images -q $composeImageName 2>$null
if ([string]::IsNullOrWhiteSpace($imageExists)) {
    Write-Host "⚙️ Image not yet available locally. Initiating initial build process." -ForegroundColor Cyan
    docker compose up -d --build
} else {
    Write-Host "✅ Image '$composeImageName' Already available. Launching the container immediately." -ForegroundColor Green
    docker compose up -d
}
Write-Host "`nWaiting for Docker containers to initialize (20s)..." -ForegroundColor Magenta
Start-Sleep -Seconds 20
# --- Get Jenkins Password ---
$jenkinsId = docker ps -q --filter "name=jenkins"
$jenkinsPass = ""
if ($jenkinsId) {
    $rawPass = docker exec $jenkinsId cat /var/jenkins_home/secrets/initialAdminPassword 2>$null
    if ($rawPass) { $jenkinsPass = $rawPass.Trim() }
}
if ([string]::IsNullOrWhiteSpace($jenkinsPass)) {
    $jenkinsPass = "InitAdminPassword has been performed; please log in using the credentials registered in Jenkins."
}


Write-Host "`n==========================================================" -ForegroundColor Cyan
Write-Host "2. Setup Argo CD on Kubernetes (K3s)" -ForegroundColor Yellow
Write-Host "==========================================================" -ForegroundColor Cyan
# Mendeploy ArgoCD ke klaster K3s dan menahan eksekusi (wait) hingga seluruh pod berstatus ready.
kubectl create namespace argocd
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
Write-Host "`nWaiting for Argo CD pods to become ready (this takes a few minutes)..." -ForegroundColor Magenta
kubectl wait --for=condition=ready pod --all -n argocd --timeout=300s
$argocdPass = "P4ssw0rdArgoCD"
Write-Host "`nLocking the ArgoCD admin password..." -ForegroundColor Green

#Men-generate password admin ArgoCD menggunakan hash Bcrypt secara native, memperbarui K8s secret, mengaplikasikan manifest Ingress, dan me-restart pod untuk menerapkan perubahan.
$bcryptOutput = kubectl exec -n argocd deploy/argocd-server -- argocd account bcrypt --password $argocdPass 2>$null
$bcryptHash = ($bcryptOutput | Select-Object -Last 1).Trim()
$encodedHash = [Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($bcryptHash))
$encodedMtime = [Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes((Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")))
# Patch the ArgoCD Secret with a permanent hash
$patchContent = "{ `"data`": { `"admin.password`": `"$encodedHash`", `"admin.passwordMtime`": `"$encodedMtime`" } }"
$patchContent | Out-File -FilePath "argo-patch.json" -Encoding utf8
kubectl patch secret argocd-secret -n argocd --type='merge' --patch-file argo-patch.json
Remove-Item "argo-patch.json" -ErrorAction SilentlyContinue
kubectl delete secret argocd-initial-admin-secret -n argocd --ignore-not-found=true
# Apply manifest ConfigMap & Ingress sebelum restart pod
Write-Host "`nApplying ArgoCD local manifest (ConfigMap & Ingress)..." -ForegroundColor Yellow
kubectl apply -f k8s/argocd.yaml
# Restart the pod so it reads the newly applied insecure ConfigMap
kubectl rollout restart deploy/argocd-server -n argocd
kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=argocd-server -n argocd --timeout=120s
Write-Host "[SUCCESS] Password ArgoCD berhasil dikunci mati menjadi: $argocdPass" -ForegroundColor Green


# Mengeksekusi instalasi K3s secara berurutan untuk Nginx Ingress Controller, PGAdmin, stack pemantauan (Prometheus & Grafana), komponen HashiCorp Vault, dan message broker ActiveMQ Artemis melalui Helm.
Write-Host "`n==========================================================" -ForegroundColor Cyan
Write-Host "3. Setup Nginx Ingress Controller (Core Networking)" -ForegroundColor Yellow
Write-Host "==========================================================" -ForegroundColor Cyan
helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx
helm repo update
helm upgrade --install ingress-nginx ingress-nginx/ingress-nginx `
    --namespace ingress-nginx `
    --create-namespace `
    --set controller.service.type=LoadBalancer

# helm repo add cilium https://helm.cilium.io/
# helm install cilium cilium/cilium --version 1.14.0 --namespace kube-system --set ingressController.enabled=true --set ingressController.default=true

Write-Host "`n==========================================================" -ForegroundColor Cyan
Write-Host "4. Setup PGAdmin on Kubernetes (K3s via Helm)" -ForegroundColor Yellow
Write-Host "==========================================================" -ForegroundColor Cyan
helm repo add runix https://helm.runix.net
helm repo update

helm upgrade --install pgadmin runix/pgadmin4 -n default `
    --set env.email="$env:PGADMIN_EMAIL" `
    --set env.password="$env:PGADMIN_PASSWORD" `
    --set service.type=LoadBalancer `
    --set service.port=8081


Write-Host "`n==========================================================" -ForegroundColor Cyan
Write-Host "5. Setup Prometheus & Grafana on Kubernetes (K3s via Helm)" -ForegroundColor Yellow
Write-Host "==========================================================" -ForegroundColor Cyan
kubectl create namespace monitoring --dry-run=client -o yaml | kubectl apply -f -
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo update

helm upgrade --install prometheus-stack prometheus-community/kube-prometheus-stack -n monitoring `
    --set grafana.service.type=LoadBalancer `
    --set grafana.service.port=8083 `
    --set prometheus.service.type=LoadBalancer `
    --set prometheus.service.port=9090


Write-Host "`n==========================================================" -ForegroundColor Cyan
Write-Host "6. Setup HashiCorp Vault on Kubernetes (K3s via Helm)" -ForegroundColor Yellow
Write-Host "==========================================================" -ForegroundColor Cyan
kubectl create namespace vault --dry-run=client -o yaml | kubectl apply -f -
helm repo add hashicorp https://helm.releases.hashicorp.com
helm repo update

helm upgrade --install vault hashicorp/vault -n vault `
    --set "server.dev.enabled=true" `
    --set "injector.enabled=true" `
    --set "ui.enabled=true" `
    --set "ui.serviceType=LoadBalancer" `
    --set "ui.externalPort=8200"

Write-Host "`n==========================================================" -ForegroundColor Cyan
Write-Host "7. Setup ActiveMQ Artemis on Kubernetes (K3s via Helm)" -ForegroundColor Yellow
Write-Host "==========================================================" -ForegroundColor Cyan
Write-Host "Creating 'artemis' namespace..." -ForegroundColor Cyan
helm repo add vromero https://vromero.github.io/activemq-artemis-helm/
helm repo update

helm upgrade --install artemis vromero/activemq-artemis -n artemis `
    --create-namespace `
    --set adminUser="$env:ARTEMIS_USER" `
    --set adminPassword="$env:ARTEMIS_PASSWORD"

# --- Non Helm ---
# Write-Host "`n==========================================================" -ForegroundColor Cyan
# Write-Host "7. Setup ActiveMQ Artemis on Kubernetes (K3s via Manifest)" -ForegroundColor Yellow
# Write-Host "==========================================================" -ForegroundColor Cyan
# Write-Host "Creating 'artemis' namespace..." -ForegroundColor Cyan
# kubectl create namespace artemis --dry-run=client -o yaml | kubectl apply -f -

# Write-Host "Injecting Artemis Credentials from .env to Kubernetes Secret..." -ForegroundColor Cyan
# kubectl create secret generic artemis-credentials -n artemis `
#     --from-literal=ARTEMIS_USER="$env:ARTEMIS_USER" `
#     --from-literal=ARTEMIS_PASSWORD="$env:ARTEMIS_PASSWORD" `
#     --dry-run=client -o yaml | kubectl apply -f -

# Write-Host "Applying Artemis StatefulSet Manifest..." -ForegroundColor Cyan
# kubectl apply -f k8s/artemis.yaml


Write-Host "`n==========================================================" -ForegroundColor Cyan
Write-Host "8. Complete The Installation Process" -ForegroundColor Yellow
Write-Host "==========================================================" -ForegroundColor Cyan
$grafanaPass = ""
$encodedGrafana = kubectl get secret prometheus-stack-grafana -n monitoring -o jsonpath="{.data.admin-password}" 2>$null
if ($encodedGrafana) {
    $grafanaPass = [System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($encodedGrafana))
} else {
    $grafanaPass = "prom-operator" 
}

# Membersihkan sisa instalasi atau Persistent Volume Claim (PVC) Vault versi sebelumnya untuk mencegah status sealed yang terkunci, lalu mendeploy ulang Vault.
# 1. Complete cleanup of global resources & legacy namespaces
Write-Host "Membersihkan resource global dan instalasi Vault sebelumnya..." -ForegroundColor Cyan
helm uninstall vault -n vault --no-hooks --ignore-not-found 2>$null
kubectl delete namespace vault --force --grace-period=0 --ignore-not-found 2>$null
kubectl delete mutatingwebhookconfiguration vault-agent-injector-cfg --ignore-not-found 2>$null
kubectl delete validatingwebhookconfiguration vault-agent-injector-webhook --ignore-not-found 2>$null
kubectl delete clusterrole vault-agent-injector-clusterrole --ignore-not-found 2>$null
kubectl delete clusterrolebinding vault-agent-injector-clusterrolebinding --ignore-not-found 2>$null
# 2. Safely delete any existing local key file, if present
$keyFile = "vault-keys.json"
if (Test-Path $keyFile) {
    try {
        Remove-Item $keyFile -Force -ErrorAction Stop
        Write-Host "✅ Berhasil menghapus file kunci lama ($keyFile)." -ForegroundColor Green
    } catch {
        Write-Host "⚠️ Gagal menghapus $keyFile, file mungkin sedang digunakan proses lain." -ForegroundColor Yellow
    }
}
# 3. Recreate the namespace and run Helm install
kubectl create namespace vault --dry-run=client -o yaml | kubectl apply -f -
helm repo add hashicorp https://helm.releases.hashicorp.com
helm repo update
# 4. Enabling Production Mode with a 1GB Persistent Volume Claim (PVC)
helm upgrade --install vault hashicorp/vault -n vault `
    --set "server.dev.enabled=false" `
    --set "server.dataStorage.enabled=true" `
    --set "server.dataStorage.size=1Gi" `
    --set "injector.enabled=true" `
    --set "ui.enabled=true" `
    --set "ui.serviceType=LoadBalancer" `
    --set "ui.externalPort=8200"

# Mengeksekusi inisialisasi cluster (1 key share), menyimpan root token ke vault-keys.json, melakukan proses unseal secara otomatis, dan mengaktifkan KV v2 Secrets Engine.
Write-Host "`nWaiting for Vault pod to be created..." -ForegroundColor Magenta
Start-Sleep -Seconds 10
kubectl wait --for=condition=ready pod/vault-0 -n vault --timeout=120s
Write-Host "`nChecking Vault Initialization and Seal Status..." -ForegroundColor Yellow
$vaultStatusJson = kubectl exec -n vault vault-0 -- vault status -format=json 2>$null
$vaultStatus = $vaultStatusJson | ConvertFrom-Json
if ($vaultStatus.initialized -eq $false) {
    Write-Host "⚙️ Vault belum di-inisialisasi. Memulai proses init (1 Key Share)..." -ForegroundColor Cyan
    $initResult = kubectl exec -n vault vault-0 -- vault operator init -key-shares=1 -key-threshold=1 -format=json
    $initResult | Out-File -FilePath $keyFile -Encoding utf8
    Write-Host "✅ Vault di-inisialisasi! Kunci baru disimpan di '$keyFile'." -ForegroundColor Green
} else {
    Write-Host "✅ Vault sudah terinisialisasi sebelumnya." -ForegroundColor Green
}
# Reading tokens and keys from a new local file
if (-not (Test-Path $keyFile)) {
    Write-Host "❌ File $keyFile tidak ditemukan! Tidak bisa melakukan Unseal." -ForegroundColor Red
    exit
}
$vaultKeys = Get-Content $keyFile | ConvertFrom-Json
$unsealKey = $vaultKeys.unseal_keys_b64[0]
$VaultRootToken = $vaultKeys.root_token
# Checking whether Vault is in a Sealed (locked) state
$vaultStatusJson = kubectl exec -n vault vault-0 -- vault status -format=json 2>$null
$vaultStatus = $vaultStatusJson | ConvertFrom-Json
if ($vaultStatus.sealed -eq$true) {
    Write-Host "🔐 Vault dalam keadaan Terkunci (Sealed). Melakukan Unseal otomatis..." -ForegroundColor Cyan
    kubectl exec -n vault vault-0 -- vault operator unseal $unsealKey | Out-Null
    Write-Host "🔓 Vault berhasil di-Unseal!" -ForegroundColor Green
} else {
    Write-Host "🔓 Vault sudah dalam keadaan terbuka (Unsealed)." -ForegroundColor Green
}

Write-Host "`nMemeriksa dan mengaktifkan KV Secrets Engine di path 'secret/'..." -ForegroundColor Yellow
kubectl exec -n vault vault-0 -- vault login $VaultRootToken | Out-Null
$secretsList = kubectl exec -n vault vault-0 -- vault secrets list -format=json 2>$null
$secretsObj = $secretsList | ConvertFrom-Json
if (-not $secretsObj.'secret/') {
    Write-Host "⚙️ Path 'secret/' belum aktif. Mengaktifkan KV v2 Engine..." -ForegroundColor Cyan
    kubectl exec -n vault vault-0 -- vault secrets enable -path=secret -version=2 kv | Out-Null
    Write-Host "✅ KV v2 Engine berhasil diaktifkan di 'secret/'!" -ForegroundColor Green
} else {
    Write-Host "✅ Path 'secret/' sudah aktif." -ForegroundColor Green
}

Write-Host "`nMenyimpan seluruh kredensial layanan & Jenkins ke dalam Vault..." -ForegroundColor Yellow
# Infrastructure & Data Services
kubectl exec -n vault vault-0 -- vault kv put secret/database/postgres username="postgres" password="$env:POSTGRES_PASSWORD" | Out-Null
kubectl exec -n vault vault-0 -- vault kv put secret/pgadmin admin_email="$env:PGADMIN_EMAIL" admin_password="$env:PGADMIN_PASSWORD" | Out-Null
kubectl exec -n vault vault-0 -- vault kv put secret/minio root_user="$env:MINIO_ROOT_USER" root_password="$env:MINIO_ROOT_PASSWORD" | Out-Null
kubectl exec -n vault vault-0 -- vault kv put secret/artemis admin_user="$env:ARTEMIS_USER" admin_password="$env:ARTEMIS_PASSWORD" | Out-Null
# CI/CD & Monitoring Services
kubectl exec -n vault vault-0 -- vault kv put secret/nexus admin_user="admin" admin_password="$env:NEXUS_PASSWORD" | Out-Null
kubectl exec -n vault vault-0 -- vault kv put secret/argocd admin_user="admin" admin_password="$env:ARGOCD_PASSWORD" | Out-Null
kubectl exec -n vault vault-0 -- vault kv put secret/grafana admin_user="admin" admin_password="$grafanaPass" | Out-Null
kubectl exec -n vault vault-0 -- vault kv put secret/jenkins/admin admin_user="jenkins" admin_password="$env:JENKINS_PASSWORD" | Out-Null
# External Credentials for Jenkins Pipelines
kubectl exec -n vault vault-0 -- vault kv put secret/jenkins/github username="$env:GITHUB_USER" token="$env:GITHUB_TOKEN" | Out-Null
kubectl exec -n vault vault-0 -- vault kv put secret/jenkins/dockerhub username="$env:DOCKER_USER" password="$env:DOCKER_PASS" | Out-Null
kubectl exec -n vault vault-0 -- vault kv put secret/argocd admin_user="admin" admin_password="$argocdPass" | Out-Null
Write-Host "✅ Seluruh kredensial berhasil diekspor ke Vault KV (secret/)." -ForegroundColor Green

Write-Host "📦 Mengunggah File Binary Lokal ke Nexus Repository" -ForegroundColor Yellow
$ProgressPreference = 'SilentlyContinue'
$binFolder = "$env:LOCAL_PROJECT_PATH\bin"
$nexusUrl = "http://127.0.0.1:8082"
$repoName = "raw-binaries"
$nexusPass = $env:NEXUS_PASSWORD
if ([string]::IsNullOrWhiteSpace($nexusPass)) {
    Write-Host "⚠️ NEXUS_PASSWORD tidak ditemukan di .env! Lewati proses upload otomatis." -ForegroundColor Red
} else {
    Write-Host "Memeriksa dan membuat repository '$repoName' di Nexus..." -ForegroundColor Cyan
    $base64AuthInfo = [Convert]::ToBase64String([System.Text.Encoding]::ASCII.GetBytes(("admin:{0}" -f $nexusPass)))
    $headers = @{
        Authorization = ("Basic {0}" -f $base64AuthInfo)
        "Content-Type" = "application/json"
    }
    $repoPayload = @{
        name = $repoName
        online = $true
        storage = @{
            blobStoreName = "default"
            strictContentTypeValidation = $false
            writePolicy = "ALLOW"
        }
        raw = @{
            contentDisposition = "ATTACHMENT"
        }
    } | ConvertTo-Json -Depth 10

    $authFailed = $false
    try {
        Invoke-RestMethod -Uri "$nexusUrl/service/rest/v1/repositories/raw/hosted" -Method Post -Headers $headers -Body $repoPayload -ErrorAction Stop | Out-Null
        Write-Host "✅ Repository '$repoName' berhasil dibuat via API." -ForegroundColor Green
    } catch {
        $statusCode = $_.Exception.Response.StatusCode.Value__
        if ($statusCode -eq 401) {
            Write-Host "❌ Autentikasi Gagal! Password Nexus salah. Pastikan NEXUS_PASSWORD di .env valid." -ForegroundColor Red
            $authFailed = $true
        } elseif ($statusCode -eq 400 -or $statusCode -eq 422) {
            Write-Host "❌ Gagal membuat repository. Payload API ditolak Nexus." -ForegroundColor Red
            $authFailed = $true
        } else {
            Write-Host "✅ Repository '$repoName' sudah tersedia di sistem." -ForegroundColor Green
        }
    }
    
    if (-not $authFailed) {
        if (Test-Path $binFolder) {
            $files = Get-ChildItem -Path $binFolder -File
            if ($files.Count -gt 0) {
                foreach ($file in $files) {
                    Write-Host "⬆️ Mengunggah $($file.Name) ke Nexus..." -ForegroundColor Yellow
                    $uploadUrl = "$nexusUrl/repository/$repoName/$($file.Name)"
                    
                    $curlOutput = curl.exe --silent --show-error --fail -u "admin:$nexusPass" -T "$($file.FullName)" "$uploadUrl" 2>&1
                    
                    if ($LASTEXITCODE -eq 0) {
                        Write-Host "✅ Sukses mengunggah $($file.Name)." -ForegroundColor Green
                    } else {
                        Write-Host "⚠️ Gagal mengunggah $($file.Name). Detail Error: $curlOutput" -ForegroundColor Red
                    }
                }
            } else {
                Write-Host "⚠️ Folder $binFolder kosong." -ForegroundColor Yellow
            }
        } else {
            Write-Host "⚠️ Folder $binFolder tidak ditemukan." -ForegroundColor Yellow
        }
    }
}
$ProgressPreference = 'Continue'

Write-Host "`n==========================================================" -ForegroundColor Green
Write-Host "Done! Setup successful." -ForegroundColor Green
Write-Host "==========================================================" -ForegroundColor Green
Write-Host "ACCESS YOUR SERVICES:"
Write-Host " - Jenkins    : http://localhost:8080"
Write-Host "   InitAdmin  : $jenkinsPass (Login: jenkins / jenkins)" -ForegroundColor Green
Write-Host " - Nexus 3    : http://localhost:8082 (User: admin, Pass: $nexusPass)" -ForegroundColor Green
Write-Host " - Argo CD    : https://localhost (User: admin, Pass: $argocdPass)" -ForegroundColor Green
Write-Host " - Artemis    : http://localhost:8161 (User: $($env:ARTEMIS_USER), Pass: $($env:ARTEMIS_PASSWORD))" -ForegroundColor Green
Write-Host " - Grafana    : http://localhost:8083 (User: admin, Pass: $grafanaPass)" -ForegroundColor Green
Write-Host " - Prometheus : http://localhost:9090" -ForegroundColor Green
Write-Host " - PGAdmin    : http://localhost:8081 (User: $($env:PGADMIN_EMAIL), Pass: $($env:PGADMIN_PASSWORD))"
Write-Host " - PostgreSQL : localhost:5432 (User: postgres, Pass: $($env:POSTGRES_PASSWORD))"
Write-Host " - MinIO      : http://localhost:9001 (User: $($env:MINIO_ROOT_USER), Pass: $($env:MINIO_ROOT_PASSWORD))" -ForegroundColor Green
Write-Host " - Vault      : http://localhost:8200 (Token: $VaultRootToken)" -ForegroundColor Green
Write-Host "==========================================================" -ForegroundColor Green
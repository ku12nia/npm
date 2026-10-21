Write-Host "==========================================================" -ForegroundColor Cyan
Write-Host "0. Prerequisite & Environment Setup" -ForegroundColor Yellow
Write-Host "==========================================================" -ForegroundColor Cyan

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

# --- Get Nexus Initial Password dengan Polling ---
# $nexusId = docker ps -q --filter "name=nexus"
# $nexusPass = ""

# if ($nexusId) {
#     Write-Host "⏳ Menunggu Nexus selesai booting dan men-generate password (bisa memakan waktu 1-2 menit)..." -ForegroundColor Magenta
    
#     $retryCount = 0
#     $maxRetries = 18 # Maksimal menunggu 18 x 5 detik = 90 detik

#     while ($retryCount -lt $maxRetries) {
#         # Coba baca file password
#         $rawNexusPass = docker exec $nexusId cat /nexus-data/admin.password 2>$null
        
#         # Jika berhasil membaca dan isinya bukan pesan error "No such file"
#         if ($rawNexusPass -and $rawNexusPass -notmatch "No such file" -and -not [string]::IsNullOrWhiteSpace($rawNexusPass)) {
#             $nexusPass = $rawNexusPass.Trim()
#             Write-Host "✅ Password Nexus berhasil didapatkan!" -ForegroundColor Green
#             break
#         }
        
#         Start-Sleep -Seconds 5
#         $retryCount++
#     }
# }

# if ([string]::IsNullOrWhiteSpace($nexusPass)) {
#     $nexusPass = "Password has been changed or check manually."
# }


Write-Host "`n==========================================================" -ForegroundColor Cyan
Write-Host "📦 Mengunggah File Binary Lokal ke Nexus Repository" -ForegroundColor Yellow
Write-Host "==========================================================" -ForegroundColor Cyan

$binFolder = "$env:LOCAL_PROJECT_PATH\bin"
$nexusUrl = "http://localhost:8082"
$repoName = "raw-binaries"
$nexusPass = $env:NEXUS_PASSWORD # <= menambahkan variable untuk pass nexus

# if ($nexusPass -notmatch "Password has been changed") {
#     Write-Host "Memeriksa dan membuat repository '$repoName' di Nexus..." -ForegroundColor Cyan
#     $repoPayload = @{
#         name = $repoName
#         online = $true
#         storage = @{
#             blobStoreName = "default"
#             strictContentTypeValidation = $false
#         }
#     } | ConvertTo-Json -Depth 10

#     $base64AuthInfo = [Convert]::ToBase64String([System.Text.Encoding]::ASCII.GetBytes(("admin:{0}" -f $nexusPass)))
#     $headers = @{Authorization=("Basic {0}" -f $base64AuthInfo)}
    
#     try {
#         Invoke-RestMethod -Uri "$nexusUrl/service/rest/v1/repositories/raw/hosted" -Method Post -Headers $headers -ContentType "application/json" -Body $repoPayload -ErrorAction Stop | Out-Null
#         Write-Host "✅ Repository '$repoName' berhasil dibuat." -ForegroundColor Green
#     } catch {
#         Write-Host "✅ Repository '$repoName' sudah tersedia." -ForegroundColor Green
#     }

#     if (Test-Path $binFolder) {
#         $files = Get-ChildItem -Path $binFolder -File
#         if ($files.Count -gt 0) {
#             foreach ($file in $files) {
#                 Write-Host "⬆️ Mengunggah $($file.Name) ke Nexus..." -ForegroundColor Yellow
#                 $uploadUrl = "$nexusUrl/repository/$repoName/$($file.Name)"
                
#                 # Menggunakan curl.exe bawaan Windows (dengan -T untuk upload file)
#                 curl.exe -s -u "admin:$nexusPass" -T "$($file.FullName)" "$uploadUrl"
                
#                 Write-Host "✅ Selesai mengunggah $($file.Name)." -ForegroundColor Green
#             }
#         } else {
#             Write-Host "⚠️ Folder $binFolder kosong. Tidak ada yang diunggah." -ForegroundColor Yellow
#         }
#     } else {
#         Write-Host "⚠️ Folder $binFolder tidak ditemukan. Lewati proses upload." -ForegroundColor Yellow
#     }

# } else {
#     Write-Host "⚠️ Password Nexus tidak valid. Silakan upload file bin secara manual." -ForegroundColor Red
# }


if ([string]::IsNullOrWhiteSpace($nexusPass)) {
    Write-Host "⚠️ NEXUS_PASSWORD tidak ditemukan di .env! Lewati proses upload otomatis." -ForegroundColor Red
} else {
    Write-Host "Memeriksa dan membuat repository '$repoName' di Nexus..." -ForegroundColor Cyan
    
    $repoPayload = @{
        name = $repoName
        online = $true
        storage = @{
            blobStoreName = "default"
            strictContentTypeValidation = $false
        }
    } | ConvertTo-Json -Depth 10

    $base64AuthInfo = [Convert]::ToBase64String([System.Text.Encoding]::ASCII.GetBytes(("admin:{0}" -f $nexusPass)))
    $headers = @{Authorization=("Basic {0}" -f $base64AuthInfo)}
    
    try {
        Invoke-RestMethod -Uri "$nexusUrl/service/rest/v1/repositories/raw/hosted" -Method Post -Headers $headers -ContentType "application/json" -Body $repoPayload -ErrorAction Stop | Out-Null
        Write-Host "✅ Repository '$repoName' berhasil dibuat via API." -ForegroundColor Green
    } catch {
        Write-Host "✅ Repository '$repoName' sudah tersedia di sistem." -ForegroundColor Green
    }

    if (Test-Path $binFolder) {
        $files = Get-ChildItem -Path $binFolder -File
        if ($files.Count -gt 0) {
            foreach ($file in $files) {
                Write-Host "⬆️ Mengunggah $($file.Name) ke Nexus..." -ForegroundColor Yellow
                $uploadUrl = "$nexusUrl/repository/$repoName/$($file.Name)"
                
                $curlResult = curl.exe -s -w "%{http_code}" -u "admin:$nexusPass" -T "$($file.FullName)" "$uploadUrl"
                
                if ($curlResult -match "200|201|204") {
                    Write-Host "✅ Sukses mengunggah $($file.Name)." -ForegroundColor Green
                } else {
                    Write-Host "⚠️ Gagal mengunggah $($file.Name). HTTP Code: $curlResult" -ForegroundColor Red
                }
            }
        } else {
            Write-Host "⚠️ Folder $binFolder kosong." -ForegroundColor Yellow
        }
    } else {
        Write-Host "⚠️ Folder $binFolder tidak ditemukan." -ForegroundColor Yellow
    }
}

# -------------------------------------------------------------------------

Write-Host "`n==========================================================" -ForegroundColor Cyan
Write-Host "2. Setup Argo CD on Kubernetes (K3s)" -ForegroundColor Yellow
Write-Host "==========================================================" -ForegroundColor Cyan

kubectl create namespace argocd
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml

Write-Host "`nWaiting for Argo CD pods to become ready (this takes a few minutes)..." -ForegroundColor Magenta
kubectl wait --for=condition=ready pod --all -n argocd --timeout=300s

$argocdPass = "P4ssw0rdArgoCD"
Write-Host "`nLocking the ArgoCD admin password..." -ForegroundColor Green

# Generate valid Bcrypt Hash natively
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

# [PERBAIKAN] Apply manifest ConfigMap & Ingress sebelum restart pod
Write-Host "`nApplying ArgoCD local manifest (ConfigMap & Ingress)..." -ForegroundColor Yellow
kubectl apply -f k8s/argocd.yaml

# Restart pod agar membaca ConfigMap insecure yang baru di-apply
kubectl rollout restart deploy/argocd-server -n argocd
kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=argocd-server -n argocd --timeout=120s
Write-Host "[SUCCESS] Password ArgoCD berhasil dikunci mati menjadi: $argocdPass" -ForegroundColor Green


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
Write-Host "7. Setup ActiveMQ Artemis on Kubernetes (K3s via Helm)" -ForegroundColor Yellow
Write-Host "==========================================================" -ForegroundColor Cyan
Write-Host "Creating 'artemis' namespace..." -ForegroundColor Cyan
helm repo add vromero https://vromero.github.io/activemq-artemis-helm/
helm repo update

helm upgrade --install artemis vromero/activemq-artemis -n artemis `
    --create-namespace `
    --set adminUser="$env:ARTEMIS_USER" `
    --set adminPassword="$env:ARTEMIS_PASSWORD"


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

# 1. Pembersihan total resource global & namespace lama
Write-Host "Membersihkan resource global dan instalasi Vault sebelumnya..." -ForegroundColor Cyan
helm uninstall vault -n vault --no-hooks --ignore-not-found 2>$null
kubectl delete namespace vault --force --grace-period=0 --ignore-not-found 2>$null
kubectl delete mutatingwebhookconfiguration vault-agent-injector-cfg --ignore-not-found 2>$null
kubectl delete validatingwebhookconfiguration vault-agent-injector-webhook --ignore-not-found 2>$null
kubectl delete clusterrole vault-agent-injector-clusterrole --ignore-not-found 2>$null
kubectl delete clusterrolebinding vault-agent-injector-clusterrolebinding --ignore-not-found 2>$null

# 2. Hapus file kunci lama lokal dengan aman jika ada
$keyFile = "vault-keys.json"
if (Test-Path $keyFile) {
    try {
        Remove-Item $keyFile -Force -ErrorAction Stop
        Write-Host "✅ Berhasil menghapus file kunci lama ($keyFile)." -ForegroundColor Green
    } catch {
        Write-Host "⚠️ Gagal menghapus $keyFile, file mungkin sedang digunakan proses lain." -ForegroundColor Yellow
    }
}

# 3. Buat ulang namespace dan jalankan Helm install
kubectl create namespace vault --dry-run=client -o yaml | kubectl apply -f -
helm repo add hashicorp https://helm.releases.hashicorp.com
helm repo update

# Menyalakan Production Mode dengan Persistent Volume Claim (PVC) 1GB
helm upgrade --install vault hashicorp/vault -n vault `
    --set "server.dev.enabled=false" `
    --set "server.dataStorage.enabled=true" `
    --set "server.dataStorage.size=1Gi" `
    --set "injector.enabled=true" `
    --set "ui.enabled=true" `
    --set "ui.serviceType=LoadBalancer" `
    --set "ui.externalPort=8200"

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

# Membaca token dan kunci dari file lokal yang baru
if (-not (Test-Path $keyFile)) {
    Write-Host "❌ File $keyFile tidak ditemukan! Tidak bisa melakukan Unseal." -ForegroundColor Red
    exit
}

$vaultKeys = Get-Content $keyFile | ConvertFrom-Json
$unsealKey = $vaultKeys.unseal_keys_b64[0]
$VaultRootToken = $vaultKeys.root_token

# Mengecek apakah Vault dalam kondisi Sealed (Terkunci)
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

# Login CLI menggunakan Root Token agar punya otorisasi
kubectl exec -n vault vault-0 -- vault login $VaultRootToken | Out-Null

# Mengecek apakah path 'secret/' sudah aktif
$secretsList = kubectl exec -n vault vault-0 -- vault secrets list -format=json 2>$null
$secretsObj = $secretsList | ConvertFrom-Json

if (-not $secretsObj.'secret/') {
    Write-Host "⚙️ Path 'secret/' belum aktif. Mengaktifkan KV v2 Engine..." -ForegroundColor Cyan
    kubectl exec -n vault vault-0 -- vault secrets enable -path=secret -version=2 kv | Out-Null
    Write-Host "✅ KV v2 Engine berhasil diaktifkan di 'secret/'!" -ForegroundColor Green
} else {
    Write-Host "✅ Path 'secret/' sudah aktif." -ForegroundColor Green
}

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
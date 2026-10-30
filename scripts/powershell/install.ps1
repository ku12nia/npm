function Write-Log {
    param (
        [Parameter(Mandatory=$true)]
        [string]$Message,
        [System.ConsoleColor]$ForegroundColor = [System.ConsoleColor]::White
    )
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    Write-Host "[$timestamp] $Message" -ForegroundColor $ForegroundColor
}

Write-Host "==========================================================" -ForegroundColor Cyan
Write-Host "0. Prerequisite & Environment Setup" -ForegroundColor Yellow
Write-Host "==========================================================" -ForegroundColor Cyan
# Loads the entire configuration from the .env file into the local PowerShell environment (process level)
if (Test-Path ".env") {
    Write-Log "Loading environment variables from .env file..." -ForegroundColor Cyan
    Get-Content ".env" | ForEach-Object {
        if ($_ -match '^\s*([^#\s][^=]+)=(.*)$') {
            $name =$matches[1].Trim()
            $value =$matches[2].Trim()
            [Environment]::SetEnvironmentVariable($name,$value, "Process")
        }
    }
    Write-Log "✅ .env loaded successfully." -ForegroundColor Green
} else {
    Write-Log "⚠️ Warning: .env file not found! Please create it before proceeding." -ForegroundColor Red
    exit
}
$WorkspaceName = if ($env:WORKSPACE_NAME) {$env:WORKSPACE_NAME } else { "npm-cicd" }
$WorkspaceDir = "/var/jenkins_home/workspace/$WorkspaceName"

# Checks for the availability of the Helm CLI and automatically installs it using winget if it is not already detected on the system.
if (-not (Get-Command helm -ErrorAction SilentlyContinue)) {
    Write-Log "Helm is not detected! Attempting to install Helm using winget..." -ForegroundColor Yellow
    try {
        winget install Helm.Helm --accept-source-agreements --accept-package-agreements
        $env:Path = [System.Environment]::GetEnvironmentVariable("Path","Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path","User")
    } catch {
        Write-Log "Failed to install/load Helm automatically." -ForegroundColor Red
        exit
    }
} else {
    Write-Log "✅ Helm is already installed." -ForegroundColor Green
}


Write-Host "`n==========================================================" -ForegroundColor Cyan
Write-Host "1. Running Jenkins, PostgreSQL, and MinIO (Docker Compose)" -ForegroundColor Yellow
Write-Host "==========================================================" -ForegroundColor Cyan
# Authenticates to Docker Hub and spins up containers for Jenkins, PostgreSQL, MinIO, and Nexus.
if (-not [string]::IsNullOrWhiteSpace($env:DOCKER_USER) -and -not [string]::IsNullOrWhiteSpace($env:DOCKER_PASS)) {
    Write-Log "Logging in to Docker Hub as $($env:DOCKER_USER)..." -ForegroundColor Cyan
    $env:DOCKER_PASS | docker login --username $env:DOCKER_USER --password-stdin
    if ($LASTEXITCODE -ne 0) {
        Write-Log "❌ Docker login failed! Please check your credentials in .env" -ForegroundColor Red
        exit
    } else {
        Write-Log "✅ Docker login successful!" -ForegroundColor Green
    }
} else {
    Write-Log "⚠️ DOCKER_USER or DOCKER_PASS not found in .env, skipping explicit login..." -ForegroundColor Yellow
}

# Fixes directory ownership permissions for Jenkins and Nexus volumes, then extracts the initial Jenkins admin password directly from inside the container.
Write-Host "Fixing volume permissions for Jenkins..." -ForegroundColor Cyan
docker run --rm -v npm_jenkins_home:/var/jenkins_home alpine chown -R 1000:1000 /var/jenkins_home 2>$null
docker run --rm -v nexus_data:/nexus-data alpine chown -R 200:200 /nexus-data 2>$null
$composeImageName = "npm-jenkins"

Write-Log "🔍 Checking the availability of a custom Docker image ($composeImageName)..." -ForegroundColor Yellow
$imageExists = docker images -q $composeImageName 2>$null
if ([string]::IsNullOrWhiteSpace($imageExists)) {
    Write-Log "⚙️ Image not yet available locally. Initiating initial build process." -ForegroundColor Cyan
    # docker build -t npm-jenkins -f Dockerfile.win .
    docker compose up -d --build
} else {
    Write-Log "✅ Image '$composeImageName' Already available. Launching the container immediately." -ForegroundColor Green
    docker compose up -d
}
Write-Log "`nWaiting for Docker containers to initialize (20s)..." -ForegroundColor Magenta
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
# Deploys ArgoCD to the K3s cluster and waits until all pods achieve a ready state.
kubectl create namespace argocd
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
Write-Log "`nWaiting for Argo CD pods to become ready (this takes a few minutes)..." -ForegroundColor Magenta
kubectl wait --for=condition=ready pod --all -n argocd --timeout=300s
$argocdPass = "P4ssw0rdArgoCD"
Write-Log "`nLocking the ArgoCD admin password..." -ForegroundColor Green

#Generates a custom ArgoCD admin password using native Bcrypt hashing, patches the Kubernetes secret, applies the Ingress manifest, and restarts the pod to apply changes.
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
Write-Log "`nApplying ArgoCD local manifest (ConfigMap & Ingress)..." -ForegroundColor Yellow
kubectl apply -f k8s/argocd.yaml
# Restart the pod so it reads the newly applied insecure ConfigMap
kubectl rollout restart deploy/argocd-server -n argocd
kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=argocd-server -n argocd --timeout=120s
Write-Log "[SUCCESS] The ArgoCD password has been successfully locked to: $argocdPass" -ForegroundColor Green


# Sequentially executes K3s installations via Helm for the Nginx Ingress Controller, PGAdmin, the monitoring stack (Prometheus & Grafana), HashiCorp Vault, and the ActiveMQ Artemis message broker.
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
Write-Host "5. Setup Prometheus & Grafana on Kubernetes (K3s)" -ForegroundColor Yellow
Write-Host "==========================================================" -ForegroundColor Cyan
kubectl create namespace monitoring --dry-run=client -o yaml | kubectl apply -f -
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo update

helm upgrade --install prometheus-stack prometheus-community/kube-prometheus-stack -n monitoring --reuse-values `
    --set grafana.ingress.enabled=true `
    --set grafana.ingress.ingressClassName=nginx `
    --set "grafana.ingress.hosts={grafana.local}" `
    --set prometheus.service.type=LoadBalancer `
    --set prometheus.service.port=9090

Write-Host "`nWaiting for the Grafana pod to reach a ready state." -ForegroundColor Magenta
Start-Sleep -Seconds 15
kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=grafana -n monitoring --timeout=300s


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
Write-Host "7. Setup ActiveMQ Artemis on Kubernetes (K3s via Manifest)" -ForegroundColor Yellow
Write-Host "==========================================================" -ForegroundColor Cyan
Write-Host "Creating 'artemis' namespace..." -ForegroundColor Cyan
kubectl create namespace artemis --dry-run=client -o yaml | kubectl apply -f -

Write-Log "Injecting Artemis Credentials from .env to Kubernetes Secret..." -ForegroundColor Cyan
kubectl create secret generic artemis-credentials -n artemis `
    --from-literal=ARTEMIS_USER="$env:ARTEMIS_USER" `
    --from-literal=ARTEMIS_PASSWORD="$env:ARTEMIS_PASSWORD" `
    --dry-run=client -o yaml | kubectl apply -f -

Write-Log "Applying Artemis StatefulSet Manifest." -ForegroundColor Cyan
kubectl apply -f k8s/artemis.yaml

Write-Log "`nWaiting for the Artemis Pod to reach ready status." -ForegroundColor Magenta
Start-Sleep -Seconds 10
kubectl wait --for=condition=ready pod -l app=artemis -n artemis --timeout=300s

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

# 1. Complete cleanup of global resources & legacy namespaces
Write-Log "Cleaning up global resources and previous Vault installations." -ForegroundColor Cyan
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
        Write-Log "✅ Successfully deleted the old lock file ($keyFile)." -ForegroundColor Green
    } catch {
        Write-Log "⚠️ Failed to delete $keyFile; the file may be in use by another process." -ForegroundColor Yellow
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

# Executes cluster initialization (1 key share), saves the root token to vault-keys.json, performs an automatic unseal, and enables the KV v2 Secrets Engine.
Write-Log "`nWaiting for Vault pod to be created..." -ForegroundColor Magenta
Start-Sleep -Seconds 10
kubectl wait --for=condition=ready pod/vault-0 -n vault --timeout=120s
Write-Log "`nChecking Vault Initialization and Seal Status..." -ForegroundColor Yellow
$vaultStatusJson = kubectl exec -n vault vault-0 -- vault status -format=json 2>$null
$vaultStatus = $vaultStatusJson | ConvertFrom-Json
if ($vaultStatus.initialized -eq $false) {
    Write-Log "⚙️ Vault has not been initialized. Starting the initialization process (1 Key Share)." -ForegroundColor Cyan
    $initResult = kubectl exec -n vault vault-0 -- vault operator init -key-shares=1 -key-threshold=1 -format=json
    $initResult | Out-File -FilePath $keyFile -Encoding utf8
    Write-Log "✅ Vault initialized! New key stored in '$keyFile'." -ForegroundColor Green
} else {
    Write-Log "✅ Vault has already been initialized." -ForegroundColor Green
}
# Reading tokens and keys from a new local file
if (-not (Test-Path $keyFile)) {
    Write-Log "❌ File $keyFile not found! Unable to perform unseal." -ForegroundColor Red
    exit
}
$vaultKeys = Get-Content $keyFile | ConvertFrom-Json
$unsealKey = $vaultKeys.unseal_keys_b64[0]
$VaultRootToken = $vaultKeys.root_token
# Checking whether Vault is in a Sealed (locked) state
$vaultStatusJson = kubectl exec -n vault vault-0 -- vault status -format=json 2>$null
$vaultStatus = $vaultStatusJson | ConvertFrom-Json
if ($vaultStatus.sealed -eq$true) {
    Write-Log "🔐 Vault is in a Sealed state. Performing automatic unseal." -ForegroundColor Cyan
    kubectl exec -n vault vault-0 -- vault operator unseal $unsealKey | Out-Null
    Write-Log "🔓 Vault successfully unsealed!" -ForegroundColor Green
} else {
    Write-Log "🔓 The vault is already in an unsealed state.." -ForegroundColor Green
}

Write-Log "`nChecking and enabling the KV Secrets Engine at the path 'secret/'" -ForegroundColor Yellow
kubectl exec -n vault vault-0 -- vault login $VaultRootToken | Out-Null
$secretsList = kubectl exec -n vault vault-0 -- vault secrets list -format=json 2>$null
$secretsObj = $secretsList | ConvertFrom-Json
if (-not $secretsObj.'secret/') {
    Write-Log "⚙️ The 'secret/' path is not yet active. Activating the KV v2 engine." -ForegroundColor Cyan
    kubectl exec -n vault vault-0 -- vault secrets enable -path=secret -version=2 kv | Out-Null
    Write-Log "✅ KV v2 Engine successfully activated in 'secret/'!" -ForegroundColor Green
} else {
    Write-Log "✅ Path 'secret/' already active." -ForegroundColor Green
}

Write-Log "`nStoring all service & Jenkins credentials into Vault." -ForegroundColor Yellow
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
Write-Log "✅ All credentials have been successfully exported to the KV Vault (secret/)." -ForegroundColor Green

Write-Log "📦 Uploading Local Binary Files to Nexus Repository" -ForegroundColor Yellow
# Communicates with the local Nexus REST API to create a raw-type repository named raw-binaries and Uploads local binary files from the bin folder to the Nexus repository using curl.
$ProgressPreference = 'SilentlyContinue'
$binFolder = "$env:LOCAL_PROJECT_PATH\bin"
$nexusUrl = "http://127.0.0.1:8082"
$repoName = "raw-binaries"
$nexusPass = $env:NEXUS_PASSWORD
if ([string]::IsNullOrWhiteSpace($nexusPass)) {
    Write-Log "⚠️ NEXUS_PASSWORD not found in .env! Skipping the automatic upload process." -ForegroundColor Red
} else {
    Write-Log "Checking and creating repository '$repoName' in Nexus." -ForegroundColor Cyan
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
        Write-Log "✅ Repository '$repoName' successfully created via API." -ForegroundColor Green
    } catch {
        $statusCode = $_.Exception.Response.StatusCode.Value__
        if ($statusCode -eq 401) {
            Write-Log "❌ Authentication Failed! The Nexus password is incorrect. Ensure that NEXUS_PASSWORD in the .env file is valid." -ForegroundColor Red
            $authFailed = $true
        } elseif ($statusCode -eq 400 -or $statusCode -eq 422) {
            Write-Log "❌ Failed to create repository. API payload rejected by Nexus." -ForegroundColor Red
            $authFailed = $true
        } else {
            Write-Log "✅ Repository '$repoName' already available in the system." -ForegroundColor Green
        }
    }

    if (-not $authFailed) {
        if (Test-Path $binFolder) {
            $files = Get-ChildItem -Path $binFolder -File
            if ($files.Count -gt 0) {
                foreach ($file in $files) {
                    Write-Log "⬆️ Uploading $($file.Name) to Nexus." -ForegroundColor Yellow
                    $uploadUrl = "$nexusUrl/repository/$repoName/$($file.Name)"
                    
                    $curlOutput = curl.exe --silent --show-error --fail -u "admin:$nexusPass" -T "$($file.FullName)" "$uploadUrl" 2>&1
                    
                    if ($LASTEXITCODE -eq 0) {
                        Write-Log "✅ Successfully uploaded $($file.Name)." -ForegroundColor Green
                    } else {
                        Write-Log "⚠️ Failed to upload $($file.Name). Error details: $curlOutput" -ForegroundColor Red
                    }
                }
            } else {
                Write-Log "⚠️ Folder $binFolder is empty." -ForegroundColor Yellow
            }
        } else {
            Write-Log "⚠️ Folder $binFolder not found." -ForegroundColor Yellow
        }
    }
}
$ProgressPreference = 'Continue'

Write-Host "`n==========================================================" -ForegroundColor Green
Write-Host "Done! Setup successful." -ForegroundColor Green
Write-Host "==========================================================" -ForegroundColor Green
Write-Host "ACCESS YOUR SERVICES:"
Write-Log " - Jenkins    : http://localhost:8080"
Write-Log "   InitAdmin  : $jenkinsPass (Login: jenkins / jenkins)" -ForegroundColor Green
Write-Log " - Nexus 3    : http://localhost:8082 (User: admin, Pass: $nexusPass)" -ForegroundColor Green
Write-Log " - Argo CD    : http://argocd.local (User: admin, Pass: $argocdPass)" -ForegroundColor Green
Write-Log " - Artemis    : http://localhost:8161 (User: $($env:ARTEMIS_USER), Pass: $($env:ARTEMIS_PASSWORD))" -ForegroundColor Green
Write-Log " - Grafana    : http://grafana.local (User: admin, Pass: $grafanaPass)" -ForegroundColor Green
Write-Log " - Prometheus : http://localhost:9090" -ForegroundColor Green
Write-Log " - PGAdmin    : http://localhost:8081 (User: $($env:PGADMIN_EMAIL), Pass: $($env:PGADMIN_PASSWORD))"
Write-Log " - PostgreSQL : localhost:5432 (User: postgres, Pass: $($env:POSTGRES_PASSWORD))"
Write-Log " - MinIO      : http://localhost:9001 (User: $($env:MINIO_ROOT_USER), Pass: $($env:MINIO_ROOT_PASSWORD))" -ForegroundColor Green
Write-Log " - Vault      : http://localhost:8200 (Token: $VaultRootToken)" -ForegroundColor Green
Write-Host "==========================================================" -ForegroundColor Green
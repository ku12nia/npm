# ==============================================================================
# DEVOPS LAB AUTOMATION SCRIPT (K3s, Docker, Vault, ArgoCD, Nexus, Terraform)
# ==============================================================================

function Write-Log {
    param (
        [Parameter(Mandatory=$true)]
        [string]$Message,
        [System.ConsoleColor]$ForegroundColor = [System.ConsoleColor]::White
    )
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    Write-Host "[$timestamp] $Message" -ForegroundColor $ForegroundColor
}

# ==============================================================================
# PHASE 0: PREREQUISITES & ENVIRONMENT SETUP
# ==============================================================================
Write-Host "`n==========================================================" -ForegroundColor Cyan
Write-Host "0. Prerequisite & Environment Setup" -ForegroundColor Yellow
Write-Host "==========================================================" -ForegroundColor Cyan

if (Test-Path ".env") {
    Write-Log "Loading environment variables from .env file..." -ForegroundColor Cyan
    Get-Content ".env" | ForEach-Object {
        if ($_ -match '^\s*([^#\s][^=]+)=(.*)$') {
            $name  = $matches[1].Trim()
            $value = $matches[2].Trim()
            [Environment]::SetEnvironmentVariable($name, $value, "Process")
        }
    }
    Write-Log "✅ .env loaded successfully." -ForegroundColor Green
} else {
    Write-Log "⚠️ Warning: .env file not found! Please create it before proceeding." -ForegroundColor Red
    exit 1
}

$WorkspaceName = if ($env:WORKSPACE_NAME) { $env:WORKSPACE_NAME } else { "npm-cicd" }
$WorkspaceDir = "/var/jenkins_home/workspace/$WorkspaceName"

# Check & Install Helm CLI
if (-not (Get-Command helm -ErrorAction SilentlyContinue)) {
    Write-Log "Helm is not detected! Attempting to install Helm using winget..." -ForegroundColor Yellow
    try {
        winget install Helm.Helm --accept-source-agreements --accept-package-agreements | Out-Null
        $env:Path = [System.Environment]::GetEnvironmentVariable("Path","Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path","User")
        Write-Log "✅ Helm successfully installed." -ForegroundColor Green
    } catch {
        Write-Log "❌ Failed to install Helm automatically." -ForegroundColor Red
        exit 1
    }
} else {
    Write-Log "✅ Helm is already installed." -ForegroundColor Green
}

# Check & Install Terraform CLI
if (-not (Get-Command terraform -ErrorAction SilentlyContinue)) {
    Write-Log "Terraform tidak ditemukan! Mencoba menginstal via winget..." -ForegroundColor Yellow
    try {
        winget install Hashicorp.Terraform --accept-source-agreements --accept-package-agreements | Out-Null
        $env:Path = [System.Environment]::GetEnvironmentVariable("Path","Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path","User")
        Write-Log "✅ Terraform berhasil diinstal." -ForegroundColor Green
    } catch {
        Write-Log "⚠️ Gagal menginstal Terraform secara otomatis. Harap instal manual." -ForegroundColor Yellow
    }
} else {
    Write-Log "✅ Terraform sudah terpasang." -ForegroundColor Green
}


# ==============================================================================
# PHASE 1: DOCKER COMPOSE SERVICES (Jenkins, PostgreSQL, MinIO, Nexus)
# ==============================================================================
Write-Host "`n==========================================================" -ForegroundColor Cyan
Write-Host "1. Local Services via Docker Compose" -ForegroundColor Yellow
Write-Host "==========================================================" -ForegroundColor Cyan

if (-not [string]::IsNullOrWhiteSpace($env:DOCKER_USER) -and -not [string]::IsNullOrWhiteSpace($env:DOCKER_PASS)) {
    Write-Log "Logging in to Docker Hub as $($env:DOCKER_USER)..." -ForegroundColor Cyan
    $env:DOCKER_PASS | docker login --username $env:DOCKER_USER --password-stdin | Out-Null
    if ($LASTEXITCODE -ne 0) {
        Write-Log "❌ Docker login failed! Check your credentials in .env" -ForegroundColor Red
        exit 1
    } else {
        Write-Log "✅ Docker login successful!" -ForegroundColor Green
    }
} else {
    Write-Log "⚠️ DOCKER_USER/DOCKER_PASS not found, skipping explicit login..." -ForegroundColor Yellow
}

Write-Log "Fixing volume permissions for Jenkins and Nexus..." -ForegroundColor Cyan
docker run --rm -v npm_jenkins_home:/var/jenkins_home alpine chown -R 1000:1000 /var/jenkins_home 2>$null
docker run --rm -v nexus_data:/nexus-data alpine chown -R 200:200 /nexus-data 2>$null

Write-Log "Launching Docker Compose stack..." -ForegroundColor Cyan
docker compose up -d --build --force-recreate

Write-Log "Waiting for Docker containers to initialize (20s)..." -ForegroundColor Magenta
Start-Sleep -Seconds 20

# Extract Jenkins Initial Password
$jenkinsId = docker ps -q --filter "name=jenkins"
$jenkinsPass = ""
if ($jenkinsId) {
    $rawPass = docker exec $jenkinsId cat /var/jenkins_home/secrets/initialAdminPassword 2>$null
    if ($rawPass) { $jenkinsPass = $rawPass.Trim() }
}
if ([string]::IsNullOrWhiteSpace($jenkinsPass)) {
    $jenkinsPass = "Already initialized; use registered credentials."
}


# ==============================================================================
# PHASE 2: KUBERNETES CORE NETWORKING (Ingress-Nginx)
# ==============================================================================
Write-Host "`n==========================================================" -ForegroundColor Cyan
Write-Host "2. Setup Nginx Ingress Controller" -ForegroundColor Yellow
Write-Host "==========================================================" -ForegroundColor Cyan

helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx | Out-Null
helm repo update | Out-Null
helm upgrade --install ingress-nginx ingress-nginx/ingress-nginx `
    --namespace ingress-nginx `
    --create-namespace `
    --set controller.service.type=LoadBalancer | Out-Null
Write-Log "✅ Ingress Nginx ready." -ForegroundColor Green


# ==============================================================================
# PHASE 3: ARGO CD SETUP & PASSWORD LOCKING
# ==============================================================================
Write-Host "`n==========================================================" -ForegroundColor Cyan
Write-Host "3. Setup Argo CD on Kubernetes (K3s)" -ForegroundColor Yellow
Write-Host "==========================================================" -ForegroundColor Cyan

kubectl create namespace argocd --dry-run=client -o yaml | kubectl apply -f - | Out-Null
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml | Out-Null

Write-Log "Waiting for Argo CD pods to become ready..." -ForegroundColor Magenta
kubectl wait --for=condition=ready pod --all -n argocd --timeout=300s | Out-Null

$argocdPass = "P4ssw0rdArgoCD"
Write-Log "Locking the ArgoCD admin password..." -ForegroundColor Cyan

$bcryptOutput = kubectl exec -n argocd deploy/argocd-server -- argocd account bcrypt --password $argocdPass 2>$null
$bcryptHash = ($bcryptOutput | Select-Object -Last 1).Trim()
$encodedHash = [Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($bcryptHash))
$encodedMtime = [Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes((Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")))

$patchContent = "{ `"data`": { `"admin.password`": `"$encodedHash`", `"admin.passwordMtime`": `"$encodedMtime`" } }"
$patchContent | Out-File -FilePath "argo-patch.json" -Encoding utf8
kubectl patch secret argocd-secret -n argocd --type='merge' --patch-file argo-patch.json | Out-Null
Remove-Item "argo-patch.json" -ErrorAction SilentlyContinue
kubectl delete secret argocd-initial-admin-secret -n argocd --ignore-not-found=true | Out-Null

kubectl apply -f k8s/argocd.yaml | Out-Null
kubectl rollout restart deploy/argocd-server -n argocd | Out-Null
kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=argocd-server -n argocd --timeout=120s | Out-Null
Write-Log "✅ ArgoCD successfully configured." -ForegroundColor Green


# ==============================================================================
# PHASE 4: PGADMIN SETUP
# ==============================================================================
Write-Host "`n==========================================================" -ForegroundColor Cyan
Write-Host "4. Setup PGAdmin on Kubernetes" -ForegroundColor Yellow
Write-Host "==========================================================" -ForegroundColor Cyan

helm repo add runix https://helm.runix.net | Out-Null
helm repo update | Out-Null
helm upgrade --install pgadmin runix/pgadmin4 -n default `
    --set env.email="$env:PGADMIN_EMAIL" `
    --set env.password="$env:PGADMIN_PASSWORD" `
    --set service.type=LoadBalancer `
    --set service.port=8081 | Out-Null
Write-Log "✅ PGAdmin deployed." -ForegroundColor Green


# ==============================================================================
# PHASE 5: HASHICORP VAULT (Deployment, Unseal, & Secret Population)
# ==============================================================================
Write-Host "`n==========================================================" -ForegroundColor Cyan
Write-Host "5. Setup HashiCorp Vault on Kubernetes (Production Mode)" -ForegroundColor Yellow
Write-Host "==========================================================" -ForegroundColor Cyan

Write-Log "Cleaning up previous Vault installations..." -ForegroundColor Cyan
helm uninstall vault -n vault --no-hooks --ignore-not-found 2>$null
kubectl delete namespace vault --force --grace-period=0 --ignore-not-found 2>$null
kubectl delete mutatingwebhookconfiguration,validatingwebhookconfiguration -l app.kubernetes.io/name=vault --ignore-not-found=true 2>$null
kubectl delete clusterrole,clusterrolebinding -l app.kubernetes.io/name=vault --ignore-not-found=true 2>$null

$keyFile = "vault-keys.json"
if (Test-Path $keyFile) { Remove-Item $keyFile -Force -ErrorAction SilentlyContinue }

kubectl create namespace vault --dry-run=client -o yaml | kubectl apply -f - | Out-Null
helm repo add hashicorp https://helm.releases.hashicorp.com | Out-Null
helm repo update | Out-Null

helm upgrade --install vault hashicorp/vault -n vault `
    --set "server.dev.enabled=false" `
    --set "server.dataStorage.enabled=true" `
    --set "server.dataStorage.size=1Gi" `
    --set "injector.enabled=true" `
    --set "ui.enabled=true" `
    --set "ui.serviceType=LoadBalancer" `
    --set "ui.externalPort=8200" | Out-Null

Write-Log "Waiting for Vault pod to be ready..." -ForegroundColor Magenta
kubectl wait --for=condition=ready pod/vault-0 -n vault --timeout=120s | Out-Null

$vaultStatus = kubectl exec -n vault vault-0 -- vault status -format=json 2>$null | ConvertFrom-Json
if (-not $vaultStatus.initialized) {
    Write-Log "⚙️ Initializing Vault (1 Key Share)..." -ForegroundColor Cyan
    kubectl exec -n vault vault-0 -- vault operator init -key-shares=1 -key-threshold=1 -format=json | Out-File -FilePath $keyFile -Encoding utf8
    Write-Log "✅ Vault initialized & keys saved." -ForegroundColor Green
} else {
    Write-Log "✅ Vault was already initialized." -ForegroundColor Green
}

if (-not (Test-Path $keyFile)) {
    Write-Log "❌ File $keyFile not found! Cannot unseal." -ForegroundColor Red
    exit 1
}

$vaultKeys = Get-Content $keyFile | ConvertFrom-Json
$unsealKey = $vaultKeys.unseal_keys_b64[0]
$vaultRootToken = $vaultKeys.root_token

$vaultStatus = kubectl exec -n vault vault-0 -- vault status -format=json 2>$null | ConvertFrom-Json
if ($vaultStatus.sealed) {
    Write-Log "🔐 Unsealing Vault..." -ForegroundColor Cyan
    kubectl exec -n vault vault-0 -- vault operator unseal $unsealKey | Out-Null
    Write-Log "🔓 Vault unsealed successfully!" -ForegroundColor Green
} else {
    Write-Log "🔓 Vault is already unsealed." -ForegroundColor Green
}

# Enable KV v2 Secrets Engine
kubectl exec -n vault vault-0 -- vault login $vaultRootToken | Out-Null
$secretsList = kubectl exec -n vault vault-0 -- vault secrets list -format=json 2>$null | ConvertFrom-Json
if (-not $secretsList.'secret/') {
    kubectl exec -n vault vault-0 -- vault secrets enable -path=secret -version=2 kv | Out-Null
    Write-Log "✅ KV v2 Secrets Engine enabled at 'secret/'." -ForegroundColor Green
} else {
    Write-Log "✅ Path 'secret/' already active." -ForegroundColor Green
}

# Populate Secrets Map
Write-Log "Storing service credentials into Vault..." -ForegroundColor Yellow
$secretsMap = @{
    "secret/database/postgres"  = @{ username = "postgres"; password = "$env:POSTGRES_PASSWORD" }
    "secret/pgadmin"            = @{ admin_email = "$env:PGADMIN_EMAIL"; admin_password = "$env:PGADMIN_PASSWORD" }
    "secret/minio"              = @{ root_user = "$env:MINIO_ROOT_USER"; root_password = "$env:MINIO_ROOT_PASSWORD" }
    "secret/artemis"            = @{ admin_user = "$env:ARTEMIS_USER"; admin_password = "$env:ARTEMIS_PASSWORD" }
    "secret/nexus"              = @{ admin_user = "admin"; admin_password = "$env:NEXUS_PASSWORD" }
    "secret/argocd"             = @{ admin_user = "admin"; admin_password = "$argocdPass" }
    "secret/jenkins/admin"      = @{ admin_user = "jenkins"; admin_password = "$env:JENKINS_PASSWORD" }
    "secret/jenkins/github"     = @{ username = "$env:GITHUB_USER"; token = "$env:GITHUB_TOKEN" }
    "secret/jenkins/dockerhub"  = @{ username = "$env:DOCKER_USER"; password = "$env:DOCKER_PASS" }
}

foreach ($path in $secretsMap.Keys) {
    $pairs = $secretsMap[$path]
    $argString = ""
    foreach ($k in $pairs.Keys) {
        $val = $pairs[$k]
        if (-not [string]::IsNullOrEmpty($val)) {
            $argString += "$k=`"$val`" "
        }
    }
    if ($argString) {
        kubectl exec -n vault vault-0 -- vault kv put $path $argString | Out-Null
    }
}
Write-Log "✅ All credentials successfully exported to Vault." -ForegroundColor Green


# ==============================================================================
# PHASE 6: NEXUS REPOSITORY & BINARY UPLOADS
# ==============================================================================
Write-Host "`n==========================================================" -ForegroundColor Cyan
Write-Host "6. Nexus Binary Uploads" -ForegroundColor Yellow
Write-Host "==========================================================" -ForegroundColor Cyan

$ProgressPreference = 'SilentlyContinue'
$binFolder = "$env:LOCAL_PROJECT_PATH\bin"
$nexusUrl = "http://127.0.0.1:8082"
$repoName = "raw-binaries"
$nexusPass = $env:NEXUS_PASSWORD

if ([string]::IsNullOrWhiteSpace($nexusPass)) {
    Write-Log "⚠️ NEXUS_PASSWORD not found in .env! Skipping Nexus uploads." -ForegroundColor Red
} else {
    $base64AuthInfo = [Convert]::ToBase64String([System.Text.Encoding]::ASCII.GetBytes(("admin:{0}" -f $nexusPass)))
    $headers = @{
        Authorization  = ("Basic {0}" -f $base64AuthInfo)
        "Content-Type" = "application/json"
    }
    $repoPayload = @{
        name   = $repoName
        online = $true
        storage = @{
            blobStoreName               = "default"
            strictContentTypeValidation = false
            writePolicy                 = "ALLOW"
        }
        raw = @{ contentDisposition = "ATTACHMENT" }
    } | ConvertTo-Json -Depth 10

    $authFailed = $false
    try {
        Invoke-RestMethod -Uri "$nexusUrl/service/rest/v1/repositories/raw/hosted" -Method Post -Headers $headers -Body $repoPayload -ErrorAction Stop | Out-Null
        Write-Log "✅ Repository '$repoName' created via API." -ForegroundColor Green
    } catch {
        $statusCode = $_.Exception.Response.StatusCode.Value__
        if ($statusCode -eq 401) {
            Write-Log "❌ Authentication Failed! Invalid Nexus password." -ForegroundColor Red
            $authFailed = $true
        } elseif ($statusCode -eq 400 -or $statusCode -eq 422) {
            Write-Log "❌ Payload rejected by Nexus API." -ForegroundColor Red
            $authFailed = $true
        } else {
            Write-Log "✅ Repository '$repoName' already exists." -ForegroundColor Green
        }
    }

    if (-not $authFailed -and (Test-Path $binFolder)) {
        $files = Get-ChildItem -Path $binFolder -File
        if ($files.Count -gt 0) {
            foreach ($file in $files) {
                Write-Log "⬆️ Uploading $($file.Name) to Nexus..." -ForegroundColor Yellow
                $uploadUrl = "$nexusUrl/repository/$repoName/$($file.Name)"
                $curlOutput = curl.exe --silent --show-error --fail -u "admin:$nexusPass" -T "$($file.FullName)" "$uploadUrl" 2>&1
                if ($LASTEXITCODE -eq 0) {
                    Write-Log "✅ Uploaded $($file.Name)." -ForegroundColor Green
                } else {
                    Write-Log "⚠️ Failed to upload $($file.Name): $curlOutput" -ForegroundColor Red
                }
            }
        } else {
            Write-Log "⚠️ Folder $binFolder is empty." -ForegroundColor Yellow
        }
    }
}
$ProgressPreference = 'Continue'


# ==============================================================================
# FINAL ACCESS DASHBOARD
# ==============================================================================
Write-Host "`n==========================================================" -ForegroundColor Green
Write-Host "✅ Done! All components successfully installed & configured." -ForegroundColor Green
Write-Host "==========================================================" -ForegroundColor Green
Write-Host "ACCESS YOUR SERVICES:"
Write-Log " - Jenkins    : http://localhost:8080"
Write-Log "   InitAdmin  : $jenkinsPass (Login: jenkins / jenkins)" -ForegroundColor Green
Write-Log " - Argo CD    : http://argocd.local (User: admin, Pass: $argocdPass)" -ForegroundColor Green
Write-Log " - Nexus 3    : http://localhost:8082 (User: admin, Pass: $nexusPass)" -ForegroundColor Green
Write-Log " - SonarQube  : http://localhost:9002 (User: admin, Pass: admin)" -ForegroundColor Green
Write-Log " - PostgreSQL : localhost:5432 (User: postgres, Pass: $($env:POSTGRES_PASSWORD))"
Write-Log " - PGAdmin    : http://localhost:8081 (User: $($env:PGADMIN_EMAIL), Pass: $($env:PGADMIN_PASSWORD))"
Write-Log " - Vault      : http://localhost:8200 (Token: $vaultRootToken)" -ForegroundColor Green
Write-Host "==========================================================" -ForegroundColor Green
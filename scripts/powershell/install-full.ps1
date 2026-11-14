# ==============================================================================
# DEVOPS LAB AUTOMATION - UNIFIED MASTER DEPLOYMENT SCRIPT
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


Write-Host "==========================================================" -ForegroundColor Cyan
Write-Host "PHASE 0: PREREQUISITES & ENVIRONMENT SETUP" -ForegroundColor Yellow
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
$WorkspaceDir  = "/var/jenkins_home/workspace/$WorkspaceName"
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
    Write-Log "Terraform is not detected! Attempting to install Terraform using winget..." -ForegroundColor Yellow
    try {
        winget install Hashicorp.Terraform --accept-source-agreements --accept-package-agreements | Out-Null
        $env:Path = [System.Environment]::GetEnvironmentVariable("Path","Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path","User")
        Write-Log "✅ Terraform installed successfully." -ForegroundColor Green
    } catch {
        Write-Log "⚠️ Failed to install Terraform automatically. Please install it manually." -ForegroundColor Yellow
    }
} else {
    Write-Log "✅ Terraform is already installed on the host." -ForegroundColor Green
}


Write-Host "`n==========================================================" -ForegroundColor Cyan
Write-Host "PHASE 1: DOCKER COMPOSE SERVICES (Jenkins, PostgreSQL, MinIO, Nexus)" -ForegroundColor Yellow
Write-Host "==========================================================" -ForegroundColor Cyan
if (-not [string]::IsNullOrWhiteSpace($env:DOCKER_USER) -and -not [string]::IsNullOrWhiteSpace($env:DOCKER_PASS)) {
    Write-Log "Logging in to Docker Hub as $($env:DOCKER_USER)..." -ForegroundColor Cyan
    $env:DOCKER_PASS | docker login --username $env:DOCKER_USER --password-stdin | Out-Null
    if ($LASTEXITCODE -ne 0) {
        Write-Log "❌ Docker login failed! Please check your credentials in .env" -ForegroundColor Red
        exit 1
    } else {
        Write-Log "✅ Docker login successful!" -ForegroundColor Green
    }
} else {
    Write-Log "⚠️ DOCKER_USER or DOCKER_PASS not found in .env, skipping explicit login..." -ForegroundColor Yellow
}

Write-Log "Fixing volume permissions for Jenkins and Nexus..." -ForegroundColor Cyan
docker run --rm -v npm_jenkins_home:/var/jenkins_home alpine chown -R 1000:1000 /var/jenkins_home 2>$null
docker run --rm -v nexus_data:/nexus-data alpine chown -R 200:200 /nexus-data 2>$null

$composeImageName = "npm-jenkins"
Write-Log "🔍 Checking custom Docker image ($composeImageName)..." -ForegroundColor Yellow
$imageExists = docker images -q $composeImageName 2>$null
try {
    Push-Location "config"
    if ([string]::IsNullOrWhiteSpace($imageExists)) {
        Write-Log "⚙️ Image not yet available locally. Initiating build via Docker Compose." -ForegroundColor Cyan
        docker compose up -d --build --force-recreate
    } else {
        Write-Log "✅ Image '$composeImageName' already available. Launching containers." -ForegroundColor Green
        docker compose up -d --force-recreate
    }
}
finally {
    Pop-Location
}
Write-Log "Waiting for Docker containers to initialize (20s)..." -ForegroundColor Magenta
Start-Sleep -Seconds 20

# Retrieve Jenkins Admin Password
$jenkinsId   = docker ps -q --filter "name=jenkins"
$jenkinsPass = ""
if ($jenkinsId) {
    $rawPass = docker exec $jenkinsId cat /var/jenkins_home/secrets/initialAdminPassword 2>$null
    if ($rawPass) { $jenkinsPass = $rawPass.Trim() }
}
if ([string]::IsNullOrWhiteSpace($jenkinsPass)) {
    $jenkinsPass = "Already initialized; use existing registered credentials."
}


Write-Host "`n==========================================================" -ForegroundColor Cyan
Write-Host "PHASE 2: ARGO CD SETUP & PASSWORD LOCKING" -ForegroundColor Yellow
Write-Host "==========================================================" -ForegroundColor Cyan
kubectl create namespace argocd --dry-run=client -o yaml | kubectl apply -f - | Out-Null
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml | Out-Null
Write-Log "Waiting for Argo CD pods to become ready..." -ForegroundColor Magenta
kubectl wait --for=condition=ready pod --all -n argocd --timeout=300s | Out-Null
$argocdPass = "P4ssw0rdArgoCD"
Write-Log "Locking the ArgoCD admin password..." -ForegroundColor Cyan
$bcryptOutput  = kubectl exec -n argocd deploy/argocd-server -- argocd account bcrypt --password $argocdPass 2>$null
$bcryptHash    = ($bcryptOutput | Select-Object -Last 1).Trim()
$encodedHash   = [Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($bcryptHash))
$encodedMtime  = [Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes((Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")))
$patchContent  = "{ `"data`": { `"admin.password`": `"$encodedHash`", `"admin.passwordMtime`": `"$encodedMtime`" } }"
$patchContent | Out-File -FilePath "argo-patch.json" -Encoding utf8
kubectl patch secret argocd-secret -n argocd --type='merge' --patch-file argo-patch.json | Out-Null
Remove-Item "argo-patch.json" -ErrorAction SilentlyContinue
kubectl delete secret argocd-initial-admin-secret -n argocd --ignore-not-found=true | Out-Null
kubectl apply -f k8s/argocd.yaml | Out-Null
kubectl rollout restart deploy/argocd-server -n argocd | Out-Null
kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=argocd-server -n argocd --timeout=120s | Out-Null
Write-Log "✅ ArgoCD successfully configured and secured." -ForegroundColor Green


Write-Host "`n==========================================================" -ForegroundColor Cyan
Write-Host "PHASE 3: KUBERNETES CORE NETWORKING (Ingress-Nginx)" -ForegroundColor Yellow
Write-Host "==========================================================" -ForegroundColor Cyan
helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx | Out-Null
helm repo update | Out-Null
helm upgrade --install ingress-nginx ingress-nginx/ingress-nginx `
    --namespace ingress-nginx `
    --create-namespace `
    --set controller.service.type=LoadBalancer | Out-Null
Write-Log "✅ Ingress Nginx ready." -ForegroundColor Green


Write-Host "`n==========================================================" -ForegroundColor Cyan
Write-Host "PHASE 4: PGADMIN SETUP ON KUBERNETES" -ForegroundColor Yellow
Write-Host "==========================================================" -ForegroundColor Cyan
helm repo add runix https://helm.runix.net | Out-Null
helm repo update | Out-Null
helm upgrade --install pgadmin runix/pgadmin4 -n default `
    --set env.email="$env:PGADMIN_EMAIL" `
    --set env.password="$env:PGADMIN_PASSWORD" `
    --set service.type=LoadBalancer `
    --set service.port=8081 | Out-Null
Write-Log "✅ PGAdmin deployed." -ForegroundColor Green


Write-Host "`n==========================================================" -ForegroundColor Cyan
Write-Host "PHASE 5: PROMETHEUS & GRAFANA ON KUBERNETES" -ForegroundColor Yellow
Write-Host "==========================================================" -ForegroundColor Cyan
kubectl create namespace monitoring --dry-run=client -o yaml | kubectl apply -f - | Out-Null
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts | Out-Null
helm repo update | Out-Null
helm upgrade --install prometheus-stack prometheus-community/kube-prometheus-stack -n monitoring --reuse-values `
    --set grafana.ingress.enabled=true `
    --set grafana.ingress.ingressClassName=nginx `
    --set "grafana.ingress.hosts={grafana.local}" `
    --set prometheus.service.type=LoadBalancer `
    --set prometheus.service.port=9090 | Out-Null

Write-Log "Waiting for Grafana pod to reach ready state..." -ForegroundColor Magenta
Start-Sleep -Seconds 15
kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=grafana -n monitoring --timeout=300s | Out-Null
$grafanaPass = ""
$encodedGrafana = kubectl get secret prometheus-stack-grafana -n monitoring -o jsonpath="{.data.admin-password}" 2>$null
if ($encodedGrafana) {
    $grafanaPass = [System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($encodedGrafana))
} else {
    $grafanaPass = "prom-operator"
}
Write-Log "✅ Prometheus & Grafana ready." -ForegroundColor Green


Write-Host "`n==========================================================" -ForegroundColor Cyan
Write-Host "PHASE 6: ACTIVEMQ ARTEMIS ON KUBERNETES" -ForegroundColor Yellow
Write-Host "==========================================================" -ForegroundColor Cyan
kubectl create namespace artemis --dry-run=client -o yaml | kubectl apply -f - | Out-Null
Write-Log "Injecting Artemis Credentials into Kubernetes Secret..." -ForegroundColor Cyan
kubectl create secret generic artemis-credentials -n artemis `
    --from-literal=ARTEMIS_USER="$env:ARTEMIS_USER" `
    --from-literal=ARTEMIS_PASSWORD="$env:ARTEMIS_PASSWORD" `
    --dry-run=client -o yaml | kubectl apply -f - | Out-Null
Write-Log "Applying Artemis StatefulSet Manifest..." -ForegroundColor Cyan
kubectl apply -f k8s/artemis.yaml | Out-Null
Write-Log "Waiting for Artemis Pod to reach ready status..." -ForegroundColor Magenta
Start-Sleep -Seconds 10
kubectl wait --for=condition=ready pod -l app=artemis -n artemis --timeout=300s | Out-Null
Write-Log "✅ ActiveMQ Artemis ready." -ForegroundColor Green


Write-Host "`n==========================================================" -ForegroundColor Cyan
Write-Host "PHASE 7: HASHICORP VAULT (Production Mode & Secret Seeding)" -ForegroundColor Yellow
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
Write-Log "Deploying Vault via Helm (Production Mode with PVC)..." -ForegroundColor Cyan
helm upgrade --install vault hashicorp/vault -n vault `
    --set "server.dev.enabled=false" `
    --set "server.dataStorage.enabled=true" `
    --set "server.dataStorage.size=1Gi" `
    --set "injector.enabled=true" `
    --set "ui.enabled=true" `
    --set "ui.serviceType=LoadBalancer" `
    --set "ui.externalPort=8200" | Out-Null

Write-Log "Waiting for Vault pod to be running..." -ForegroundColor Magenta
while ($true) {
    $podPhase = kubectl get pod vault-0 -n vault -o jsonpath='{.status.phase}' 2>$null
    if ($podPhase -eq "Running") {
        Write-Log "✅ Vault pod is running." -ForegroundColor Green
        break
    }
    Start-Sleep -Seconds 3
}
Start-Sleep -Seconds 5
# Allow a brief pause so that the HTTP server inside the container is ready to accept connections
Write-Log "Checking Vault status..." -ForegroundColor Cyan
$vaultStatusJson = kubectl exec -n vault vault-0 -- vault status -format=json 2>$null
if (-not $vaultStatusJson) {
    Write-Log "❌ Failed to connect to Vault container." -ForegroundColor Red
    exit 1
}
$vaultStatus = $vaultStatusJson | ConvertFrom-Json
if (-not $vaultStatus.initialized) {
    Write-Log "⚙️ Initializing Vault (1 Key Share)..." -ForegroundColor Cyan
    kubectl exec -n vault vault-0 -- vault operator init -key-shares=1 -key-threshold=1 -format=json | Out-File -FilePath $keyFile -Encoding utf8
    Write-Log "✅ Vault initialized & keys saved." -ForegroundColor Green
}

if (-not (Test-Path $keyFile)) {
    Write-Log "❌ File $keyFile not found! Cannot unseal." -ForegroundColor Red
    exit 1
}
$vaultKeys      = Get-Content $keyFile | ConvertFrom-Json
$unsealKey      = $vaultKeys.unseal_keys_b64[0]
$vaultRootToken = $vaultKeys.root_token
# Check the Vault status (whether it is sealed/locked). If it is, perform an automatic unseal; otherwise, skip.
$vaultStatusJson = kubectl exec -n vault vault-0 -- vault status -format=json 2>$null
$vaultStatus     = $vaultStatusJson | ConvertFrom-Json
if ($vaultStatus.sealed) {
    Write-Log "🔐 Unsealing Vault..." -ForegroundColor Cyan
    kubectl exec -n vault vault-0 -- vault operator unseal $unsealKey | Out-Null
    Write-Log "🔓 Vault unsealed successfully!" -ForegroundColor Green
}
# Enable KV v2 Secrets Engine
Write-Log "Enabling KV v2 Secrets Engine at 'secret/' path..." -ForegroundColor Cyan
kubectl exec -n vault vault-0 -- vault login $vaultRootToken | Out-Null
$secretsListJson = kubectl exec -n vault vault-0 -- vault secrets list -format=json 2>$null
$secretsList     = $secretsListJson | ConvertFrom-Json
if (-not $secretsList.'secret/') {
    kubectl exec -n vault vault-0 -- vault secrets enable -path=secret -version=2 kv | Out-Null
    Write-Log "✅ KV v2 Secrets Engine enabled." -ForegroundColor Green
}
# Populate All Secrets via Clean Array Loop
Write-Log "Exporting all credentials to Vault KV..." -ForegroundColor Yellow
$vaultSecrets = @(
    @{ Path = "secret/database/postgres";  Data = @("username=postgres", "password=$env:POSTGRES_PASSWORD") },
    @{ Path = "secret/pgadmin";            Data = @("admin_email=$env:PGADMIN_EMAIL", "admin_password=$env:PGADMIN_PASSWORD") },
    @{ Path = "secret/minio";              Data = @("root_user=$env:MINIO_ROOT_USER", "root_password=$env:MINIO_ROOT_PASSWORD") },
    @{ Path = "secret/artemis";            Data = @("admin_user=$env:ARTEMIS_USER", "admin_password=$env:ARTEMIS_PASSWORD") },
    @{ Path = "secret/nexus";              Data = @("admin_user=admin", "admin_password=$env:NEXUS_PASSWORD") },
    @{ Path = "secret/argocd";             Data = @("admin_user=admin", "admin_password=$argocdPass") },
    @{ Path = "secret/grafana";            Data = @("admin_user=admin", "admin_password=$grafanaPass") },
    @{ Path = "secret/jenkins/admin";      Data = @("admin_user=jenkins", "admin_password=$env:JENKINS_PASSWORD") },
    @{ Path = "secret/jenkins/github";     Data = @("username=$env:GITHUB_USER", "token=$env:GITHUB_TOKEN") },
    @{ Path = "secret/jenkins/dockerhub";  Data = @("username=$env:DOCKER_USER", "password=$env:DOCKER_PASS") }
)
foreach ($secret in $vaultSecrets) {
    $cmdArgs = @("exec", "-n", "vault", "vault-0", "--", "vault", "kv", "put", $secret.Path) + $secret.Data
    & kubectl $cmdArgs | Out-Null
}
Write-Log "✅ All credentials successfully stored in Vault." -ForegroundColor Green


Write-Host "`n==========================================================" -ForegroundColor Cyan
Write-Host "PHASE 8: NEXUS REPOSITORY & BINARY UPLOADS" -ForegroundColor Yellow
Write-Host "==========================================================" -ForegroundColor Cyan

$ProgressPreference = 'SilentlyContinue'
$binFolder  = "$env:LOCAL_PROJECT_PATH\bin"
$nexusUrl   = "http://127.0.0.1:8082"
$repoName   = "raw-binaries"
$nexusPass  = $env:NEXUS_PASSWORD

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
            strictContentTypeValidation = $false
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
        } else {
            Write-Log "✅ Repository '$repoName' already exists. Proceeding to uploads..." -ForegroundColor Green
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
Write-Log " - Grafana    : http://grafana.local (User: admin, Pass: $grafanaPass)" -ForegroundColor Green
Write-Log " - Artemis    : http://localhost:8161 (User: $($env:ARTEMIS_USER), Pass: $($env:ARTEMIS_PASSWORD))" -ForegroundColor Green
Write-Log " - Prometheus : http://localhost:9090" -ForegroundColor Green
Write-Log " - MinIO      : http://localhost:9001 (User: $($env:MINIO_ROOT_USER), Pass: $($env:MINIO_ROOT_PASSWORD))" -ForegroundColor Green
Write-Host "==========================================================" -ForegroundColor Green
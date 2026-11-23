# ==============================================================================
# DEVOPS LAB AUTOMATION - UNIFIED MASTER DEPLOYMENT SCRIPT
# ==============================================================================
$ErrorActionPreference = "Stop"

function Write-Log {
    param (
        [Parameter(Mandatory=$true)]
        [string]$Message,
        [System.ConsoleColor]$ForegroundColor = [System.ConsoleColor]::White
    )
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    Write-Host "[$timestamp] $Message" -ForegroundColor $ForegroundColor
}

# Resolve Project Root dynamically and set working directory
$ProjectRoot = (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path
Set-Location $ProjectRoot

Write-Host "`n==========================================================" -ForegroundColor Cyan
Write-Host "PHASE 0: PREREQUISITES, BINARY VALIDATION & ENV SETUP" -ForegroundColor Yellow
Write-Host "==========================================================" -ForegroundColor Cyan

# 1. Strict .env Check at Project Root
$envFilePath = Join-Path $ProjectRoot ".env"
if (Test-Path -Path $envFilePath -PathType Leaf) {
    Write-Log "Loading environment variables from $envFilePath..." -ForegroundColor Cyan
    Get-Content $envFilePath | ForEach-Object {
        if ($_ -match '^\s*([^#\s][^=]+)=(.*)$') {
            $name  = $matches[1].Trim()
            $value = $matches[2].Trim()
            [Environment]::SetEnvironmentVariable($name, $value, "Process")
        }
    }
    Write-Log "✅ .env loaded successfully." -ForegroundColor Green
} else {
    Write-Log "⚠️ Warning: .env file not found at $envFilePath! Please create it before proceeding." -ForegroundColor Red
    exit 1
}

$WorkspaceName = if ($env:WORKSPACE_NAME) { $env:WORKSPACE_NAME } else { "npm-cicd" }
$WorkspaceDir = "/var/jenkins_home/workspace/$WorkspaceName"

# 2. Strict bin/ Directory Check at Project Root
$binFolderPath = Join-Path $ProjectRoot "bin"
if (Test-Path -Path $binFolderPath -PathType Container) {
    Write-Log "📁 Using project bin folder at: $binFolderPath" -ForegroundColor Cyan
} else {
    Write-Log "⚠️ Warning: 'bin/' folder not found at $binFolderPath! Please create it and place all required binaries before proceeding." -ForegroundColor Red
    exit 1
}

$requiredBinaries = @(
    "docker-24.0.9.tgz",
    "buildx-v0.14.0.linux-amd64",
    "kubectl",
    "argocd-linux-amd64",
    "sonar-scanner-cli-5.0.1.3006-linux.zip",
    "terraform_1.9.0_linux_amd64.zip"
)

$missingFiles = $requiredBinaries | Where-Object { -not (Test-Path (Join-Path $binFolderPath $_)) }
if ($missingFiles.Count -gt 0) {
    Write-Log "⚠️ Warning: Missing binaries detected in $binFolderPath, checking Downloads fallback..." -ForegroundColor Yellow
    $fallbackSource = "C:\Users\evoel\Downloads"
    foreach ($miss in $missingFiles) {
        $possibleSource = Join-Path $fallbackSource $miss
        if (Test-Path $possibleSource) {
            Write-Log "🔄 Auto-copying $miss from $possibleSource to $binFolderPath..." -ForegroundColor Cyan
            Copy-Item -Path $possibleSource -Destination (Join-Path $binFolderPath $miss) -Force
        }
    }

    $stillMissing = $requiredBinaries | Where-Object { -not (Test-Path (Join-Path $binFolderPath $_)) }
    if ($stillMissing.Count -gt 0) {
        Write-Log "❌ Error: Required binaries still missing in '$binFolderPath': $($stillMissing -join ', ')" -ForegroundColor Red
        exit 1
    }
}
Write-Log "✅ All required binaries are complete and verified." -ForegroundColor Green


Write-Host "`n==========================================================" -ForegroundColor Cyan
Write-Host "PHASE 1: DOCKER COMPOSE SERVICES (Jenkins, PostgreSQL, MinIO, Nexus)" -ForegroundColor Yellow
Write-Host "==========================================================" -ForegroundColor Cyan
if (-not [string]::IsNullOrWhiteSpace($env:DOCKER_USER) -and -not [string]::IsNullOrWhiteSpace($env:DOCKER_PASS)) {
    Write-Log "Logging in to Docker Hub as $($env:DOCKER_USER)..." -ForegroundColor Cyan
    $env:DOCKER_PASS | docker login --username $env:DOCKER_USER --password-stdin | Out-Null
    if ($LASTEXITCODE -ne 0) {
        Write-Log "❌ Docker login failed! Please check your credentials in .env" -ForegroundColor Red
        exit 1
    }
    Write-Log "✅ Docker login successful!" -ForegroundColor Green
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
    Push-Location (Join-Path $ProjectRoot "config")
    if ([string]::IsNullOrWhiteSpace($imageExists)) {
        Write-Log "⚙️ Image not yet available locally. Initiating build via Docker Compose." -ForegroundColor Cyan
        docker compose up -d --build --force-recreate
    } else {
        Write-Log "✅ Image '$composeImageName' already available. Launching containers." -ForegroundColor Green
        docker compose up -d --force-recreate
    }
    if ($LASTEXITCODE -ne 0) { Write-Log "❌ Docker Compose failed to start." -ForegroundColor Red; exit 1 }
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
Write-Host "PHASE 2: KUBERNETES CORE NETWORKING (Ingress-Nginx)" -ForegroundColor Yellow
Write-Host "==========================================================" -ForegroundColor Cyan
helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx | Out-Null
helm repo update | Out-Null
helm upgrade --install ingress-nginx ingress-nginx/ingress-nginx `
    --namespace ingress-nginx `
    --create-namespace `
    --set controller.service.type=LoadBalancer `
    --wait --timeout 180s
if ($LASTEXITCODE -ne 0) { Write-Log "❌ Ingress-Nginx deployment failed." -ForegroundColor Red; exit 1 }
Write-Log "✅ Ingress Nginx ready." -ForegroundColor Green


Write-Host "`n==========================================================" -ForegroundColor Cyan
Write-Host "PHASE 3: ARGO CD SETUP, CRD FIX & INGRESS" -ForegroundColor Yellow
Write-Host "==========================================================" -ForegroundColor Cyan
kubectl create namespace argocd --dry-run=client -o yaml | kubectl apply -f -

# Server-Side Apply agar CRD ApplicationSet (>262KB) tidak gagal terpotong
Write-Log "Applying ArgoCD v3.6.1 manifests (Server-Side Apply)..." -ForegroundColor Cyan
kubectl apply --server-side --force-conflicts -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/v3.6.1/manifests/install.yaml
if ($LASTEXITCODE -ne 0) { Write-Log "❌ Failed to apply ArgoCD install.yaml" -ForegroundColor Red; exit 1 }

kubectl wait --for=condition=Established crd/applicationsets.argoproj.io --timeout=60s

Write-Log "Waiting for Argo CD pods to become ready..." -ForegroundColor Magenta
kubectl wait --for=condition=ready pod --all -n argocd --timeout=300s

$argocdPass = "P4ssw0rdArgoCD"
Write-Log "Locking the ArgoCD admin password..." -ForegroundColor Cyan
$bcryptOutput  = kubectl exec -n argocd deploy/argocd-server -- argocd account bcrypt --password $argocdPass
$bcryptHash    = ($bcryptOutput | Select-Object -Last 1).Trim()
$encodedHash   = [Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($bcryptHash))
$encodedMtime  = [Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes((Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")))
$patchContent  = "{ `"data`": { `"admin.password`": `"$encodedHash`", `"admin.passwordMtime`": `"$encodedMtime`" } }"
$patchFile     = Join-Path $ProjectRoot "argo-patch.json"
$patchContent | Out-File -FilePath $patchFile -Encoding utf8
kubectl patch secret argocd-secret -n argocd --type='merge' --patch-file $patchFile
Remove-Item $patchFile -ErrorAction SilentlyContinue
kubectl delete secret argocd-initial-admin-secret -n argocd --ignore-not-found=true

# Apply k8s/argocd.yaml (Ingress argocd.local & ConfigMaps)
$argocdManifest = Join-Path $ProjectRoot "k8s\argocd.yaml"
if (Test-Path $argocdManifest) {
    Write-Log "Applying custom ArgoCD Ingress & ConfigMaps ($argocdManifest)..." -ForegroundColor Cyan
    kubectl apply -f $argocdManifest
    if ($LASTEXITCODE -ne 0) { Write-Log "❌ Failed to apply $argocdManifest" -ForegroundColor Red; exit 1 }
} else {
    Write-Log "❌ File $argocdManifest not found!" -ForegroundColor Red
    exit 1
}

kubectl rollout restart deploy/argocd-server -n argocd
kubectl rollout status deploy/argocd-server -n argocd --timeout=120s

# Apply k8s/application.yaml (dev, staging, prod)
$argocdAppsManifest = Join-Path $ProjectRoot "k8s\application.yaml"
if (Test-Path $argocdAppsManifest) {
    Write-Log "Applying ArgoCD Applications ($argocdAppsManifest)..." -ForegroundColor Cyan
    kubectl apply -f $argocdAppsManifest
}
Write-Log "✅ ArgoCD successfully configured and secured." -ForegroundColor Green


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
helm upgrade --install prometheus-stack prometheus-community/kube-prometheus-stack -n monitoring `
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

$artemisManifest = Join-Path $ProjectRoot "k8s\artemis.yaml"
Write-Log "Applying Artemis StatefulSet Manifest ($artemisManifest)..." -ForegroundColor Cyan
kubectl apply -f $artemisManifest
if ($LASTEXITCODE -ne 0) { Write-Log "❌ Failed to apply $artemisManifest" -ForegroundColor Red; exit 1 }

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
$keyFile = Join-Path $ProjectRoot "vault-keys.json"
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
$vaultStatusJson = kubectl exec -n vault vault-0 -- vault status -format=json 2>$null
$vaultStatus     = $vaultStatusJson | ConvertFrom-Json
if ($vaultStatus.sealed) {
    Write-Log "🔐 Unsealing Vault..." -ForegroundColor Cyan
    kubectl exec -n vault vault-0 -- vault operator unseal $unsealKey | Out-Null
    Write-Log "🔓 Vault unsealed successfully!" -ForegroundColor Green
}

Write-Log "Enabling KV v2 Secrets Engine at 'secret/' path..." -ForegroundColor Cyan
kubectl exec -n vault vault-0 -- vault login $vaultRootToken | Out-Null
$secretsListJson = kubectl exec -n vault vault-0 -- vault secrets list -format=json 2>$null
$secretsList     = $secretsListJson | ConvertFrom-Json
if (-not $secretsList.'secret/') {
    kubectl exec -n vault vault-0 -- vault secrets enable -path=secret -version=2 kv | Out-Null
    Write-Log "✅ KV v2 Secrets Engine enabled." -ForegroundColor Green
}

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


Write-Host "==========================================================" -ForegroundColor Cyan
Write-Host "PHASE 8: AUTOMATED SONARQUBE CONFIGURATION & TOKEN GENERATION" -ForegroundColor Yellow
Write-Host "==========================================================" -ForegroundColor Cyan

$sonarUrl = "http://localhost:9002"
$username = "admin"
$customPassword = "Kul!kS0narLocal"

Write-Log "Waiting for SonarQube to be ready..." -ForegroundColor Yellow
$maxRetries = 30
$retryCount = 0
$isUp = $false

while (-not $isUp -and $retryCount -lt $maxRetries) {
    try {
        $response = Invoke-RestMethod -Uri "$sonarUrl/api/system/status" -Method Get -TimeoutSec 5
        if ($response.status -eq "UP") {
            $isUp = $true
            Write-Log "[SUCCESS] SonarQube service is up and running!" -ForegroundColor Green
        }
    } catch {
        Start-Sleep -Seconds 5
        $retryCount++
        Write-Log "Attempting to connect to SonarQube ($retryCount/$maxRetries)..." -ForegroundColor DarkGray
    }
}

if (-not $isUp) {
    Write-Log "[ERROR] SonarQube failed to respond in time." -ForegroundColor Red
    exit 1
}

$authString = "{0}:{1}" -f $username, $customPassword
$base64AuthInfo = [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes($authString))
$headers = @{ Authorization = "Basic $base64AuthInfo" }

try {
    Invoke-RestMethod -Uri "$sonarUrl/api/authentication/validate" -Method Get -Headers $headers -ErrorAction Stop | Out-Null
    Write-Log "[SUCCESS] Authenticated successfully with custom password." -ForegroundColor Green
} catch {
    Write-Log "[INFO] Custom password not set yet. Trying default credentials (admin:admin)..." -ForegroundColor Yellow
    $defaultAuthString = "{0}:admin" -f $username
    $defaultBase64 = [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes($defaultAuthString))
    $defaultHeaders = @{ Authorization = "Basic $defaultBase64" }

    try {
        $body = @{
            login            = "admin"
            previousPassword = "admin"
            password         = $customPassword
        }
        Invoke-RestMethod -Uri "$sonarUrl/api/users/change_password" -Method Post -Headers $defaultHeaders -Body $body -ContentType "application/x-www-form-urlencoded" -ErrorAction Stop | Out-Null
        Write-Log "[SUCCESS] Admin password successfully updated to: $customPassword" -ForegroundColor Green
    } catch {
        Write-Log "[ERROR] Failed to update password: $_" -ForegroundColor Red
        exit 1
    }
}

$projectKey = "node-app-backend"
$projectName = "Node JS Backend App"
$encodedName = [uri]::EscapeDataString($projectName)

try {
    Write-Log "Creating SonarQube project: $projectKey..." -ForegroundColor Cyan
    Invoke-RestMethod -Uri "$sonarUrl/api/projects/create?project=$projectKey&name=$encodedName" -Method Post -Headers $headers -ContentType "application/x-www-form-urlencoded" -ErrorAction Stop | Out-Null
    Write-Log "[SUCCESS] SonarQube project successfully created!" -ForegroundColor Green
} catch {
    Write-Log "[INFO] The SonarQube project may already exist; continuing..." -ForegroundColor Yellow
}

$tokenName = "jenkins-token-fixed"
try {
    Write-Log "Revoking old tokens and generating a fresh static SonarQube token ($tokenName)..." -ForegroundColor Cyan
    try {
        Invoke-RestMethod -Uri "$sonarUrl/api/user_tokens/revoke?name=$tokenName" -Method Post -Headers $headers -ErrorAction SilentlyContinue | Out-Null
    } catch {}

    $tokenResponse = Invoke-RestMethod -Uri "$sonarUrl/api/user_tokens/generate?name=$tokenName" -Method Post -Headers $headers -ErrorAction Stop
    $sonarToken = $tokenResponse.token
    Write-Log "[SUCCESS] Static SonarQube token successfully generated!" -ForegroundColor Green

    $envContent = if (Test-Path $envFilePath) { Get-Content $envFilePath -Raw } else { "" }
    if ([string]::IsNullOrWhiteSpace($envContent)) {
        $envContent = "SONAR_TOKEN=$sonarToken`nSONAR_PASSWORD=$customPassword"
    } else {
        if ($envContent -match "SONAR_TOKEN=") {
            $envContent = $envContent -replace "SONAR_TOKEN=.*", "SONAR_TOKEN=$sonarToken"
        } else {
            $envContent = $envContent.TrimEnd() + "`nSONAR_TOKEN=$sonarToken"
        }

        if ($envContent -match "SONAR_PASSWORD=") {
            $envContent = $envContent -replace "SONAR_PASSWORD=.*", "SONAR_PASSWORD=$customPassword"
        } else {
            $envContent = $envContent.TrimEnd() + "`nSONAR_PASSWORD=$customPassword"
        }
    }

    Set-Content -Path $envFilePath -Value $envContent -Encoding utf8
    Write-Log "[SUCCESS] SONAR_TOKEN and SONAR_PASSWORD successfully saved to .env file!" -ForegroundColor Green
} catch {
    Write-Log "[ERROR] Failed to generate SonarQube token: $_" -ForegroundColor Red
}


Write-Host "`n==========================================================" -ForegroundColor Cyan
Write-Host "PHASE 9: NEXUS REPOSITORY & BINARY UPLOADS" -ForegroundColor Yellow
Write-Host "==========================================================" -ForegroundColor Cyan

$ProgressPreference = 'SilentlyContinue'
$nexusUrl  = "http://127.0.0.1:8082"
$repoName  = "raw-binaries"
$nexusPass = $env:NEXUS_PASSWORD

Write-Log "Waiting for Nexus 3 REST API to be ready..." -ForegroundColor Yellow
$nexusReady = $false
for ($i = 1; $i -le 30; $i++) {
    try {
        Invoke-RestMethod -Uri "$nexusUrl/service/rest/v1/status" -Method Get -TimeoutSec 5 -ErrorAction Stop | Out-Null
        $nexusReady = $true
        Write-Log "✅ Nexus 3 is up and ready!" -ForegroundColor Green
        break
    } catch {
        Start-Sleep -Seconds 5
        Write-Log "Attempting to connect to Nexus ($i/30)..." -ForegroundColor DarkGray
    }
}

if (-not $nexusReady) {
    Write-Log "❌ Nexus failed to respond in time." -ForegroundColor Red
    exit 1
}

if ([string]::IsNullOrWhiteSpace($nexusPass)) {
    Write-Log "⚠️ NEXUS_PASSWORD not found in .env! Skipping Nexus uploads." -ForegroundColor Red
} else {
    $base64AuthInfo = [Convert]::ToBase64String([System.Text.Encoding]::ASCII.GetBytes(("admin:{0}" -f $nexusPass)))
    $headers = @{
        Authorization  = ("Basic {0}" -f $base64AuthInfo)
        "Content-Type" = "application/json"
    }

    # Auto-configure initial password jika ini fresh install Nexus
    try {
        Invoke-RestMethod -Uri "$nexusUrl/service/rest/v1/repositories" -Method Get -Headers $headers -ErrorAction Stop | Out-Null
    } catch {
        $nexusContainerId = docker ps -q --filter "name=nexus"
        if ($nexusContainerId) {
            $initNexusPass = (docker exec $nexusContainerId cat /nexus-data/admin.password 2>$null)
            if ($initNexusPass) {
                $initNexusPass = $initNexusPass.Trim()
                Write-Log "🔄 First-time Nexus setup detected. Updating admin password..." -ForegroundColor Cyan
                $initBase64 = [Convert]::ToBase64String([System.Text.Encoding]::ASCII.GetBytes(("admin:{0}" -f $initNexusPass)))
                $initHeaders = @{ Authorization = ("Basic {0}" -f $initBase64); "Content-Type" = "text/plain" }
                Invoke-RestMethod -Uri "$nexusUrl/service/rest/v1/security/users/admin/change-password" -Method Put -Headers $initHeaders -Body $nexusPass -ErrorAction Stop | Out-Null
                $eulaBody = @{ accepted = $true } | ConvertTo-Json
                Invoke-RestMethod -Uri "$nexusUrl/service/rest/v1/system/eula" -Method Post -Headers $headers -Body $eulaBody -ErrorAction SilentlyContinue | Out-Null
                Write-Log "✅ Nexus admin password updated to .env value." -ForegroundColor Green
            }
        }
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

    if (-not $authFailed -and (Test-Path $binFolderPath)) {
        $files = Get-ChildItem -Path $binFolderPath -File
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
            Write-Log "⚠️ Folder $binFolderPath is empty." -ForegroundColor Yellow
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
Write-Log " - SonarQube  : http://localhost:9002 (User: admin, Pass: $customPassword)" -ForegroundColor Green
Write-Log " - PostgreSQL : localhost:5432 (User: postgres, Pass: $($env:POSTGRES_PASSWORD))"
Write-Log " - PGAdmin    : http://localhost:8081 (User: $($env:PGADMIN_EMAIL), Pass: $($env:PGADMIN_PASSWORD))"
Write-Log " - Vault      : http://localhost:8200 (Token: $vaultRootToken)" -ForegroundColor Green
Write-Log " - Grafana    : http://grafana.local (User: admin, Pass: $grafanaPass)" -ForegroundColor Green
Write-Log " - Artemis    : http://localhost:8161 (User: $($env:ARTEMIS_USER), Pass: $($env:ARTEMIS_PASSWORD))" -ForegroundColor Green
Write-Log " - Prometheus : http://localhost:9090" -ForegroundColor Green
Write-Log " - MinIO      : http://localhost:9001 (User: $($env:MINIO_ROOT_USER), Pass: $($env:MINIO_ROOT_PASSWORD))" -ForegroundColor Green
Write-Host "==========================================================" -ForegroundColor Green
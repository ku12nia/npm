# ==============================================================================
# DEVOPS LAB AUTOMATION - UNIFIED MASTER DEPLOYMENT SCRIPT
# Usage:
#   .\scripts\powershell\install.ps1              -> Normal / Idempotent run
#   .\scripts\powershell\install.ps1 -CleanVault  -> Force reset & re-init Vault
# ==============================================================================
param (
    [switch]$CleanVault
)

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

# Resolve Project Root dynamically so paths work regardless of where script is invoked
$ProjectRoot = (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path
Set-Location $ProjectRoot

# ==============================================================================
Write-Host "`n==========================================================" -ForegroundColor Cyan
Write-Host "PHASE 0: PREREQUISITES, 3-TIER BINARY CACHE & ENVIRONMENT SETUP" -ForegroundColor Yellow
Write-Host "==========================================================" -ForegroundColor Cyan
$envFilePath = Join-Path $ProjectRoot ".env"
if (Test-Path $envFilePath) {
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
$WorkspaceDir  = "/var/jenkins_home/workspace/$WorkspaceName"

# --- AUTOMATED BINARY DIRECTORY CHECK & 3-TIER RESOLUTION ---
$parentBinPath  = Join-Path $ProjectRoot "bin"
$siblingBinPath = "C:\Users\evoel\Downloads\labs_dedi\bin"

if (Test-Path $parentBinPath) {
    $binFolderPath = $parentBinPath
    Write-Log "📁 Using local project bin folder at: $binFolderPath" -ForegroundColor Cyan
} elseif (Test-Path $siblingBinPath) {
    $binFolderPath = $siblingBinPath
    Write-Log "📁 Using shared lab bin folder at: $binFolderPath" -ForegroundColor Cyan
} else {
    Write-Log "📁 Folder 'bin/' not found. Creating directory automatically..." -ForegroundColor Yellow
    $binFolderPath = $parentBinPath
    New-Item -ItemType Directory -Force -Path $binFolderPath | Out-Null
}

$requiredBinaries = @(
    "docker-24.0.9.tgz",
    "buildx-v0.14.0.linux-amd64",
    "kubectl",
    "argocd-linux-amd64",
    "sonar-scanner-cli-5.0.1.3006-linux.zip",
    "terraform_1.9.0_linux_amd64.zip"
)

$binaryUrls = @{
    "docker-24.0.9.tgz"                        = "https://download.docker.com/linux/static/stable/x86_64/docker-24.0.9.tgz"
    "buildx-v0.14.0.linux-amd64"               = "https://github.com/docker/buildx/releases/download/v0.14.0/buildx-v0.14.0.linux-amd64"
    "kubectl"                                  = "https://dl.k8s.io/release/v1.30.0/bin/linux/amd64/kubectl"
    "argocd-linux-amd64"                       = "https://github.com/argoproj/argo-cd/releases/download/v3.6.1/argocd-linux-amd64"
    "sonar-scanner-cli-5.0.1.3006-linux.zip"   = "https://binaries.sonarsource.com/Distribution/sonar-scanner-cli/sonar-scanner-cli-5.0.1.3006-linux.zip"
    "terraform_1.9.0_linux_amd64.zip"          = "https://releases.hashicorp.com/terraform/1.9.0/terraform_1.9.0_linux_amd64.zip"
}

$missingFiles = $requiredBinaries | Where-Object { -not (Test-Path (Join-Path $binFolderPath $_)) }
if ($missingFiles.Count -gt 0) {
    Write-Log "⚠️ Missing binaries in $binFolderPath. Checking Nexus -> Downloads -> Internet..." -ForegroundColor Yellow
    $nexusRawBase   = "http://127.0.0.1:8082/repository/raw-binaries"
    $fallbackSource = "C:\Users\evoel\Downloads"

    foreach ($miss in $missingFiles) {
        $destPath = Join-Path $binFolderPath $miss

        # Tier 2: Local Nexus Cache
        $nexusCode = cmd /c "curl.exe -s -o nul -w %{http_code} ""$nexusRawBase/$miss"" 2>nul"
        if ($nexusCode -and $nexusCode.Trim() -eq "200") {
            Write-Log "⚡ Pulling $miss from local Nexus cache..." -ForegroundColor Cyan
            curl.exe -fsSL "$nexusRawBase/$miss" -o "$destPath"
            continue
        }

        # Tier 3a: Downloads Folder
        $possibleSource = Join-Path $fallbackSource $miss
        if (Test-Path $possibleSource) {
            Write-Log "🔄 Auto-copying $miss from $possibleSource..." -ForegroundColor Cyan
            Copy-Item -Path $possibleSource -Destination $destPath -Force
            continue
        }

        # Tier 3b: Official Release Mirror
        if ($binaryUrls.ContainsKey($miss)) {
            Write-Log "⬇️ Downloading $miss from official release..." -ForegroundColor Cyan
            curl.exe -fsSL "$($binaryUrls[$miss])" -o "$destPath"
        }
    }

    $stillMissing = $requiredBinaries | Where-Object { -not (Test-Path (Join-Path $binFolderPath $_)) }
    if ($stillMissing.Count -gt 0) {
        Write-Log "❌ Error: Required binaries still missing in '$binFolderPath': $($stillMissing -join ', ')" -ForegroundColor Red
        exit 1
    }
}
Write-Log "✅ All required binaries are complete and verified." -ForegroundColor Green


# ==============================================================================
Write-Host "`n==========================================================" -ForegroundColor Cyan
Write-Host "PHASE 1: DOCKER COMPOSE SERVICES (Jenkins, PostgreSQL, MinIO, Nexus, SonarQube)" -ForegroundColor Yellow
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
$null = cmd /c "docker run --rm -v npm_jenkins_home:/var/jenkins_home alpine chown -R 1000:1000 /var/jenkins_home 2>nul"
$null = cmd /c "docker run --rm -v nexus_data:/nexus-data alpine chown -R 200:200 /nexus-data 2>nul"

$composeImageName = "npm-jenkins"
Write-Log "🔍 Checking custom Docker image ($composeImageName)..." -ForegroundColor Yellow
$imageExists = cmd /c "docker images -q $composeImageName 2>nul"
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

$jenkinsId   = docker ps -q --filter "name=jenkins"
$jenkinsPass = ""
if ($jenkinsId) {
    $rawPass = cmd /c "docker exec $jenkinsId sh -c ""if [ -f /var/jenkins_home/secrets/initialAdminPassword ]; then cat /var/jenkins_home/secrets/initialAdminPassword; fi"" 2>nul"
    if ($rawPass) { $jenkinsPass = ($rawPass | Out-String).Trim() }
}
if ([string]::IsNullOrWhiteSpace($jenkinsPass)) {
    $jenkinsPass = "Already initialized (or configured via JCasC); use existing registered credentials."
}


# ==============================================================================
Write-Host "`n==========================================================" -ForegroundColor Cyan
Write-Host "PHASE 2: NEXUS REPOSITORY & BINARY UPLOADS" -ForegroundColor Yellow
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

    try {
        Invoke-RestMethod -Uri "$nexusUrl/service/rest/v1/repositories" -Method Get -Headers $headers -ErrorAction Stop | Out-Null
    } catch {
        $nexusContainerId = docker ps -q --filter "name=nexus"
        if ($nexusContainerId) {
            $initNexusPass = cmd /c "docker exec $nexusContainerId cat /nexus-data/admin.password 2>nul"
            if ($initNexusPass) {
                $initNexusPass = ($initNexusPass | Out-String).Trim()
                Write-Log "🔄 First-time Nexus setup detected. Updating admin password..." -ForegroundColor Cyan
                $initBase64  = [Convert]::ToBase64String([System.Text.Encoding]::ASCII.GetBytes(("admin:{0}" -f $initNexusPass)))
                $initHeaders = @{ Authorization = ("Basic {0}" -f $initBase64); "Content-Type" = "text/plain" }
                Invoke-RestMethod -Uri "$nexusUrl/service/rest/v1/security/users/admin/change-password" -Method Put -Headers $initHeaders -Body $nexusPass -ErrorAction Stop | Out-Null
                $eulaBody = @{ accepted = $true } | ConvertTo-Json
                Invoke-RestMethod -Uri "$nexusUrl/service/rest/v1/system/eula" -Method Post -Headers $headers -Body $eulaBody -ErrorAction SilentlyContinue | Out-Null
                Start-Sleep -Seconds 2
                Write-Log "✅ Nexus admin password updated to .env value." -ForegroundColor Green
            }
        }
    }

    $repoPayload = @{
        name    = $repoName
        online  = $true
        storage = @{
            blobStoreName               = "default"
            strictContentTypeValidation = $false
            writePolicy                 = "ALLOW"
        }
        raw = @{ contentDisposition = "ATTACHMENT" }
    } | ConvertTo-Json -Depth 10

    try {
        Invoke-RestMethod -Uri "$nexusUrl/service/rest/v1/repositories/raw/hosted" -Method Post -Headers $headers -Body $repoPayload -ErrorAction Stop | Out-Null
        Write-Log "✅ Repository '$repoName' created via API." -ForegroundColor Green
    } catch {
        $statusCode = $_.Exception.Response.StatusCode.Value__
        if ($statusCode -eq 401) {
            Write-Log "❌ Authentication Failed! Invalid Nexus password." -ForegroundColor Red
            exit 1
        } else {
            Write-Log "✅ Repository '$repoName' already exists. Checking artifacts..." -ForegroundColor Green
        }
    }

    if (Test-Path $binFolderPath) {
        $files = Get-ChildItem -Path $binFolderPath -File
        foreach ($file in $files) {
            $uploadUrl  = "$nexusUrl/repository/$repoName/$($file.Name)"
            $existsCode = cmd /c "curl.exe -s -o nul -w %{http_code} -u ""admin:$nexusPass"" ""$uploadUrl"" 2>nul"
            if ($existsCode -and $existsCode.Trim() -eq "200") {
                Write-Log "✅ $($file.Name) already exists in Nexus (skipped)." -ForegroundColor DarkGray
                continue
            }

            Write-Log "⬆️ Uploading $($file.Name) to Nexus..." -ForegroundColor Yellow
            $curlOutput = curl.exe --silent --show-error --fail -u "admin:$nexusPass" -T "$($file.FullName)" "$uploadUrl" 2>&1
            if ($LASTEXITCODE -eq 0) {
                Write-Log "✅ Uploaded $($file.Name)." -ForegroundColor Green
            } else {
                Write-Log "⚠️ Failed to upload $($file.Name): $curlOutput" -ForegroundColor Red
            }
        }
    }
}
$ProgressPreference = 'Continue'


# ==============================================================================
Write-Host "`n==========================================================" -ForegroundColor Cyan
Write-Host "PHASE 3: KUBERNETES CORE NETWORKING (Ingress-Nginx)" -ForegroundColor Yellow
Write-Host "==========================================================" -ForegroundColor Cyan
helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx 2>$null | Out-Null
helm repo update | Out-Null
helm upgrade --install ingress-nginx ingress-nginx/ingress-nginx `
    --namespace ingress-nginx `
    --create-namespace `
    --set controller.service.type=LoadBalancer `
    --wait --timeout 180s
if ($LASTEXITCODE -ne 0) { Write-Log "❌ Ingress-Nginx deployment failed." -ForegroundColor Red; exit 1 }
Write-Log "✅ Ingress Nginx ready." -ForegroundColor Green


# ==============================================================================
Write-Host "`n==========================================================" -ForegroundColor Cyan
Write-Host "PHASE 4: ARGO CD SETUP, CRD FIX & INGRESS" -ForegroundColor Yellow
Write-Host "==========================================================" -ForegroundColor Cyan
kubectl create namespace argocd --dry-run=client -o yaml | kubectl apply -f - | Out-Null

Write-Log "Applying ArgoCD manifests (with Server-Side Apply for CRDs)..." -ForegroundColor Cyan
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
kubectl patch secret argocd-secret -n argocd --type='merge' --patch-file $patchFile | Out-Null
Remove-Item $patchFile -ErrorAction SilentlyContinue
kubectl delete secret argocd-initial-admin-secret -n argocd --ignore-not-found=true 2>$null | Out-Null

$argocdCustomManifest = if (Test-Path (Join-Path $ProjectRoot "k8s\argocd\argocd.yaml")) {
    Join-Path $ProjectRoot "k8s\argocd\argocd.yaml"
} else {
    Join-Path $ProjectRoot "k8s\argocd.yaml"
}

if (Test-Path $argocdCustomManifest) {
    Write-Log "Applying custom ArgoCD ConfigMaps & Ingress ($argocdCustomManifest)..." -ForegroundColor Cyan
    kubectl apply -f $argocdCustomManifest
    if ($LASTEXITCODE -ne 0) { Write-Log "❌ Failed to apply $argocdCustomManifest" -ForegroundColor Red; exit 1 }
} else {
    Write-Log "❌ ArgoCD Ingress/ConfigMap manifest not found!" -ForegroundColor Red
    exit 1
}

kubectl rollout restart deploy/argocd-server -n argocd | Out-Null
kubectl rollout status deploy/argocd-server -n argocd --timeout=120s

$argocdAppsManifest = Join-Path $ProjectRoot "k8s\argocd\application.yaml"
if (Test-Path $argocdAppsManifest) {
    Write-Log "Applying ArgoCD Applications ($argocdAppsManifest)..." -ForegroundColor Cyan
    kubectl apply -f $argocdAppsManifest
}
Write-Log "✅ ArgoCD successfully configured and exposed at http://argocd.local." -ForegroundColor Green


# ==============================================================================
Write-Host "`n==========================================================" -ForegroundColor Cyan
Write-Host "PHASE 5: PGADMIN SETUP ON KUBERNETES" -ForegroundColor Yellow
Write-Host "==========================================================" -ForegroundColor Cyan
helm repo add runix https://helm.runix.net 2>$null | Out-Null
helm repo update | Out-Null
helm upgrade --install pgadmin runix/pgadmin4 -n default `
    --set env.email="$env:PGADMIN_EMAIL" `
    --set env.password="$env:PGADMIN_PASSWORD" `
    --set service.type=LoadBalancer `
    --set service.port=8081 | Out-Null
Write-Log "✅ PGAdmin deployed." -ForegroundColor Green


# ==============================================================================
Write-Host "`n==========================================================" -ForegroundColor Cyan
Write-Host "PHASE 6: PROMETHEUS & GRAFANA ON KUBERNETES" -ForegroundColor Yellow
Write-Host "==========================================================" -ForegroundColor Cyan
kubectl create namespace monitoring --dry-run=client -o yaml | kubectl apply -f - | Out-Null
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts 2>$null | Out-Null
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
$grafanaPass    = "prom-operator"
$encodedGrafana = cmd /c "kubectl get secret prometheus-stack-grafana -n monitoring -o jsonpath={.data.admin-password} 2>nul"
if ($encodedGrafana -and $encodedGrafana.Trim()) {
    $grafanaPass = [System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($encodedGrafana.Trim()))
}
Write-Log "✅ Prometheus & Grafana ready." -ForegroundColor Green


# ==============================================================================
Write-Host "`n==========================================================" -ForegroundColor Cyan
Write-Host "PHASE 7: ACTIVEMQ ARTEMIS ON KUBERNETES" -ForegroundColor Yellow
Write-Host "==========================================================" -ForegroundColor Cyan
kubectl create namespace artemis --dry-run=client -o yaml | kubectl apply -f - | Out-Null
Write-Log "Injecting Artemis Credentials into Kubernetes Secret..." -ForegroundColor Cyan
kubectl create secret generic artemis-credentials -n artemis `
    --from-literal=ARTEMIS_USER="$env:ARTEMIS_USER" `
    --from-literal=ARTEMIS_PASSWORD="$env:ARTEMIS_PASSWORD" `
    --dry-run=client -o yaml | kubectl apply -f - | Out-Null
Write-Log "Applying Artemis StatefulSet Manifest..." -ForegroundColor Cyan
kubectl apply -f (Join-Path $ProjectRoot "k8s\artemis.yaml") | Out-Null
Write-Log "Waiting for Artemis Pod to reach ready status..." -ForegroundColor Magenta
Start-Sleep -Seconds 10
kubectl wait --for=condition=ready pod -l app=artemis -n artemis --timeout=300s | Out-Null
Write-Log "✅ ActiveMQ Artemis ready." -ForegroundColor Green


# ==============================================================================
Write-Host "`n==========================================================" -ForegroundColor Cyan
Write-Host "PHASE 8: HASHICORP VAULT (Idempotent Deploy, Auto-Unseal & Secret Sync)" -ForegroundColor Yellow
Write-Host "==========================================================" -ForegroundColor Cyan
$keyFile = Join-Path $ProjectRoot "vault-keys.json"

if ($CleanVault) {
    Write-Log "🧹 -CleanVault flag active. Removing previous Vault installations..." -ForegroundColor Yellow
    $prevPref = $ErrorActionPreference
    $ErrorActionPreference = "Continue"
    $null = cmd /c "helm uninstall vault -n vault --no-hooks 2>nul"
    $null = cmd /c "kubectl delete namespace vault --ignore-not-found=true --wait=true --timeout=120s 2>nul"
    $null = cmd /c "kubectl delete mutatingwebhookconfiguration,validatingwebhookconfiguration -l app.kubernetes.io/name=vault --ignore-not-found=true 2>nul"
    $null = cmd /c "kubectl delete clusterrole,clusterrolebinding -l app.kubernetes.io/name=vault --ignore-not-found=true 2>nul"
    $ErrorActionPreference = $prevPref
    if (Test-Path $keyFile) { Remove-Item $keyFile -Force -ErrorAction SilentlyContinue }
}

kubectl create namespace vault --dry-run=client -o yaml | kubectl apply -f - | Out-Null
helm repo add hashicorp https://helm.releases.hashicorp.com 2>$null | Out-Null
helm repo update | Out-Null

Write-Log "Ensuring Vault Helm release is deployed (Production Mode with PVC)..." -ForegroundColor Cyan
helm upgrade --install vault hashicorp/vault -n vault `
    --set "server.dev.enabled=false" `
    --set "server.dataStorage.enabled=true" `
    --set "server.dataStorage.size=1Gi" `
    --set "injector.enabled=true" `
    --set "ui.enabled=true" `
    --set "ui.serviceType=LoadBalancer" `
    --set "ui.externalPort=8200" | Out-Null

Write-Log "Waiting for Vault pod to be running..." -ForegroundColor Magenta
$vaultPodReady = $false
for ($i = 1; $i -le 60; $i++) {
    $podPhase = cmd /c "kubectl get pod vault-0 -n vault -o jsonpath={.status.phase} 2>nul"
    if ($podPhase -and $podPhase.Trim() -eq "Running") {
        Write-Log "✅ Vault pod is running." -ForegroundColor Green
        $vaultPodReady = $true
        break
    }
    Start-Sleep -Seconds 3
}
if (-not $vaultPodReady) {
    Write-Log "❌ Vault pod 'vault-0' did not reach Running state within 180s." -ForegroundColor Red
    exit 1
}

Start-Sleep -Seconds 5
Write-Log "Checking Vault status..." -ForegroundColor Cyan
$vaultStatusJson = cmd /c "kubectl exec -n vault vault-0 -- vault status -format=json 2>nul"
if (-not $vaultStatusJson) {
    Write-Log "❌ Failed to connect to Vault container." -ForegroundColor Red
    exit 1
}
$vaultStatus = ($vaultStatusJson -join "`n") | ConvertFrom-Json

if (-not $vaultStatus.initialized) {
    Write-Log "⚙️ Initializing Vault (1 Key Share)..." -ForegroundColor Cyan
    kubectl exec -n vault vault-0 -- vault operator init -key-shares=1 -key-threshold=1 -format=json | Out-File -FilePath $keyFile -Encoding utf8
    Write-Log "✅ Vault initialized & keys saved." -ForegroundColor Green
} elseif (-not (Test-Path $keyFile)) {
    Write-Log "❌ Vault is already initialized, but $keyFile is missing! Run with -CleanVault to reset." -ForegroundColor Red
    exit 1
}

$vaultKeys      = Get-Content $keyFile | ConvertFrom-Json
$unsealKey      = $vaultKeys.unseal_keys_b64[0]
$vaultRootToken = $vaultKeys.root_token

$vaultStatusJson = cmd /c "kubectl exec -n vault vault-0 -- vault status -format=json 2>nul"
$vaultStatus     = ($vaultStatusJson -join "`n") | ConvertFrom-Json
if ($vaultStatus.sealed) {
    Write-Log "🔐 Unsealing Vault..." -ForegroundColor Cyan
    kubectl exec -n vault vault-0 -- vault operator unseal $unsealKey | Out-Null
    Write-Log "🔓 Vault unsealed successfully!" -ForegroundColor Green
} else {
    Write-Log "🔓 Vault is already unsealed." -ForegroundColor Green
}

Write-Log "Enabling KV v2 Secrets Engine at 'secret/' path..." -ForegroundColor Cyan
kubectl exec -n vault vault-0 -- vault login $vaultRootToken | Out-Null
$secretsListJson = cmd /c "kubectl exec -n vault vault-0 -- vault secrets list -format=json 2>nul"
$secretsList     = ($secretsListJson -join "`n") | ConvertFrom-Json
if (-not $secretsList.'secret/') {
    kubectl exec -n vault vault-0 -- vault secrets enable -path=secret -version=2 kv | Out-Null
    Write-Log "✅ KV v2 Secrets Engine enabled." -ForegroundColor Green
}

Write-Log "Exporting/syncing all credentials to Vault KV..." -ForegroundColor Yellow
$secretsMap = @{
    "secret/database/postgres"  = @{ username = "postgres"; password = "$env:POSTGRES_PASSWORD" }
    "secret/pgadmin"            = @{ admin_email = "$env:PGADMIN_EMAIL"; admin_password = "$env:PGADMIN_PASSWORD" }
    "secret/minio"              = @{ root_user = "$env:MINIO_ROOT_USER"; root_password = "$env:MINIO_ROOT_PASSWORD" }
    "secret/artemis"            = @{ admin_user = "$env:ARTEMIS_USER"; admin_password = "$env:ARTEMIS_PASSWORD" }
    "secret/nexus"              = @{ admin_user = "admin"; admin_password = "$env:NEXUS_PASSWORD" }
    "secret/argocd"             = @{ admin_user = "admin"; admin_password = "$argocdPass" }
    "secret/grafana"            = @{ admin_user = "admin"; admin_password = "$grafanaPass" }
    "secret/jenkins/admin"      = @{ admin_user = "jenkins"; admin_password = "$env:JENKINS_PASSWORD" }
    "secret/jenkins/github"     = @{ username = "$env:GITHUB_USER"; token = "$env:GITHUB_TOKEN" }
    "secret/jenkins/dockerhub"  = @{ username = "$env:DOCKER_USER"; password = "$env:DOCKER_PASS" }
}
foreach ($path in $secretsMap.Keys) {
    $pairs = $secretsMap[$path]
    $kvArgs = @("kv", "put", $path)
    $hasValues = $false
    foreach ($k in $pairs.Keys) {
        $val = $pairs[$k]
        if (-not [string]::IsNullOrEmpty($val)) {
            $kvArgs += "$k=$val"
            $hasValues = $true
        }
    }
    if ($hasValues) {
        kubectl exec -n vault vault-0 -- vault @kvArgs | Out-Null
    }
}
Write-Log "✅ All credentials successfully stored in Vault." -ForegroundColor Green


# ==============================================================================
Write-Host "`n==========================================================" -ForegroundColor Cyan
Write-Host "PHASE 9: AUTOMATED SONARQUBE CONFIGURATION & TOKEN GENERATION" -ForegroundColor Yellow
Write-Host "==========================================================" -ForegroundColor Cyan
$sonarUrl       = "http://localhost:9002"
$username       = "admin"
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

$authString     = "{0}:{1}" -f $username, $customPassword
$base64AuthInfo = [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes($authString))
$headers        = @{ Authorization = "Basic $base64AuthInfo" }

try {
    Invoke-RestMethod -Uri "$sonarUrl/api/authentication/validate" -Method Get -Headers $headers -ErrorAction Stop | Out-Null
    Write-Log "[SUCCESS] Authenticated successfully with custom password." -ForegroundColor Green
} catch {
    Write-Log "[INFO] Custom password not set yet. Trying default credentials (admin:admin)..." -ForegroundColor Yellow
    $defaultAuthString = "{0}:admin" -f $username
    $defaultBase64     = [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes($defaultAuthString))
    $defaultHeaders    = @{ Authorization = "Basic $defaultBase64" }

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

$projectKey  = "node-app-backend"
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
    $sonarToken    = $tokenResponse.token
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

    kubectl exec -n vault vault-0 -- vault kv put secret/sonarqube url="http://sonarqube:9000" password="$customPassword" token="$sonarToken" | Out-Null
    Write-Log "[SUCCESS] SONAR_TOKEN synced to Vault (secret/sonarqube)!" -ForegroundColor Green
} catch {
    Write-Log "[ERROR] Failed to generate SonarQube token: $_" -ForegroundColor Red
}


# ==============================================================================
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
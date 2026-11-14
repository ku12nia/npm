# ==============================================================================
# DEVOPS LAB CLEANUP & UNINSTALLATION SCRIPT
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
Write-Host "DEVOPS LAB CLEANUP & UNINSTALLATION SCRIPT" -ForegroundColor Yellow
Write-Host "==========================================================" -ForegroundColor Cyan

# 1. REMOVING ARGO CD
Write-Host "`n==========================================================" -ForegroundColor Cyan
Write-Host "1. Removing Argo CD from Kubernetes" -ForegroundColor Yellow
Write-Host "==========================================================" -ForegroundColor Cyan
if (Get-Command kubectl -ErrorAction SilentlyContinue) {
    kubectl patch application --all -n argocd -p '{"metadata":{"finalizers":[]}}' --type=merge 2>$null
    kubectl patch appproject --all -n argocd -p '{"metadata":{"finalizers":[]}}' --type=merge 2>$null
    kubectl delete applications --all -n argocd --ignore-not-found=true --force --grace-period=0 2>$null
    kubectl delete appprojects --all -n argocd --ignore-not-found=true --force --grace-period=0 2>$null
    kubectl delete crd applications.argoproj.io applicationsets.argoproj.io appprojects.argoproj.io applicationsyncwindows.argoproj.io --ignore-not-found=true 2>$null
    kubectl patch namespace argocd --type=json -p='[{"op": "remove", "path": "/metadata/finalizers"}]' 2>$null
    kubectl delete namespace argocd --ignore-not-found=true --force --grace-period=0 2>$null
    Write-Log "✅ Argo CD removed." -ForegroundColor Green
}

# 2. REMOVING APPLICATION NAMESPACES
Write-Host "`n==========================================================" -ForegroundColor Cyan
Write-Host "2. Removing Application Namespaces (dev/staging/prod)" -ForegroundColor Yellow
Write-Host "==========================================================" -ForegroundColor Cyan
if (Get-Command kubectl -ErrorAction SilentlyContinue) {
    foreach ($ns in @("dev-apps", "staging-apps", "prod-apps")) {
        kubectl delete namespace $ns --force --grace-period=0 --ignore-not-found=true 2>$null
    }
    Write-Log "✅ App namespaces removed." -ForegroundColor Green
}

# 3. REMOVING NGINX INGRESS
Write-Host "`n==========================================================" -ForegroundColor Cyan
Write-Host "3. Removing Nginx Ingress Controller" -ForegroundColor Yellow
Write-Host "==========================================================" -ForegroundColor Cyan
if (Get-Command helm -ErrorAction SilentlyContinue) {
    helm uninstall ingress-nginx -n ingress-nginx --ignore-not-found=true 2>$null
    kubectl delete namespace ingress-nginx --ignore-not-found=true --force --grace-period=0 2>$null
    Write-Log "✅ Nginx Ingress removed." -ForegroundColor Green
}

# 4. REMOVING VAULT
Write-Host "`n==========================================================" -ForegroundColor Cyan
Write-Host "4. Removing HashiCorp Vault" -ForegroundColor Yellow
Write-Host "==========================================================" -ForegroundColor Cyan
if (Get-Command helm -ErrorAction SilentlyContinue) {
    helm uninstall vault -n vault --ignore-not-found=true 2>$null
    kubectl delete namespace vault --force --grace-period=0 --ignore-not-found=true 2>$null
    kubectl delete mutatingwebhookconfiguration,validatingwebhookconfiguration -l app.kubernetes.io/name=vault --ignore-not-found=true 2>$null
    kubectl delete clusterrole,clusterrolebinding -l app.kubernetes.io/name=vault --ignore-not-found=true 2>$null
    Write-Log "✅ Vault removed." -ForegroundColor Green
}

# 5. REMOVING MONITORING (Prometheus/Grafana)
Write-Host "`n==========================================================" -ForegroundColor Cyan
Write-Host "5. Removing Prometheus & Grafana" -ForegroundColor Yellow
Write-Host "==========================================================" -ForegroundColor Cyan
if (Get-Command helm -ErrorAction SilentlyContinue) {
    helm uninstall prometheus-stack -n monitoring --ignore-not-found=true 2>$null
    kubectl delete namespace monitoring --ignore-not-found=true --force --grace-period=0 2>$null
    Write-Log "✅ Monitoring stack removed." -ForegroundColor Green
}

# 6. REMOVING PGADMIN
Write-Host "`n==========================================================" -ForegroundColor Cyan
Write-Host "6. Removing PGAdmin" -ForegroundColor Yellow
Write-Host "==========================================================" -ForegroundColor Cyan
if (Get-Command helm -ErrorAction SilentlyContinue) {
    helm uninstall pgadmin -n default --ignore-not-found=true 2>$null
    Write-Log "✅ PGAdmin removed." -ForegroundColor Green
}

# 7. REMOVING ARTEMIS
Write-Host "`n==========================================================" -ForegroundColor Cyan
Write-Host "7. Removing ActiveMQ Artemis" -ForegroundColor Yellow
Write-Host "==========================================================" -ForegroundColor Cyan
if (Get-Command helm -ErrorAction SilentlyContinue) {
    helm uninstall artemis -n artemis --ignore-not-found=true --no-hooks 2>$null
    kubectl delete namespace artemis --ignore-not-found=true --force --grace-period=0 2>$null
    Write-Log "✅ Artemis removed." -ForegroundColor Green
}

# 8. CLEANING TEMP FILES
Write-Host "`n==========================================================" -ForegroundColor Cyan
Write-Host "8. Cleaning up Local Temporary Files" -ForegroundColor Yellow
Write-Host "==========================================================" -ForegroundColor Cyan
foreach ($file in @("vault-keys.json", "argo-patch.json")) {
    if (Test-Path $file) {
        Remove-Item $file -Force -ErrorAction SilentlyContinue
        Write-Log "🗑️ Removed: $file" -ForegroundColor Yellow
    }
}

# ==============================================================================
# 9. STOPPING DOCKER COMPOSE (Preserving Volumes)
# ==============================================================================
Write-Host "`n==========================================================" -ForegroundColor Cyan
Write-Host "9. Stopping Core Docker Compose Services" -ForegroundColor Yellow
Write-Host "==========================================================" -ForegroundColor Cyan

if (Get-Command docker -ErrorAction SilentlyContinue) {
    $composeFile = Join-Path $PSScriptRoot "..\..\config\docker-compose.yml"
    $projectDir  = Join-Path $PSScriptRoot "..\..\config"
    $projectName = "npm-cicd" 
    if (Test-Path $composeFile) {
        Write-Log "Stopping Docker Compose containers for project '$projectName'..." -ForegroundColor Cyan
        docker compose -f $composeFile --project-directory $projectDir -p $projectName down --remove-orphans
        docker compose -f $composeFile --project-directory $projectDir -p config down --remove-orphans 2>$null
        Write-Log "✅ Docker Compose stack stopped and removed (volumes preserved)." -ForegroundColor Green
    } else {
        Write-Log "⚠️ docker-compose.yml not found, skipping container shutdown." -ForegroundColor Yellow
    }
    docker logout 2>$null
}

# NOTE: Terraform CLI is PRESERVED and will NOT be uninstalled.
Write-Host "`n==========================================================" -ForegroundColor Green
Write-Host "✅ Done! Cleanup successful. Terraform CLI is preserved." -ForegroundColor Green
Write-Host "==========================================================" -ForegroundColor Green
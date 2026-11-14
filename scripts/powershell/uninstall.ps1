# ==============================================================================
# DEVOPS LAB CLEANUP & UNINSTALLATION SCRIPT (Final)
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

# ==============================================================================
# 1. REMOVING ARGO CD FROM KUBERNETES
# ==============================================================================
Write-Host "`n==========================================================" -ForegroundColor Cyan
Write-Host "1. Removing Argo CD from Kubernetes" -ForegroundColor Yellow
Write-Host "==========================================================" -ForegroundColor Cyan

if (Get-Command kubectl -ErrorAction SilentlyContinue) {
    Write-Log "Removing finalizers natively via kubectl patch to prevent deadlocks..."
    kubectl patch application --all -n argocd -p '{"metadata":{"finalizers":[]}}' --type=merge 2>$null
    kubectl patch appproject --all -n argocd -p '{"metadata":{"finalizers":[]}}' --type=merge 2>$null

    Write-Log "Cleaning up Applications and Projects..."
    kubectl delete applications --all -n argocd --ignore-not-found=true --force --grace-period=0 2>$null
    kubectl delete appprojects --all -n argocd --ignore-not-found=true --force --grace-period=0 2>$null

    Write-Log "Deleting Argo CD Custom Resource Definitions (CRDs)..."
    kubectl delete crd applications.argoproj.io applicationsets.argoproj.io appprojects.argoproj.io applicationsyncwindows.argoproj.io --ignore-not-found=true 2>$null

    Write-Log "Patching and deleting namespace argocd..."
    kubectl patch namespace argocd --type=json -p='[{"op": "remove", "path": "/metadata/finalizers"}]' 2>$null
    kubectl delete namespace argocd --ignore-not-found=true --force --grace-period=0 2>$null
    Write-Log "✅ Argo CD successfully removed." -ForegroundColor Green
} else {
    Write-Log "⚠️ kubectl not found, skipping Argo CD cleanup." -ForegroundColor Yellow
}


# ==============================================================================
# 2. REMOVING NGINX INGRESS CONTROLLER
# ==============================================================================
Write-Host "`n==========================================================" -ForegroundColor Cyan
Write-Host "2. Removing Nginx Ingress Controller" -ForegroundColor Yellow
Write-Host "==========================================================" -ForegroundColor Cyan

if (Get-Command helm -ErrorAction SilentlyContinue) {
    Write-Log "Uninstalling ingress-nginx Helm release..."
    helm uninstall ingress-nginx -n ingress-nginx --ignore-not-found=true 2>$null
    kubectl delete namespace ingress-nginx --ignore-not-found=true --force --grace-period=0 2>$null
    Write-Log "✅ Nginx Ingress Controller successfully removed." -ForegroundColor Green
} else {
    Write-Log "⚠️ Helm not found, skipping Ingress cleanup." -ForegroundColor Yellow
}


# ==============================================================================
# 3. REMOVING HASHICORP VAULT
# ==============================================================================
Write-Host "`n==========================================================" -ForegroundColor Cyan
Write-Host "3. Removing HashiCorp Vault" -ForegroundColor Yellow
Write-Host "==========================================================" -ForegroundColor Cyan

if (Get-Command helm -ErrorAction SilentlyContinue) {
    Write-Log "Uninstalling Vault Helm release..."
    helm uninstall vault -n vault --ignore-not-found=true 2>$null
    kubectl delete namespace vault --force --grace-period=0 --ignore-not-found=true 2>$null
    kubectl delete mutatingwebhookconfiguration,validatingwebhookconfiguration -l app.kubernetes.io/name=vault --ignore-not-found=true 2>$null
    kubectl delete clusterrole,clusterrolebinding -l app.kubernetes.io/name=vault --ignore-not-found=true 2>$null
    Write-Log "✅ HashiCorp Vault successfully removed." -ForegroundColor Green
} else {
    Write-Log "⚠️ Helm not found, skipping Vault cleanup." -ForegroundColor Yellow
}


# ==============================================================================
# 4. REMOVING MONITORING STACK (Prometheus & Grafana)
# ==============================================================================
Write-Host "`n==========================================================" -ForegroundColor Cyan
Write-Host "4. Removing Prometheus & Grafana (Monitoring Stack)" -ForegroundColor Yellow
Write-Host "==========================================================" -ForegroundColor Cyan

if (Get-Command helm -ErrorAction SilentlyContinue) {
    Write-Log "Uninstalling prometheus-stack Helm release..."
    helm uninstall prometheus-stack -n monitoring --ignore-not-found=true 2>$null
    kubectl delete namespace monitoring --ignore-not-found=true --force --grace-period=0 2>$null
    Write-Log "✅ Monitoring stack successfully removed." -ForegroundColor Green
} else {
    Write-Log "⚠️ Helm not found, skipping Prometheus/Grafana cleanup." -ForegroundColor Yellow
}


# ==============================================================================
# 5. REMOVING PGADMIN
# ==============================================================================
Write-Host "`n==========================================================" -ForegroundColor Cyan
Write-Host "5. Removing PGAdmin" -ForegroundColor Yellow
Write-Host "==========================================================" -ForegroundColor Cyan

if (Get-Command helm -ErrorAction SilentlyContinue) {
    Write-Log "Uninstalling pgadmin Helm release..."
    helm uninstall pgadmin -n default --ignore-not-found=true 2>$null
    Write-Log "✅ PGAdmin successfully removed." -ForegroundColor Green
} else {
    Write-Log "⚠️ Helm not found, skipping PGAdmin cleanup." -ForegroundColor Yellow
}


# ==============================================================================
# 6. REMOVING ACTIVEMQ ARTEMIS
# ==============================================================================
Write-Host "`n==========================================================" -ForegroundColor Cyan
Write-Host "6. Removing ActiveMQ Artemis" -ForegroundColor Yellow
Write-Host "==========================================================" -ForegroundColor Cyan

if (Get-Command helm -ErrorAction SilentlyContinue) {
    Write-Log "Uninstalling Artemis Helm release..."
    helm uninstall artemis -n artemis --ignore-not-found=true --no-hooks 2>$null
    kubectl delete namespace artemis --ignore-not-found=true --force --grace-period=0 2>$null
    Write-Log "✅ ActiveMQ Artemis successfully removed." -ForegroundColor Green
} else {
    Write-Log "⚠️ Helm not found, skipping Artemis cleanup." -ForegroundColor Yellow
}


# ==============================================================================
# 7. CLEANING UP LOCAL LOCK & TEMP FILES
# ==============================================================================
Write-Host "`n==========================================================" -ForegroundColor Cyan
Write-Host "7. Cleaning up Local Temporary Files" -ForegroundColor Yellow
Write-Host "==========================================================" -ForegroundColor Cyan

$tempFiles = @("vault-keys.json", "argo-patch.json")
foreach ($file in $tempFiles) {
    if (Test-Path $file) {
        Remove-Item $file -Force -ErrorAction SilentlyContinue
        Write-Log "🗑️ Removed local temporary file: $file" -ForegroundColor Yellow
    }
}


# ==============================================================================
# 8. STOPPING DOCKER COMPOSE SERVICES
# ==============================================================================
Write-Host "`n==========================================================" -ForegroundColor Cyan
Write-Host "8. Stopping Core Docker Compose Services" -ForegroundColor Yellow
Write-Host "==========================================================" -ForegroundColor Cyan

if (Get-Command docker -ErrorAction SilentlyContinue) {
    Write-Log "Stopping and removing Docker Compose containers, networks, and volumes..."
    docker compose down -v --remove-orphans
    
    Write-Log "Logging out from Docker registry..." -ForegroundColor Yellow
    docker logout 2>$null
    Write-Log "✅ Docker services stopped and cleaned." -ForegroundColor Green
} else {
    Write-Log "⚠️ Docker not found, skipping container cleanup." -ForegroundColor Yellow
}


# ==============================================================================
# 9. REMOVING HASHICORP TERRAFORM CLI
# ==============================================================================
Write-Host "`n==========================================================" -ForegroundColor Cyan
Write-Host "9. Removing HashiCorp Terraform CLI" -ForegroundColor Yellow
Write-Host "==========================================================" -ForegroundColor Cyan

if (Get-Command terraform -ErrorAction SilentlyContinue) {
    Write-Log "Uninstalling HashiCorp Terraform via winget..." -ForegroundColor Cyan
    try {
        winget uninstall Hashicorp.Terraform --accept-source-agreements | Out-Null
        Write-Log "✅ HashiCorp Terraform successfully uninstalled." -ForegroundColor Green
    } catch {
        Write-Log "⚠️ Failed to uninstall Terraform automatically. You can remove it manually." -ForegroundColor Yellow
    }
} else {
    Write-Log "⚠️ Terraform is not detected on the system, skipping." -ForegroundColor Yellow
}


# ==============================================================================
# FINAL COMPLETION
# ==============================================================================
Write-Host "`n==========================================================" -ForegroundColor Green
Write-Host "✅ Done! Uninstallation and cleanup successful." -ForegroundColor Green
Write-Host "==========================================================" -ForegroundColor Green
Write-Log "All Kubernetes namespaces, Helm releases, Docker containers, Terraform CLI, and temporary files have been fully purged."
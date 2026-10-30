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
Write-Host "1. Removing Argo CD from Kubernetes" -ForegroundColor Yellow
Write-Host "==========================================================" -ForegroundColor Cyan

Write-Log "Removing finalizers natively via kubectl patch to prevent deadlocks..."
kubectl patch application --all -n argocd -p '{"metadata":{"finalizers":[]}}' --type=merge 2>$null
kubectl patch appproject --all -n argocd -p '{"metadata":{"finalizers":[]}}' --type=merge 2>$null

Write-Log "Cleaning up Applications and Projects..."
kubectl delete applications --all -n argocd --ignore-not-found=true --force --grace-period=0
kubectl delete appprojects --all -n argocd --ignore-not-found=true --force --grace-period=0

# Write-Host "Deleting all Argo CD installation resources..."
# kubectl delete -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml --ignore-not-found=true

Write-Log "Deleting remaining Custom Resource Definitions (CRD)..."
kubectl delete crd applications.argoproj.io applicationsets.argoproj.io appprojects.argoproj.io applicationsyncwindows.argoproj.io --ignore-not-found=true

Write-Log "Patching and deleting namespace argocd..."
kubectl patch namespace argocd --type=json -p='[{"op": "remove", "path": "/metadata/finalizers"}]' 2>$null
kubectl delete namespace argocd --ignore-not-found=true --force --grace-period=0

Write-Host "`n==========================================================" -ForegroundColor Cyan
Write-Host "2. Removing Prometheus & Grafana (Monitoring Stack)" -ForegroundColor Yellow
Write-Host "==========================================================" -ForegroundColor Cyan
if (Get-Command helm -ErrorAction SilentlyContinue) {
    Write-Log "Uninstalling prometheus-stack Helm release..."
    helm uninstall prometheus-stack -n monitoring --ignore-not-found=true
    
    Write-Log "Deleting namespace monitoring..."
    kubectl delete namespace monitoring --ignore-not-found=true
} else {
    Write-Log "Helm is not installed, skipping Prometheus cleanup." -ForegroundColor Yellow
}

Write-Host "`n==========================================================" -ForegroundColor Cyan
Write-Host "3. Removing HashiCorp Vault" -ForegroundColor Yellow
Write-Host "==========================================================" -ForegroundColor Cyan

if (Get-Command helm -ErrorAction SilentlyContinue) {
    Write-Log "Uninstalling vault Helm release..."
    helm uninstall vault -n vault --ignore-not-found=true
    
    # Write-Host "Menghapus Persistent Volume (PVC) milik Vault..." -ForegroundColor Cyan
    # kubectl delete pvc data-vault-0 -n vault --ignore-not-found=true
    
    Write-Log "Deleting namespace vault..."
    kubectl delete namespace vault --force --grace-period=0 --ignore-not-found=true
} else {
    Write-Log "Helm is not installed, skipping Vault cleanup." -ForegroundColor Yellow
}

Write-Log "Cleaning up leftover local Vault lock files..." -ForegroundColor Cyan
Remove-Item "vault-keys.json" -ErrorAction SilentlyContinue

Write-Host "`n==========================================================" -ForegroundColor Cyan
Write-Host "4. Removing PGAdmin" -ForegroundColor Yellow
Write-Host "==========================================================" -ForegroundColor Cyan
if (Get-Command helm -ErrorAction SilentlyContinue) {
    Write-Log "Uninstalling pgadmin Helm release..."
    helm uninstall pgadmin -n default --ignore-not-found=true
} else {
    Write-Log "Helm is not installed, skipping PGAdmin cleanup." -ForegroundColor Yellow
}

# Write-Host "`n==========================================================" -ForegroundColor Cyan
# Write-Host "5. Removing ActiveMQ Artemis (via kubectl)" -ForegroundColor Yellow
# Write-Host "==========================================================" -ForegroundColor Cyan
# Write-Host "Cleaning up Artemis specific workloads (Deployment & StatefulSet)..." -ForegroundColor Yellow
# kubectl delete deployment artemis -n artemis --ignore-not-found=true
# kubectl delete statefulset artemis -n artemis --ignore-not-found=true
# Write-Host "Deleting remaining resources in artemis namespace (Services, PVC, etc)..." -ForegroundColor Yellow
# kubectl delete all --all -n artemis --ignore-not-found=true
# Write-Host "Deleting namespace artemis..." -ForegroundColor Yellow
# kubectl delete namespace artemis --ignore-not-found=true

Write-Host "`n==========================================================" -ForegroundColor Cyan
Write-Host "5. Removing ActiveMQ Artemis (via Helm)" -ForegroundColor Yellow
Write-Host "==========================================================" -ForegroundColor Cyan

if (Get-Command helm -ErrorAction SilentlyContinue) {
    Write-Log "Uninstalling artemis Helm release..." -ForegroundColor Yellow
    helm uninstall artemis -n artemis --ignore-not-found=true --no-hooks
    
    Write-Log "Deleting Persistent Volume Claims (PVC) to wipe data..." -ForegroundColor Yellow
    kubectl get pvc -n artemis -o jsonpath='{.items[*].metadata.name}' 2>$null | ForEach-Object {
        if ($_ -ne "") {
            Write-Log "Force deleting PVC: $_" -ForegroundColor Yellow
            kubectl delete pvc $_ -n artemis --force --grace-period=0 --ignore-not-found=true
        }
    }
    
    Write-Log "Deleting namespace artemis..." -ForegroundColor Yellow
    kubectl delete namespace artemis --ignore-not-found=true --force --grace-period=0
    
    Write-Log "✅ Artemis cleanup completed successfully." -ForegroundColor Green
} else {
    Write-Log "⚠️ Helm is not installed, skipping ActiveMQ Artemis cleanup." -ForegroundColor Yellow
}


Write-Host "`n==========================================================" -ForegroundColor Cyan
Write-Host "6. Stopping Jenkins, PostgreSQL, and MinIO (Docker Compose)" -ForegroundColor Yellow
Write-Host "==========================================================" -ForegroundColor Cyan
Write-Host "Stopping and removing Docker containers and default networks..."
# docker compose down --rmi all
# docker image prune -f
# docker builder prune -f
docker compose down

Write-Log "`nLogging out from Docker registry to clear credentials..." -ForegroundColor Yellow
docker logout

Write-Host "`n==========================================================" -ForegroundColor Green
Write-Host "✅ Done! Uninstallation successful." -ForegroundColor Green
Write-Host "==========================================================" -ForegroundColor Green
Write-Log "All services in Docker Compose and Kubernetes have been fully cleaned up."
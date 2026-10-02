Write-Host "==========================================================" -ForegroundColor Cyan
Write-Host "🗑️ 1. Removing Argo CD from Kubernetes" -ForegroundColor Yellow
Write-Host "==========================================================" -ForegroundColor Cyan

Write-Host "Cleaning up Applications and Projects (to avoid stuck namespaces)..."
kubectl delete applications --all -n argocd --ignore-not-found=true
kubectl delete appprojects --all -n argocd --ignore-not-found=true

Write-Host "Deleting all Argo CD installation resources..."
kubectl delete -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml --ignore-not-found=true

Write-Host "Deleting namespace argocd..."
kubectl delete namespace argocd --ignore-not-found=true

Write-Host "Deleting remaining Custom Resource Definitions (CRD)..."
kubectl delete crd applications.argoproj.io applicationsets.argoproj.io appprojects.argoproj.io applicationsyncwindows.argoproj.io --ignore-not-found=true

Write-Host "`n==========================================================" -ForegroundColor Cyan
Write-Host "🗑️ 2. Removing Prometheus & Grafana (Monitoring Stack)" -ForegroundColor Yellow
Write-Host "==========================================================" -ForegroundColor Cyan
if (Get-Command helm -ErrorAction SilentlyContinue) {
    Write-Host "Uninstalling prometheus-stack Helm release..."
    helm uninstall prometheus-stack -n monitoring --ignore-not-found=true
    
    Write-Host "Deleting namespace monitoring..."
    kubectl delete namespace monitoring --ignore-not-found=true
} else {
    Write-Host "Helm is not installed, skipping Prometheus cleanup." -ForegroundColor Yellow
}

Write-Host "`n==========================================================" -ForegroundColor Cyan
Write-Host "🗑️ 3. Removing HashiCorp Vault" -ForegroundColor Yellow
Write-Host "==========================================================" -ForegroundColor Cyan
if (Get-Command helm -ErrorAction SilentlyContinue) {
    Write-Host "Uninstalling vault Helm release..."
    helm uninstall vault -n vault --ignore-not-found=true
    
    Write-Host "Deleting namespace vault..."
    kubectl delete namespace vault --ignore-not-found=true
} else {
    Write-Host "Helm is not installed, skipping Vault cleanup." -ForegroundColor Yellow
}

Write-Host "`n==========================================================" -ForegroundColor Cyan
Write-Host "🛑 4. Stopping Jenkins, PostgreSQL, and pgAdmin (Docker)" -ForegroundColor Yellow
Write-Host "==========================================================" -ForegroundColor Cyan
Write-Host "Stopping and removing Docker containers and default networks..."
docker compose down

Write-Host "`n==========================================================" -ForegroundColor Green
Write-Host "✅ Done! Uninstallation successful." -ForegroundColor Green
Write-Host "==========================================================" -ForegroundColor Green
Write-Host "All services in Docker Desktop and Kubernetes have been fully cleaned up."
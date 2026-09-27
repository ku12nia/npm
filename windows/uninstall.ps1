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
Write-Host "🛑 2. Stopping Jenkins, PostgreSQL, and pgAdmin (Docker)" -ForegroundColor Yellow
Write-Host "==========================================================" -ForegroundColor Cyan

docker compose down

Write-Host "`n==========================================================" -ForegroundColor Green
Write-Host "✅ Done! Uninstallation successful." -ForegroundColor Green
Write-Host "==========================================================" -ForegroundColor Green
Write-Host "All services in Docker Desktop and Argo CD on Kubernetes have been cleaned up."
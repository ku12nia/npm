Write-Host "==========================================================" -ForegroundColor Cyan
Write-Host "🗑️ 1. Removing Argo CD from Kubernetes" -ForegroundColor Yellow
Write-Host "==========================================================" -ForegroundColor Cyan

Write-Host "Removing finalizers natively via kubectl patch to prevent deadlocks..."
kubectl patch application --all -n argocd -p '{"metadata":{"finalizers":[]}}' --type=merge 2>$null
kubectl patch appproject --all -n argocd -p '{"metadata":{"finalizers":[]}}' --type=merge 2>$null

Write-Host "Cleaning up Applications and Projects..."
kubectl delete applications --all -n argocd --ignore-not-found=true --force --grace-period=0
kubectl delete appprojects --all -n argocd --ignore-not-found=true --force --grace-period=0

Write-Host "Deleting all Argo CD installation resources..."
kubectl delete -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml --ignore-not-found=true

Write-Host "Deleting remaining Custom Resource Definitions (CRD)..."
kubectl delete crd applications.argoproj.io applicationsets.argoproj.io appprojects.argoproj.io applicationsyncwindows.argoproj.io --ignore-not-found=true

Write-Host "Patching and deleting namespace argocd..."
kubectl patch namespace argocd --type=json -p='[{"op": "remove", "path": "/metadata/finalizers"}]' 2>$null
kubectl delete namespace argocd --ignore-not-found=true --force --grace-period=0

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
Write-Host "🗑️ 4. Removing PGAdmin" -ForegroundColor Yellow
Write-Host "==========================================================" -ForegroundColor Cyan
if (Get-Command helm -ErrorAction SilentlyContinue) {
    Write-Host "Uninstalling pgadmin Helm release..."
    helm uninstall pgadmin -n default --ignore-not-found=true
} else {
    Write-Host "Helm is not installed, skipping PGAdmin cleanup." -ForegroundColor Yellow
}

# Write-Host "`n==========================================================" -ForegroundColor Cyan
# Write-Host "🗑️ 5. Removing ActiveMQ Artemis" -ForegroundColor Yellow
# Write-Host "==========================================================" -ForegroundColor Cyan
# Write-Host "Cleaning up Artemis specific workloads (Deployment & StatefulSet)..." -ForegroundColor Yellow
# kubectl delete deployment artemis -n artemis --ignore-not-found=true
# kubectl delete statefulset artemis -n artemis --ignore-not-found=true
# Write-Host "Deleting remaining resources in artemis namespace (Services, PVC, etc)..." -ForegroundColor Yellow
# kubectl delete all --all -n artemis --ignore-not-found=true
# Write-Host "Deleting namespace artemis..." -ForegroundColor Yellow
# kubectl delete namespace artemis --ignore-not-found=true

Write-Host "`n==========================================================" -ForegroundColor Cyan
Write-Host "🗑️ 5. Removing ActiveMQ Artemis (via Helm)" -ForegroundColor Yellow
Write-Host "==========================================================" -ForegroundColor Cyan

if (Get-Command helm -ErrorAction SilentlyContinue) {
    Write-Host "Uninstalling artemis Helm release..." -ForegroundColor Yellow
    helm uninstall artemis -n artemis --ignore-not-found=true
    
    # Wajib ada: Helm tidak menghapus PVC bawaan StatefulSet secara otomatis
    Write-Host "Deleting Persistent Volume Claims (PVC) to wipe data..." -ForegroundColor Yellow
    kubectl delete pvc --all -n artemis --ignore-not-found=true
    
    Write-Host "Deleting namespace artemis..." -ForegroundColor Yellow
    kubectl delete namespace artemis --ignore-not-found=true --force --grace-period=0
} else {
    Write-Host "Helm is not installed, skipping ActiveMQ Artemis cleanup." -ForegroundColor Yellow
}


Write-Host "`n==========================================================" -ForegroundColor Cyan
Write-Host "🛑 6. Stopping Jenkins, PostgreSQL, and MinIO (Docker Compose)" -ForegroundColor Yellow
Write-Host "==========================================================" -ForegroundColor Cyan
Write-Host "Stopping and removing Docker containers and default networks..."
docker compose down --rmi all
docker image prune -f
docker builder prune -f

Write-Host "`n==========================================================" -ForegroundColor Green
Write-Host "✅ Done! Uninstallation successful." -ForegroundColor Green
Write-Host "==========================================================" -ForegroundColor Green
Write-Host "All services in Docker Compose and Kubernetes have been fully cleaned up."
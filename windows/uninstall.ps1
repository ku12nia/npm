Write-Host "==========================================================" -ForegroundColor Cyan
Write-Host "🗑️ 1. Menghapus Argo CD dari Kubernetes" -ForegroundColor Yellow
Write-Host "==========================================================" -ForegroundColor Cyan

Write-Host "Membersihkan Applications dan Projects (menghindari namespace stuck)..."
kubectl delete applications --all -n argocd --ignore-not-found=true
kubectl delete appprojects --all -n argocd --ignore-not-found=true

Write-Host "Menghapus semua resource instalasi Argo CD..."
kubectl delete -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml --ignore-not-found=true

Write-Host "Menghapus namespace argocd..."
kubectl delete namespace argocd --ignore-not-found=true

Write-Host "Menghapus sisa Custom Resource Definitions (CRD)..."
kubectl delete crd applications.argoproj.io applicationsets.argoproj.io appprojects.argoproj.io applicationsyncwindows.argoproj.io --ignore-not-found=true

Write-Host "`n==========================================================" -ForegroundColor Cyan
Write-Host "🛑 2. Menghentikan Jenkins, PostgreSQL, dan pgAdmin (Docker)" -ForegroundColor Yellow
Write-Host "==========================================================" -ForegroundColor Cyan

# Hapus -v jika Anda tidak ingin menghapus volume data database/jenkins
docker compose down

Write-Host "`n==========================================================" -ForegroundColor Green
Write-Host "✅ SELESAI! UNINSTALL BERHASIL" -ForegroundColor Green
Write-Host "==========================================================" -ForegroundColor Green
Write-Host "Semua layanan di Docker Desktop dan Argo CD di Kubernetes telah dibersihkan."
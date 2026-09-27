#!/bin/bash

echo "=========================================================="
echo "🗑️ 1. Menghapus Argo CD dari Kubernetes"
echo "=========================================================="
echo "Membersihkan Applications dan Projects (menghindari namespace stuck)..."
kubectl delete applications --all -n argocd --ignore-not-found=true
kubectl delete appprojects --all -n argocd --ignore-not-found=true

echo "Menghapus semua resource instalasi Argo CD..."
kubectl delete -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml --ignore-not-found=true

echo "Menghapus namespace argocd..."
kubectl delete namespace argocd --ignore-not-found=true

echo "Menghapus sisa Custom Resource Definitions (CRD)..."
kubectl delete crd applications.argoproj.io applicationsets.argoproj.io appprojects.argoproj.io applicationsyncwindows.argoproj.io --ignore-not-found=true

echo ""
echo "=========================================================="
echo "🛑 2. Menghentikan Jenkins, PostgreSQL, dan pgAdmin (Docker)"
echo "=========================================================="
# Hapus flag "-v" di bawah ini jika Anda TIDAK INGIN menghapus data 
# (seperti data job Jenkins atau tabel di PostgreSQL)
docker compose down

echo ""
echo "=========================================================="
echo "✅ SELESAI! UNINSTALL BERHASIL"
echo "=========================================================="
echo "Semua layanan di Docker dan Argo CD di Kubernetes telah dibersihkan."
echo "=========================================================="
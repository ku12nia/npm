#!/bin/bash

echo "=========================================================="
echo "🚀 1. Menjalankan Jenkins, PostgreSQL, dan pgAdmin (Docker)"
echo "=========================================================="
docker compose up -d

echo ""
echo "=========================================================="
echo "⛵ 2. Setup Argo CD di Kubernetes"
echo "=========================================================="
# Pastikan cluster Kubernetes (Minikube / Docker Desktop) sudah jalan
kubectl delete namespace argocd --ignore-not-found=true --force --grace-period=0
kubectl create namespace argocd
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml

echo "Menunggu Pods Argo CD Ready (bisa memakan waktu 1-2 menit)..."
kubectl wait --for=condition=ready pod --all -n argocd --timeout=300s

echo ""
echo "=========================================================="
echo "🔑 3. Mengambil Password Initial Argo CD"
echo "=========================================================="
echo -n "Password Admin Argo CD: "
kubectl get secret argocd-initial-admin-secret -n argocd -o jsonpath="{.data.password}" | base64 -d
echo ""

echo ""
echo "=========================================================="
echo "✅ SELESAI! SETUP BERHASIL"
echo "=========================================================="
echo "🌐 AKSES LAYANAN ANDA:"
echo "- 🛠️ Jenkins    : http://localhost:8080"
echo "- 🐘 PostgreSQL : localhost:5432 (User: postgres, Pass: passwordku)"
echo "- 🖥️ pgAdmin    : http://localhost:8081 (User: admin@admin.com, Pass: adminpassword)"
echo "                   *Saat menambah server di pgAdmin, gunakan 'postgres' sebagai Hostname/Address"
echo "- 🐙 Argo CD    : Jalankan perintah ini untuk mengakses:"
echo "                  kubectl port-forward svc/argocd-server -n argocd 8082:443"
echo "                  Lalu buka: https://localhost:8082 (User: admin)"
echo "=========================================================="
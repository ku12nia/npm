#!/bin/bash
cd /vagrant

echo "=========================================================="
echo "🗑️ 1. Removing Argo CD from Kubernetes"
echo "=========================================================="
kubectl patch application --all -n argocd -p '{"metadata":{"finalizers":[]}}' --type=merge 2>/dev/null
kubectl patch appproject --all -n argocd -p '{"metadata":{"finalizers":[]}}' --type=merge 2>/dev/null

kubectl delete applications --all -n argocd --ignore-not-found=true --force --grace-period=0
kubectl delete appprojects --all -n argocd --ignore-not-found=true --force --grace-period=0

kubectl delete crd applications.argoproj.io applicationsets.argoproj.io appprojects.argoproj.io applicationsyncwindows.argoproj.io --ignore-not-found=true
kubectl patch namespace argocd --type=json -p='[{"op": "remove", "path": "/metadata/finalizers"}]' 2>/dev/null
kubectl delete namespace argocd --ignore-not-found=true --force --grace-period=0

echo -e "\n=========================================================="
echo "🗑️ 2. Removing Prometheus & Grafana (Monitoring Stack)"
echo "=========================================================="
helm uninstall prometheus-stack -n monitoring --ignore-not-found=true
kubectl delete namespace monitoring --ignore-not-found=true

echo -e "\n=========================================================="
echo "🗑️ 3. Removing HashiCorp Vault"
echo "=========================================================="
helm uninstall vault -n vault --ignore-not-found=true
kubectl delete namespace vault --force --grace-period=0 --ignore-not-found=true
rm -f /vagrant/vault-keys.json

echo -e "\n=========================================================="
echo "🗑️ 4. Removing PGAdmin"
echo "=========================================================="
helm uninstall pgadmin -n default --ignore-not-found=true

echo -e "\n=========================================================="
echo "🗑️ 5. Removing ActiveMQ Artemis (via Helm)"
echo "=========================================================="
helm uninstall artemis -n artemis --ignore-not-found=true
kubectl delete pvc --all -n artemis --ignore-not-found=true
kubectl delete namespace artemis --ignore-not-found=true --force --grace-period=0

echo -e "\n=========================================================="
echo "🛑 6. Stopping Jenkins, PostgreSQL, Nexus and MinIO (Docker Compose)"
echo "=========================================================="
docker compose down
docker logout

echo -e "\n=========================================================="
echo "✅ Done! Uninstallation successful."
echo "=========================================================="
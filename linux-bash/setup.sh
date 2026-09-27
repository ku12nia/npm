#!/bin/bash

echo "=========================================================="
echo "🚀 1. Running Jenkins, PostgreSQL, and pgAdmin (Docker)"
echo "=========================================================="
docker compose up -d

echo ""
echo "Waiting for Jenkins to initialize (20s)..."
sleep 20

jenkinsId=$(docker ps -q --filter "name=jenkins" | head -n 1)
jenkinsPass=""

if [ ! -z "$jenkinsId" ]; then
    jenkinsPass=$(docker exec $jenkinsId cat /var/jenkins_home/secrets/initialAdminPassword 2>/dev/null | tr -d '\r')
fi

if [ -z "$jenkinsPass" ]; then
    jenkinsPass="InitAdminPassword has been performed; please log in using the credentials registered in Jenkins."
fi

echo ""
echo "=========================================================="
echo "⛵ 2. Setup Argo CD di Kubernetes (Ensure the Kubernetes cluster (Minikube / Docker Desktop) is running.)"
echo "=========================================================="
kubectl delete namespace argocd --ignore-not-found=true --force --grace-period=0
kubectl create namespace argocd
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml

echo "Waiting for Argo CD pods to become ready (this may take 1–2 minutes)..."
kubectl wait --for=condition=ready pod --all -n argocd --timeout=300s

echo ""
echo "=========================================================="
echo "🔑 3. Complete The Installation Process"
echo "=========================================================="
echo -n "Password Admin Argo CD: "
argocdPass=$(kubectl get secret argocd-initial-admin-secret -n argocd -o jsonpath="{.data.password}" | base64 -d)
echo "$argocdPass"
echo ""

echo ""
echo "=========================================================="
echo "✅ Done! Setup successful."
echo "=========================================================="
echo "🌐 ACCESS YOUR SERVICES:"
echo " - Jenkins    : http://localhost:8080"
echo " InitialPasswordAdmin : $jenkinsPass"
echo " - PostgreSQL : localhost:5432 (User: postgres, Pass: pg-local)"
echo " - pgAdmin    : http://localhost:8081 (User: dedimk.devops@gmail.com, Pass: pgadmin-local)"
echo "                 *When adding a server in pgAdmin, use 'postgres' as the Hostname/Address."
echo " - Argo CD    : Run this command to access:"
echo "                  kubectl port-forward svc/argocd-server -n argocd 8082:443"
echo "                  Then open: https://localhost:8082"
echo "                  User   : admin"
echo "                  Password: $argocdPass"
echo "=========================================================="
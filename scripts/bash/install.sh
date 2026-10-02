#!/bin/bash

echo "=========================================================="
echo "🚀 1. Running Jenkins, PostgreSQL, and pgAdmin (Docker)"
echo "=========================================================="
docker compose up -d

echo ""
echo "Waiting for Jenkins to generate admin password (auto-detecting from logs)..."

jenkinsId=""
jenkinsPass=""

# 1. Pastikan container jenkins-local sudah terdeteksi dulu ID-nya
while [ -z "$jenkinsPass" ]; do
    jenkinsPass=$(docker exec $jenkinsId cat /var/jenkins_home/secrets/initialAdminPassword 2>/dev/null | tr -d '\r' | tr -d '\n' | head -c 32)
    
    if [ -z "$jenkinsPass" ]; then
        sleep 2
    fi
done

echo "Jenkins password successfully retrieved automatically!"

# 2. Otomatis baca password dari log Jenkins & bersihkan total dari karakter LF/CR/spasi
while [ -z "$jenkinsPass" ]; do
    rawLog=$(docker logs $jenkinsId 2>&1 | grep -A 1 "Please use the following password" | tail -n 1)
    jenkinsPass=$(echo "$rawLog" | tr -d '\r' | tr -d '\n' | xargs)
    
    if [ -z "$jenkinsPass" ]; then
        sleep 2
    fi
done

echo "Jenkins password successfully retrieved automatically!"
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
cleanJenkinsPass="${jenkinsPass:0:32}"

echo ""
echo "=========================================================="
echo "✅ Done! Setup successful."
echo "=========================================================="
echo "🌐 ACCESS YOUR SERVICES:"
echo " - Jenkins    : http://localhost:8080"
printf " InitialPasswordAdmin : " && docker exec $(docker ps -q --filter "name=jenkins-local" | head -n 1) cat /var/jenkins_home/secrets/initialAdminPassword 2>/dev/null | tr -d '\r' | tr -d '\n'
echo ""
echo " - PostgreSQL : localhost:5432 (User: postgres, Pass: pg-local)"
echo " - pgAdmin    : http://localhost:8081 (User: dedimk.devops@gmail.com, Pass: pgadmin-local)"
echo "                 *When adding a server in pgAdmin, use 'postgres' as the Hostname/Address."
echo " - Argo CD    : Run this command to access:"
echo "                  kubectl port-forward svc/argocd-server -n argocd 8082:443"
echo "                  Then open: https://localhost:8082"
echo "                  User   : admin"
echo "                  Password: $argocdPass"
echo "=========================================================="
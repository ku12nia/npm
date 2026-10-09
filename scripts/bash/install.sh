#!/bin/bash
WORKSPACE_NAME="nodejs-pipeline"
WORKSPACE_DIR="/var/jenkins_home/workspace/$WORKSPACE_NAME"

echo "=========================================================="
echo "🚀 1. Running Jenkins, PostgreSQL, and pgAdmin (Docker)"
echo "=========================================================="
docker compose up -d

echo ""
echo "Waiting for Jenkins container to start..."

jenkinsId=""
jenkinsPass=""

while [ -z "$jenkinsId" ]; do
    jenkinsId=$(docker ps -q --filter "name=jenkins-local" | head -n 1)
    if [ -z "$jenkinsId" ]; then
        sleep 2
    fi
done

echo "Jenkins container found (ID: $jenkinsId). Waiting for password generation..."

while [ -z "$jenkinsPass" ]; do
    jenkinsPass=$(docker exec $jenkinsId cat /var/jenkins_home/secrets/initialAdminPassword 2>/dev/null | tr -d '\r' | tr -d '\n' | head -c 32)
    if [ -z "$jenkinsPass" ]; then
        sleep 2
    fi
done

echo "Jenkins password successfully retrieved automatically!"

echo "Configuring git safe.directory inside Jenkins container for: $WORKSPACE_DIR"
docker exec -u root $jenkinsId git config --global --add safe.directory "$WORKSPACE_DIR"

echo "Setup Jenkins and Git configuration completed successfully!"

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
echo " You can create new pipeline with name "$WORKSPACE_NAME" on http://localhost:8080/view/all/newJob"
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
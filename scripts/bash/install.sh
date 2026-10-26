#!/bin/bash
echo "=========================================================="
echo "0. Prerequisite & Environment Setup (Vagrant/Ubuntu)"
echo "=========================================================="

# Update repository dan install tools wajib (jq untuk parsing JSON, dos2unix untuk fix file Windows)
apt-get update && apt-get install -y curl jq dos2unix apt-transport-https ca-certificates software-properties-common

# Masuk ke direktori yang disinkronisasi dengan Windows
cd /workspace

if [ -f ".env" ]; then
    echo "Loading environment variables from .env file..."
    dos2unix .env 2>/dev/null
    set -a; source .env; set +a
    echo "✅ .env loaded successfully."
else
    echo "⚠️ Warning: .env file not found! Please create it before proceeding."
    exit 1
fi

export WORKSPACE_NAME=${WORKSPACE_NAME:-"npm-cicd"}

echo "Installing Docker..."
if ! command -v docker &> /dev/null; then
    curl -fsSL https://get.docker.com -o get-docker.sh && sh get-docker.sh
    usermod -aG docker vagrant
fi

echo "Installing Helm..."
if ! command -v helm &> /dev/null; then
    curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
fi

echo "Installing K3s (with Nginx Ingress)"
if ! command -v k3s &> /dev/null; then
    curl -sfL https://get.k3s.io | INSTALL_K3S_EXEC="--disable traefik" sh -
    mkdir -p /home/vagrant/.kube
    cp /etc/rancher/k3s/k3s.yaml /home/vagrant/.kube/config
    chown -R vagrant:vagrant /home/vagrant/.kube
fi

export KUBECONFIG=/etc/rancher/k3s/k3s.yaml
sleep 10 # Tunggu K3s siap

echo -e "\n=========================================================="
echo "1. Running Jenkins, PostgreSQL, MinIO, and Nexus (Docker Compose)"
echo "=========================================================="
if [ -n "$DOCKER_USER" ] && [ -n "$DOCKER_PASS" ]; then
    echo "Logging in to Docker Hub as $DOCKER_USER..."
    echo "$DOCKER_PASS" | docker login --username "$DOCKER_USER" --password-stdin || echo "❌ Docker login failed!"
fi

docker run --rm -v npm_jenkins_home:/var/jenkins_home alpine chown -R 1000:1000 /var/jenkins_home 2>/dev/null
docker run --rm -v nexus_data:/nexus-data alpine chown -R 200:200 /nexus-data 2>/dev/null

composeImageName="npm-jenkins"
if [ -z "$(docker images -q $composeImageName 2>/dev/null)" ]; then
    echo "⚙️ Image not yet available locally. Initiating build."
    docker build -t npm-jenkins -f Dockerfile.linux . || exit 1
    export USERPROFILE="/home/vagrant"
    export LOCAL_PROJECT_PATH="/workspace"
    docker compose up -d
else
    echo "✅ Image '$composeImageName' Already available. Launching."
    export USERPROFILE="/home/vagrant"
    export LOCAL_PROJECT_PATH="/workspace"
    docker compose up -d
fi

echo -e "\nWaiting for Docker containers to initialize (20s)..."
sleep 20

jenkinsId=$(docker ps -q --filter "name=jenkins")
jenkinsPass="InitAdminPassword has been performed; please log in using the credentials registered in Jenkins."
if [ -n "$jenkinsId" ]; then
    rawPass=$(docker exec $jenkinsId cat /var/jenkins_home/secrets/initialAdminPassword 2>/dev/null | tr -d '\r')
    [ -n "$rawPass" ] && jenkinsPass=$rawPass
fi

echo -e "\n=========================================================="
echo "2. Setup Argo CD on Kubernetes (K3s)"
echo "=========================================================="
kubectl create namespace argocd --dry-run=client -o yaml | kubectl apply -f -
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
kubectl wait --for=condition=ready pod --all -n argocd --timeout=300s

argocdPass="P4ssw0rdArgoCD"
bcryptHash=$(kubectl exec -n argocd deploy/argocd-server -- argocd account bcrypt --password $argocdPass | tail -n 1 | tr -d '\r')
encodedHash=$(echo -n "$bcryptHash" | base64 -w 0)
encodedMtime=$(date -u +"%Y-%m-%dT%H:%M:%SZ" | base64 -w 0)

cat <<EOF > argo-patch.json
{ "data": { "admin.password": "$encodedHash", "admin.passwordMtime": "$encodedMtime" } }
EOF
kubectl patch secret argocd-secret -n argocd --type='merge' --patch-file argo-patch.json
rm -f argo-patch.json
kubectl delete secret argocd-initial-admin-secret -n argocd --ignore-not-found=true

kubectl apply -f k8s/argocd.yaml 2>/dev/null || echo "⚠️ Manifest k8s/argocd.yaml tidak ditemukan, dilewati."
kubectl rollout restart deploy/argocd-server -n argocd

echo -e "\n=========================================================="
echo "3. Setup Nginx Ingress Controller (Core Networking)"
echo "=========================================================="
helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx
helm repo update
helm upgrade --install ingress-nginx ingress-nginx/ingress-nginx --namespace ingress-nginx --create-namespace --set controller.service.type=LoadBalancer

echo -e "\n=========================================================="
echo "4. Setup PGAdmin on Kubernetes (K3s via Helm)"
echo "=========================================================="
helm repo add runix https://helm.runix.net
helm repo update
helm upgrade --install pgadmin runix/pgadmin4 -n default \
    --set env.email="$PGADMIN_EMAIL" \
    --set env.password="$PGADMIN_PASSWORD" \
    --set service.type=LoadBalancer \
    --set service.port=8081

echo -e "\n=========================================================="
echo "5. Setup Prometheus & Grafana on Kubernetes (K3s via Helm)"
echo "=========================================================="
kubectl create namespace monitoring --dry-run=client -o yaml | kubectl apply -f -
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo update
helm upgrade --install prometheus-stack prometheus-community/kube-prometheus-stack -n monitoring \
    --set grafana.service.type=LoadBalancer \
    --set grafana.service.port=8083 \
    --set prometheus.service.type=LoadBalancer \
    --set prometheus.service.port=9090

echo -e "\n=========================================================="
echo "6. Setup HashiCorp Vault on Kubernetes (K3s via Helm)"
echo "=========================================================="
helm repo add hashicorp https://helm.releases.hashicorp.com
helm repo update

keyFile="vault-keys.json"
rm -f $keyFile
kubectl create namespace vault --dry-run=client -o yaml | kubectl apply -f -
helm upgrade --install vault hashicorp/vault -n vault \
    --set "server.dev.enabled=false" \
    --set "server.dataStorage.enabled=true" \
    --set "server.dataStorage.size=1Gi" \
    --set "injector.enabled=true" \
    --set "ui.enabled=true" \
    --set "ui.serviceType=LoadBalancer" \
    --set "ui.externalPort=8200"

echo -e "\nWaiting for Vault pod to be created..."
sleep 10
kubectl wait --for=condition=ready pod/vault-0 -n vault --timeout=120s

vaultStatus=$(kubectl exec -n vault vault-0 -- vault status -format=json 2>/dev/null)
isInit=$(echo $vaultStatus | jq -r '.initialized')
if [ "$isInit" == "false" ]; then
    kubectl exec -n vault vault-0 -- vault operator init -key-shares=1 -key-threshold=1 -format=json > $keyFile
fi

unsealKey=$(jq -r '.unseal_keys_b64[0]' $keyFile)
VaultRootToken=$(jq -r '.root_token' $keyFile)

kubectl exec -n vault vault-0 -- vault operator unseal $unsealKey > /dev/null
kubectl exec -n vault vault-0 -- vault login $VaultRootToken > /dev/null

isSecretEngine=$(kubectl exec -n vault vault-0 -- vault secrets list -format=json 2>/dev/null | jq -r 'has("secret/")')
if [ "$isSecretEngine" == "false" ]; then
    kubectl exec -n vault vault-0 -- vault secrets enable -path=secret -version=2 kv > /dev/null
fi

echo -e "\nStoring all service credentials into Vault."
kubectl exec -n vault vault-0 -- vault kv put secret/database/postgres username="postgres" password="$POSTGRES_PASSWORD" >/dev/null
kubectl exec -n vault vault-0 -- vault kv put secret/pgadmin admin_email="$PGADMIN_EMAIL" admin_password="$PGADMIN_PASSWORD" >/dev/null
kubectl exec -n vault vault-0 -- vault kv put secret/minio root_user="$MINIO_ROOT_USER" root_password="$MINIO_ROOT_PASSWORD" >/dev/null
kubectl exec -n vault vault-0 -- vault kv put secret/artemis admin_user="$ARTEMIS_USER" admin_password="$ARTEMIS_PASSWORD" >/dev/null
kubectl exec -n vault vault-0 -- vault kv put secret/nexus admin_user="admin" admin_password="$NEXUS_PASSWORD" >/dev/null
kubectl exec -n vault vault-0 -- vault kv put secret/argocd admin_user="admin" admin_password="$ARGOCD_PASSWORD" >/dev/null
kubectl exec -n vault vault-0 -- vault kv put secret/jenkins/admin admin_user="jenkins" admin_password="$JENKINS_PASSWORD" >/dev/null
kubectl exec -n vault vault-0 -- vault kv put secret/jenkins/github username="$GITHUB_USER" token="$GITHUB_TOKEN" >/dev/null
kubectl exec -n vault vault-0 -- vault kv put secret/jenkins/dockerhub username="$DOCKER_USER" password="$DOCKER_PASS" >/dev/null

echo -e "\n=========================================================="
echo "7. Setup ActiveMQ Artemis on Kubernetes (K3s via Helm)"
echo "=========================================================="
helm repo add vromero https://vromero.github.io/activemq-artemis-helm/
helm repo update
helm upgrade --install artemis vromero/activemq-artemis -n artemis --create-namespace \
    --set adminUser="$ARTEMIS_USER" \
    --set adminPassword="$ARTEMIS_PASSWORD"

echo -e "\n=========================================================="
echo "8. Uploading Local Binary Files to Nexus Repository"
echo "=========================================================="
if [ -n "$NEXUS_PASSWORD" ]; then
    nexusUrl="http://127.0.0.1:8082"
    repoPayload='{"name":"raw-binaries","online":true,"storage":{"blobStoreName":"default","strictContentTypeValidation":false,"writePolicy":"ALLOW"},"raw":{"contentDisposition":"ATTACHMENT"}}'
    
    curl -s -o /dev/null -w "%{http_code}" -X POST "$nexusUrl/service/rest/v1/repositories/raw/hosted" \
      -u "admin:$NEXUS_PASSWORD" -H "Content-Type: application/json" -d "$repoPayload"
      
    if [ -d "/workspace/bin" ]; then
        for file in /workspace/bin/*; do
            if [ -f "$file" ]; then
                filename=$(basename "$file")
                echo "⬆️ Uploading $filename to Nexus."
                curl --silent --fail -u "admin:$NEXUS_PASSWORD" -T "$file" "$nexusUrl/repository/raw-binaries/$filename" || echo "⚠️ Failed to upload $filename"
            fi
        done
    fi
fi

grafanaPass=$(kubectl get secret prometheus-stack-grafana -n monitoring -o jsonpath="{.data.admin-password}" 2>/dev/null | base64 -d)
[ -z "$grafanaPass" ] && grafanaPass="prom-operator"

echo -e "\n=========================================================="
echo "Done! Setup successful."
echo "=========================================================="
echo "ACCESS YOUR SERVICES:"
echo " - Jenkins    : http://localhost:8080 (Login: jenkins / jenkins)"
echo "   InitAdmin  : $jenkinsPass"
echo " - Nexus 3    : http://localhost:8082 (User: admin, Pass: $NEXUS_PASSWORD)"
echo " - Argo CD    : https://localhost (User: admin, Pass: $argocdPass)"
echo " - Artemis    : http://localhost:8161 (User: $ARTEMIS_USER, Pass: $ARTEMIS_PASSWORD)"
echo " - Grafana    : http://localhost:8083 (User: admin, Pass: $grafanaPass)"
echo " - Prometheus : http://localhost:9090"
echo " - PGAdmin    : http://localhost:8081 (User: $PGADMIN_EMAIL, Pass: $PGADMIN_PASSWORD)"
echo " - PostgreSQL : localhost:5432 (User: postgres, Pass: $POSTGRES_PASSWORD)"
echo " - MinIO      : http://localhost:9001 (User: $MINIO_ROOT_USER, Pass: $MINIO_ROOT_PASSWORD)"
echo " - Vault      : http://localhost:8200 (Token: $VaultRootToken)"
echo "=========================================================="
Write-Host "==========================================================" -ForegroundColor Cyan
Write-Host "0. Prerequisite Checks" -ForegroundColor Yellow
Write-Host "==========================================================" -ForegroundColor Cyan

if (-not (Get-Command helm -ErrorAction SilentlyContinue)) {
    Write-Host "Helm is not detected! Attempting to install Helm using winget..." -ForegroundColor Yellow
    try {
        winget install Helm.Helm --accept-source-agreements --accept-package-agreements
        
        Write-Host "Refreshing Environment PATH variables..." -ForegroundColor Cyan
        $env:Path = [System.Environment]::GetEnvironmentVariable("Path","Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path","User")
        
        if (Get-Command helm -ErrorAction SilentlyContinue) {
            Write-Host "✅ Helm successfully installed and loaded into current session!" -ForegroundColor Green
        } else {
            throw "Helm command still not found after path refresh."
        }
    } catch {
        Write-Host "Failed to install/load Helm automatically. Please restart your terminal or install manually: https://helm.sh/docs/intro/install/" -ForegroundColor Red
        exit
    }
} else {
    Write-Host "✅ Helm is already installed." -ForegroundColor Green
}

Write-Host "`n==========================================================" -ForegroundColor Cyan
Write-Host "1. Running Jenkins, PostgreSQL, and pgAdmin (Docker Desktop)" -ForegroundColor Yellow
Write-Host "==========================================================" -ForegroundColor Cyan
docker run --rm -v npm_jenkins_home:/var/jenkins_home alpine chown -R 1000:1000 /var/jenkins_home 2>$null
docker compose build --no-cache
docker compose up -d

Write-Host "`nWaiting for Jenkins to initialize (20s)..." -ForegroundColor Magenta
Start-Sleep -Seconds 20

$jenkinsId = docker ps -q --filter "name=jenkins"
$jenkinsPass = ""

if ($jenkinsId) {
    $rawPass = docker exec $jenkinsId cat /var/jenkins_home/secrets/initialAdminPassword 2>$null
    if ($rawPass) {
        $jenkinsPass = $rawPass.Trim()
    }
    
    Write-Host "`nChecking kubectl installation inside the Jenkins container..." -ForegroundColor Cyan
    docker exec $jenkinsId kubectl version --client
}

if ([string]::IsNullOrWhiteSpace($jenkinsPass)) {$jenkinsPass = "InitAdminPassword has been performed; please log in using the credentials registered in Jenkins."
}

Write-Host "`n==========================================================" -ForegroundColor Cyan
Write-Host "2. Setup Argo CD on Kubernetes (Docker Desktop)" -ForegroundColor Yellow
Write-Host "==========================================================" -ForegroundColor Cyan
kubectl delete namespace argocd --ignore-not-found=true --force --grace-period=0
kubectl create namespace argocd
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
Write-Host "`nWaiting for Argo CD pods to become ready (this may take 1-2 minutes)..." -ForegroundColor Magenta
kubectl wait --for=condition=ready pod --all -n argocd --timeout=300s

Write-Host "Registering the ArgoCD Application manifest..." -ForegroundColor Cyan
# [REVISI] Path sudah diperbaiki untuk eksekusi dari root directory
kubectl apply -f k8s/argocd-apps/node-app-prod.yaml

Write-Host "`nPermanently exposing the ArgoCD UI (LoadBalancer)" -ForegroundColor Cyan
kubectl patch svc argocd-server -n argocd -p '{\"spec\": {\"type\": \"LoadBalancer\"}}'


Write-Host "`n==========================================================" -ForegroundColor Cyan
Write-Host "3. Setup Prometheus & Grafana on Kubernetes (Helm)" -ForegroundColor Yellow
Write-Host "==========================================================" -ForegroundColor Cyan
Write-Host "Creating 'monitoring' namespace..." -ForegroundColor Cyan
kubectl create namespace monitoring --dry-run=client -o yaml | kubectl apply -f -

Write-Host "Adding Prometheus Community Helm repo..." -ForegroundColor Cyan
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo update

Write-Host "Installing kube-prometheus-stack (Prometheus + Grafana)..." -ForegroundColor Cyan
helm upgrade --install prometheus-stack prometheus-community/kube-prometheus-stack -n monitoring `
    --set grafana.service.type=LoadBalancer `
    --set grafana.service.port=8083 `
    --set prometheus.service.type=LoadBalancer

Write-Host "`nWaiting for Prometheus & Grafana pods to become ready (this may take 1-2 minutes)..." -ForegroundColor Magenta
Start-Sleep -Seconds 15
kubectl wait --for=condition=ready pod --all -n monitoring --timeout=300s


Write-Host "`n==========================================================" -ForegroundColor Cyan
Write-Host "4. Setup HashiCorp Vault on Kubernetes (Helm)" -ForegroundColor Yellow
Write-Host "==========================================================" -ForegroundColor Cyan
Write-Host "Creating 'vault' namespace..." -ForegroundColor Cyan
kubectl create namespace vault --dry-run=client -o yaml | kubectl apply -f -

Write-Host "Adding HashiCorp Helm repo..." -ForegroundColor Cyan
helm repo add hashicorp https://helm.releases.hashicorp.com
helm repo update

Write-Host "Installing HashiCorp Vault (Dev Mode) and Injector..." -ForegroundColor Cyan
helm upgrade --install vault hashicorp/vault -n vault `
    --set "server.dev.enabled=true" `
    --set "injector.enabled=true" `
    --set "ui.enabled=true" `
    --set "ui.serviceType=LoadBalancer"

Write-Host "`nWaiting for Vault pods to become ready (this may take 1-2 minutes)..." -ForegroundColor Magenta
Start-Sleep -Seconds 10
kubectl wait --for=condition=ready pod --all -n vault --timeout=300s


Write-Host "`n==========================================================" -ForegroundColor Cyan
Write-Host "5. Complete The Installation Process" -ForegroundColor Yellow
Write-Host "==========================================================" -ForegroundColor Cyan

$encodedPass = kubectl get secret argocd-initial-admin-secret -n argocd -o jsonpath="{.data.password}"
if ($encodedPass) {
    $argocdPass = [System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($encodedPass))
} else {
    $argocdPass = "Failed to retrieve"
}

$grafanaPass = ""
$encodedGrafana = kubectl get secret prometheus-stack-grafana -n monitoring -o jsonpath="{.data.admin-password}" 2>$null
if ($encodedGrafana) {
    $grafanaPass = [System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($encodedGrafana))
} else {
    $grafanaPass = "prom-operator" # Default fallback
}

Write-Host "`n==========================================================" -ForegroundColor Green
Write-Host "Done! Setup successful." -ForegroundColor Green
Write-Host "==========================================================" -ForegroundColor Green
Write-Host "ACCESS YOUR SERVICES:"
Write-Host " - Jenkins    : http://localhost:8080"
Write-Host "   InitialAdmin : $jenkinsPass (Login: jenkins / jenkins)"  -ForegroundColor Green
Write-Host " - PostgreSQL : localhost:5432 (User: postgres, Pass: pg-local)"
Write-Host " - pgAdmin    : http://localhost:8081 (User: dedimk.devops@gmail.com, Pass: pgadmin-local)"
Write-Host " - Argo CD    : https://localhost (User: admin, Pass: $argocdPass)" -ForegroundColor Green
Write-Host " - Vault      : http://localhost:8200 (Token: root)" -ForegroundColor Green
Write-Host " - Grafana    : http://localhost:8083 (User: admin, Pass: $grafanaPass)" -ForegroundColor Green
Write-Host " - Prometheus : http://localhost:9090" -ForegroundColor Green
Write-Host "==========================================================" -ForegroundColor Green
Write-Host "==========================================================" -ForegroundColor Cyan
Write-Host "0. Prerequisite & Environment Setup" -ForegroundColor Yellow
Write-Host "==========================================================" -ForegroundColor Cyan

if (Test-Path ".env") {
    Write-Host "Loading environment variables from .env file..." -ForegroundColor Cyan
    Get-Content ".env" | ForEach-Object {
        if ($_ -match '^\s*([^#\s][^=]+)=(.*)$') {
            $name =$matches[1].Trim()
            $value =$matches[2].Trim()
            [Environment]::SetEnvironmentVariable($name,$value, "Process")
        }
    }
    Write-Host "✅ .env loaded successfully." -ForegroundColor Green
} else {
    Write-Host "⚠️ Warning: .env file not found! Please create it before proceeding." -ForegroundColor Red
    exit
}

$WorkspaceName = if ($env:WORKSPACE_NAME) { $env:WORKSPACE_NAME } else { "npm-cicd" }
$WorkspaceDir = "/var/jenkins_home/workspace/$WorkspaceName"

if (-not (Get-Command helm -ErrorAction SilentlyContinue)) {
    Write-Host "Helm is not detected! Attempting to install Helm using winget..." -ForegroundColor Yellow
    try {
        winget install Helm.Helm --accept-source-agreements --accept-package-agreements
        $env:Path = [System.Environment]::GetEnvironmentVariable("Path","Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path","User")
    } catch {
        Write-Host "Failed to install/load Helm automatically." -ForegroundColor Red
        exit
    }
} else {
    Write-Host "✅ Helm is already installed." -ForegroundColor Green
}

Write-Host "`n==========================================================" -ForegroundColor Cyan
Write-Host "1. Running Jenkins, PostgreSQL, and MinIO (Docker Compose)" -ForegroundColor Yellow
Write-Host "==========================================================" -ForegroundColor Cyan

if (-not [string]::IsNullOrWhiteSpace($env:DOCKER_USER) -and -not [string]::IsNullOrWhiteSpace($env:DOCKER_PASS)) {
    Write-Host "Logging in to Docker Hub as $($env:DOCKER_USER)..." -ForegroundColor Cyan
    $env:DOCKER_PASS | docker login --username $env:DOCKER_USER --password-stdin
    if ($LASTEXITCODE -ne 0) {
        Write-Host "❌ Docker login failed! Please check your credentials in .env" -ForegroundColor Red
        exit
    } else {
        Write-Host "✅ Docker login successful!" -ForegroundColor Green
    }
} else {
    Write-Host "⚠️ DOCKER_USER or DOCKER_PASS not found in .env, skipping explicit login..." -ForegroundColor Yellow
}

docker run --rm -v npm_jenkins_home:/var/jenkins_home alpine chown -R 1000:1000 /var/jenkins_home 2>$null
docker compose up -d --build
#docker compose build --no-cache

Write-Host "`nWaiting for Docker containers to initialize (20s)..." -ForegroundColor Magenta
Start-Sleep -Seconds 20

$jenkinsId = docker ps -q --filter "name=jenkins"
$jenkinsPass = ""

if ($jenkinsId) {$rawPass = docker exec $jenkinsId cat /var/jenkins_home/secrets/initialAdminPassword 2>$null
    if ($rawPass) { $jenkinsPass =$rawPass.Trim() }
}
if ([string]::IsNullOrWhiteSpace($jenkinsPass)) {$jenkinsPass = "InitAdminPassword has been performed; please log in using the credentials registered in Jenkins."
}

Write-Host "`n==========================================================" -ForegroundColor Cyan
Write-Host "2. Setup Argo CD on Kubernetes (K3s)" -ForegroundColor Yellow
Write-Host "==========================================================" -ForegroundColor Cyan

# 1. Bersihkan sisa instalasi lama
kubectl delete namespace argocd --ignore-not-found=true --force --grace-period=0
kubectl create namespace argocd

# 2. Install ArgoCD
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml

Write-Host "`nWaiting for Argo CD pods to become ready (ini butuh waktu beberapa menit)..." -ForegroundColor Magenta
kubectl wait --for=condition=ready pod --all -n argocd --timeout=300s

# 3. Kunci Password secara Permanen!
$argocdPass = "1pESp9R32v29ic-8"
Write-Host "`nMengunci password admin ArgoCD..." -ForegroundColor Green

# Minta ArgoCD Server membuatkan Bcrypt Hash yang valid secara native
$bcryptHash = kubectl exec -n argocd deploy/argocd-server -- argocd account bcrypt --password$argocdPass
$bcryptHash =$bcryptHash.Trim()

# Encode ke Base64 agar bisa disuntikkan ke K8s Secret
$encodedHash = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($bcryptHash))$encodedMtime = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes((Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")))

# Patch ArgoCD Secret dengan hash permanen
$patchJson = "[{`"op`": `"replace`", `"path`": `"/data/admin.password`", `"value`": `"$encodedHash`"}, {`"op`": `"replace`", `"path`": `"/data/admin.passwordMtime`", `"value`": `"$encodedMtime`"}]"
kubectl patch secret argocd-secret -n argocd --type='json' -p=$patchJson

# Hapus initial secret agar ArgoCD tidak mereset ulang passwordnya
kubectl delete secret argocd-initial-admin-secret -n argocd --ignore-not-found=true

# Restart ArgoCD Server agar membaca password baru
kubectl rollout restart deploy/argocd-server -n argocd
kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=argocd-server -n argocd --timeout=120s

Write-Host "[SUCCESS] Password ArgoCD berhasil dikunci mati menjadi: $argocdPass" -ForegroundColor Green

# 4. Terapkan Aplikasi & Expose Service
kubectl apply -f k8s/argocd-apps/node-app-prod.yaml
kubectl patch svc argocd-server -n argocd -p '{\"spec\": {\"type\": \"LoadBalancer\"}}'


Write-Host "`n==========================================================" -ForegroundColor Cyan
Write-Host "3. Setup PGAdmin on Kubernetes (K3s via Helm)" -ForegroundColor Yellow
Write-Host "==========================================================" -ForegroundColor Cyan
helm repo add runix https://helm.runix.net
helm repo update

helm upgrade --install pgadmin runix/pgadmin4 -n default `
    --set env.email="$env:PGADMIN_EMAIL" `
    --set env.password="$env:PGADMIN_PASSWORD" `
    --set service.type=LoadBalancer `
    --set service.port=8081


Write-Host "`n==========================================================" -ForegroundColor Cyan
Write-Host "4. Setup Prometheus & Grafana on Kubernetes (K3s via Helm)" -ForegroundColor Yellow
Write-Host "==========================================================" -ForegroundColor Cyan
kubectl create namespace monitoring --dry-run=client -o yaml | kubectl apply -f -
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo update

helm upgrade --install prometheus-stack prometheus-community/kube-prometheus-stack -n monitoring `
    --set grafana.service.type=LoadBalancer `
    --set grafana.service.port=8083 `
    --set prometheus.service.type=LoadBalancer `
    --set prometheus.service.port=9090


Write-Host "`n==========================================================" -ForegroundColor Cyan
Write-Host "5. Setup HashiCorp Vault on Kubernetes (K3s via Helm)" -ForegroundColor Yellow
Write-Host "==========================================================" -ForegroundColor Cyan
kubectl create namespace vault --dry-run=client -o yaml | kubectl apply -f -
helm repo add hashicorp https://helm.releases.hashicorp.com
helm repo update

helm upgrade --install vault hashicorp/vault -n vault `
    --set "server.dev.enabled=true" `
    --set "injector.enabled=true" `
    --set "ui.enabled=true" `
    --set "ui.serviceType=LoadBalancer" `
    --set "ui.externalPort=8200"


Write-Host "`n==========================================================" -ForegroundColor Cyan
Write-Host "6. Setup ActiveMQ Artemis on Kubernetes (K3s via Manifest)" -ForegroundColor Yellow
Write-Host "==========================================================" -ForegroundColor Cyan
Write-Host "Creating 'artemis' namespace..." -ForegroundColor Cyan
kubectl create namespace artemis --dry-run=client -o yaml | kubectl apply -f -

Write-Host "Injecting Artemis Credentials from .env to Kubernetes Secret..." -ForegroundColor Cyan
kubectl create secret generic artemis-credentials -n artemis `
    --from-literal=ARTEMIS_USER="$env:ARTEMIS_USER" `
    --from-literal=ARTEMIS_PASSWORD="$env:ARTEMIS_PASSWORD" `
    --dry-run=client -o yaml | kubectl apply -f -

Write-Host "Applying Artemis StatefulSet Manifest..." -ForegroundColor Cyan
kubectl apply -f k8s/artemis.yaml

Write-Host "`nWaiting for K3s pods to become ready (this may take a few minutes)..." -ForegroundColor Magenta
Start-Sleep -Seconds 15
kubectl wait --for=condition=ready pod --all -n monitoring --timeout=300s
kubectl wait --for=condition=ready pod --all -n vault --timeout=300s
kubectl wait --for=condition=ready pod --all -n artemis --timeout=300s

Write-Host "`n==========================================================" -ForegroundColor Cyan
Write-Host "7. Complete The Installation Process" -ForegroundColor Yellow
Write-Host "==========================================================" -ForegroundColor Cyan

$argocdPass = "1pESp9R32v29ic-8"

Write-Host "Menunggu ArgoCD Server siap untuk diset password-nya..." -ForegroundColor Green
Start-Sleep -Seconds 10

# Ambil password initial otomatis sebentar buat autentikasi internal
$encodedPass = kubectl get secret argocd-initial-admin-secret -n argocd -o jsonpath="{.data.password}" 2>$null
if ($encodedPass) {
    $tempPass = [System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($encodedPass))
    
    Write-Host "Mengubah password default menjadi password permanen..." -ForegroundColor Green
    # Tembak langsung ke pod argocd-server untuk update password secara resmi
    $podName = (kubectl get pods -n argocd -l app.kubernetes.io/name=argocd-server -o jsonpath="{.items[0].metadata.name}")
    
    if ($podName) {
        # Login lokal di dalam pod lalu ganti password
        kubectl exec -n argocd $podName -- argocd login localhost:8080 --username admin --password $tempPass --insecure 2>$null
        kubectl exec -n argocd $podName -- argocd account update-password --new-password $argocdPass 2>$null
        Write-Host "[SUCCESS] Password ArgoCD berhasil dipatenkan menjadi: $argocdPass" -ForegroundColor Green
    }
}

$grafanaPass = ""
$encodedGrafana = kubectl get secret prometheus-stack-grafana -n monitoring -o jsonpath="{.data.admin-password}" 2>$null
if ($encodedGrafana) {
    $grafanaPass = [System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($encodedGrafana))
} else {
    $grafanaPass = "prom-operator" 
}


Write-Host "`n==========================================================" -ForegroundColor Green
Write-Host "Done! Setup successful." -ForegroundColor Green
Write-Host "==========================================================" -ForegroundColor Green
Write-Host "ACCESS YOUR SERVICES:"
Write-Host " - Argo CD    : https://localhost (User: admin, Pass: $argocdPass " -ForegroundColor Green
Write-Host " - Jenkins    : http://localhost:8080"
Write-Host "   InitAdmin  : $jenkinsPass (Login: jenkins / jenkins)" -ForegroundColor Green
Write-Host " - Vault      : http://localhost:8200 (Token: root)" -ForegroundColor Green
Write-Host " - Grafana    : http://localhost:8083 (User: admin, Pass: $grafanaPass)" -ForegroundColor Green
Write-Host " - Prometheus : http://localhost:9090" -ForegroundColor Green
Write-Host " - PGAdmin    : http://localhost:8081 (User: $($env:PGADMIN_EMAIL), Pass: $($env:PGADMIN_PASSWORD))"
Write-Host " - PostgreSQL : localhost:5432 (User: postgres, Pass: $($env:POSTGRES_PASSWORD))"
Write-Host " - MinIO      : http://localhost:9001 (User: $($env:MINIO_ROOT_USER), Pass: $($env:MINIO_ROOT_PASSWORD))" -ForegroundColor Green
Write-Host " - Artemis    : http://localhost:8161 (User: $($env:ARTEMIS_USER), Pass: $($env:ARTEMIS_PASSWORD))" -ForegroundColor Green
Write-Host "==========================================================" -ForegroundColor Green
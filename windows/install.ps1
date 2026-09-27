Write-Host "==========================================================" -ForegroundColor Cyan
Write-Host "1. Running Jenkins, PostgreSQL, and pgAdmin (Docker)" -ForegroundColor Yellow
Write-Host "==========================================================" -ForegroundColor Cyan
docker compose up -d

Write-Host "`nWaiting for Jenkins to initialize (20s)..." -ForegroundColor Magenta
Start-Sleep -Seconds 20

$jenkinsId = docker ps -q --filter "name=jenkins"
$jenkinsPass = ""

if ($jenkinsId) {
    $containerId = $jenkinsId.Split([Environment]::NewLine)[0].Trim()
    if ($containerId) {
        $jenkinsPass = (docker exec $containerId cat /var/jenkins_home/secrets/initialAdminPassword 2>$null).Trim()
    }
}

if (-not $jenkinsPass) {
    $jenkinsPass = "InitAdminPassword has been performed; please log in using the credentials registered in Jenkins."
}

Write-Host "`n==========================================================" -ForegroundColor Cyan
Write-Host "2. Setup Argo CD di Kubernetes" -ForegroundColor Yellow
Write-Host "==========================================================" -ForegroundColor Cyan
kubectl delete namespace argocd --ignore-not-found=true --force --grace-period=0
kubectl create namespace argocd
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml

Write-Host "`nWaiting for Argo CD pods to become ready (this may take 1-2 minutes)..." -ForegroundColor Magenta
kubectl wait --for=condition=ready pod --all -n argocd --timeout=300s

Write-Host "`n==========================================================" -ForegroundColor Cyan
Write-Host "3. Complete The Installation Process" -ForegroundColor Yellow
Write-Host "==========================================================" -ForegroundColor Cyan

# Password Argo CD
$encodedPass = kubectl get secret argocd-initial-admin-secret -n argocd -o jsonpath="{.data.password}"
if ($encodedPass) {
    $argocdPass = [System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($encodedPass))
} else {
    $argocdPass = "Failed to retrieve"
}

Write-Host "`n==========================================================" -ForegroundColor Green
Write-Host "Done! Setup successful." -ForegroundColor Green
Write-Host "==========================================================" -ForegroundColor Green
Write-Host "ACCESS YOUR SERVICES:"
Write-Host " - Jenkins    : http://localhost:8080"
Write-Host "   InitialPasswordAdmin : $jenkinsPass" -ForegroundColor Green
Write-Host " - PostgreSQL : localhost:5432 (User: postgres, Pass: pg-local)"
Write-Host " - pgAdmin    : http://localhost:8081 (User: dedimk.devops@gmail.com, Pass: pgadmin-local)"
Write-Host "                *When adding a server in pgAdmin, use 'postgres' as the Hostname"
Write-Host " - Argo CD    : Run this command to access:"
Write-Host "                kubectl port-forward svc/argocd-server -n argocd 8082:443" -ForegroundColor Yellow
Write-Host "                Then open: https://localhost:8082"
Write-Host "                User   : admin"
Write-Host "                Password: $argocdPass" -ForegroundColor Green
Write-Host "==========================================================" -ForegroundColor Green
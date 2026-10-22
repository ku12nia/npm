![Jenkins](https://img.shields.io/badge/Jenkins-CI-blue?logo=jenkins)
![ArgoCD](https://img.shields.io/badge/ArgoCD-CD-orange?logo=argo)
![Kubernetes](https://img.shields.io/badge/Kubernetes-GitOps-blue?logo=kubernetes)
![Docker](https://img.shields.io/badge/Docker-Desktop-2496ED?logo=docker)
![Nexus](https://img.shields.io/badge/Nexus-Repository-1B1C1D?logo=sonatype)
![Postgres](https://img.shields.io/badge/PostgreSQL-Database-336791?logo=postgresql)
![Vault](https://img.shields.io/badge/Vault-Secrets-FF0000?logo=vault)
![Prometheus](https://img.shields.io/badge/Prometheus-Monitoring-E6522C?logo=prometheus)
![Grafana](https://img.shields.io/badge/Grafana-Dashboard-F46800?logo=grafana)
[![LinkedIn](https://img.shields.io/badge/Connect-LinkedIn-0A66C2?logo=linkedin)](https://www.linkedin.com/in/dedimohammadkurnia/)

This repository provides a ready-to-use **Full-Stack Local DevOps & GitOps** ecosystem. It integrates a modern CI/CD pipeline using Jenkins, local database management (PostgreSQL + pgAdmin), HashiCorp Vault for automated secrets management, monitoring with Prometheus & Grafana, message brokering with ActiveMQ, object storage with MinIO, a local artifactory via **Sonatype Nexus 3**, and automated deployments to Kubernetes using **ArgoCD** following the **App of Apps** pattern. The entire infrastructure is designed to run seamlessly on top of **Docker Desktop (K3s)**.

---

## 🏗️ Architecture & Ecosystem

This project applies the principle of **Separation of Concerns**, splitting the infrastructure between core Docker Compose services and Kubernetes (K3s) deployments:

### 1. Core Services (Docker Compose)
These components run directly on the Docker engine to provide stable base services:
- **Jenkins (CI Server):** Manages automated pipelines handling checkout, unit testing via Docker, building Docker images, pushing to Docker Hub, and updating environment-specific Helm manifests in Git.
- **Sonatype Nexus 3 (Artifactory):** Serves as a local repository manager (`raw-binaries`) hosting static binary files (such as `kubectl`, `argocd`, `buildx`, and `docker.tgz`). Uploads are automatically executed near the end of initialization to prevent boot timeouts.
- **PostgreSQL (Database):** Serves as the primary relational database system for application workloads.
- **MinIO (Object Storage):** Provides S3-compatible local object storage for file uploads, backups, and artifact storage.

### 2. Kubernetes Services (K3s via Docker Desktop)
These components run inside the Kubernetes cluster to mimic production-grade orchestration:
- **ArgoCD (Continuous Deployment):** Acts as the primary GitOps controller. Monitors the `k8s/` directory in Git and synchronizes manifest changes directly into target namespaces (`dev-apps`, `staging-apps`, `prod-apps`).
- **HashiCorp Vault:** Deployed via Helm with persistent storage (1Gi PVC). Automatically initialized, unsealed, and pre-populated (*auto-seeded*) with all service credentials and pipeline secrets under the `secret/` KV v2 engine.
- **pgAdmin (Database Manager):** Deployed via Helm to provide a web-based GUI for managing PostgreSQL (connected via `host.docker.internal`).
- **ActiveMQ Artemis (Message Broker):** Deployed via Helm (`artemis` namespace) to handle asynchronous messaging.
- **Monitoring Stack (Prometheus & Grafana):** Deployed via `kube-prometheus-stack` Helm chart to automatically scrape cluster metrics, monitor pod health, and visualize system performance.

---

## 📂 Repository Structure

```text
📦 npm
 ┣ 📂 ci                   
 ┃ ┗ 📜 Jenkinsfile        
  📂 config               
 ┃ ┣ 📜 postgres17-connect.json
 ┃ ┣ 📜 prometheus.yml
 ┃ ┗ 📜 pgadmin.json
 ┣ 📂 k8s
 ┃ ┣ 📜 argocd.yaml        # ArgoCD Ingress, RBAC, & Root App
 ┃ ┣ 📂 argocd-apps        
 ┃ ┃ ┗ 📜 node-app-dev.yaml
 ┃ ┗ 📂 helm-chart
 ┃    📂 templates        
 ┃   ┃ ┣ 📜 deployment.yaml
 ┃   ┃ ┣ 📜 service.yaml
 ┃   ┃ ┗ 📜 ingress.yaml
 ┃   ┣ 📜 Chart.yaml
 ┃   ┣ 📜 values-dev.yaml   # Environment specific values
 ┃   ┣ 📜 values-staging.yaml
 ┃   ┗ 📜 values-prod.yaml
 ┣ 📂 scripts              
 ┃ ┣ 📂 bash
 ┃ ┃ ┣ 📜 install.sh
 ┃ ┃ ┗ 📜 uninstall.sh
 ┃ ┗ 📂 powershell
 ┃   ┣ 📜 install.ps1      # Automated setup script (Docker + K3s + Vault Auto-Seed)
 ┃   ┗ 📜 uninstall.ps1        
 ┣ 📂 src                  
 ┃ ┣ 📜 index.js, package.json
 ┃ ┣ 📜 index.test.js      # Jest unit test
 ┃ ┗ 📜 Dockerfile         
 ┣ 📜 docker-compose.yml   
 ┗ 📜 Dockerfile.jenkins
```

---

## ⚙️ Environment Variables (.env Setup)

Before running the local infrastructure installation, create a `.env` file in the root directory (`npm/.env`):

```env
# --- Database ---
POSTGRES_PASSWORD=pg-local

# --- PGAdmin ---
PGADMIN_EMAIL=dedimk.devops@gmail.com
PGADMIN_PASSWORD=pgadmin-local

# --- MinIO ---
MINIO_ROOT_USER=admin
MINIO_ROOT_PASSWORD=minioadmin

# --- Artemis ---
ARTEMIS_USER=admin
ARTEMIS_PASSWORD=artemisadmin

# --- Docker Hub & GitHub Credentials ---
DOCKER_USER=ku12nia
DOCKER_PASS=[YOUR PAT DOCKER]

# --- Jenkins & ArgoCD Access ---
JENKINS_PASSWORD=jenkins
ARGOCD_PASSWORD=P4ssw0rdArgoCD

# --- Jenkins Workspace ---
WORKSPACE_NAME=npm-cicd
WORKSPACE_DIR=/var/jenkins_home/workspace/npm-cicd

# Absolute path to project folder on Host Windows/Linux
LOCAL_PROJECT_PATH=C:/Users/evoel/Downloads/labs_dedi/npm

# --- Nexus Artifactory ---
NEXUS_PASSWORD=P4ssw0rdNexus
```

---

## 🛠 Git Version Control Guide

Set up local Git credentials before making commits:

```bash
git config --global user.name "Dedi Mohammad Kurnia"
git config --global user.email "dedimk.devops@gmail.com"
```

Standard Commit & Push Workflow:
```bash
git status
git add .
git commit -m "feat(ci): refactor pipeline for multi-environment image promotion"
git push origin dev
```

🚨 Handling Accidental Credentials Exposure:
If GitHub Push Protection blocks your commit:
```bash
git reset --soft origin/main
git add .
git commit -m "fix(security): sanitize exposed secrets"
git push
```

---

## 🚀 Step-by-Step Installation

Ensure Kubernetes is enabled in **Docker Desktop** before running installation scripts.

### Option A: Linux / macOS / Git Bash Users
```bash
cd scripts/bash
chmod +x install.sh && ./install.sh
```

### Option B: Windows (PowerShell) Users
```powershell
cd scripts\powershell
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
.\install.ps1
```

---

## 🌐 Accessing Services & Auto-Seeded Credentials

Upon successful execution of `install.ps1`, all service credentials are automatically injected into **HashiCorp Vault KV v2** (`secret/`):

- **Jenkins:** `http://localhost:8080` (User: `jenkins`, Pass: `jenkins`)
  - Configured Credentials Store: `dockerhub-creds`, `github-creds`, `argocd-creds`.
- **Nexus 3:** `http://localhost:8082` (User: `admin`, Pass: `P4ssw0rdNexus` / value in `.env`)
- **ArgoCD Dashboard:** `https://localhost` (User: `admin`, Pass: `P4ssw0rdArgoCD`)
- **HashiCorp Vault:** `http://localhost:8200` 
  - **Root Token:** Saved automatically in `vault-keys.json` in root workspace and printed in terminal logs upon setup completion.
- **Grafana:** `http://localhost:8083` (User: `admin`, Password extracted dynamically from K8s secret)
- **Prometheus:** `http://localhost:9090`
- **ActiveMQ Artemis:** `http://localhost:8161` (User: `admin`, Pass: `artemisadmin`)
- **pgAdmin:** `http://localhost:8081` (User: `dedimk.devops@gmail.com`, Pass: `pgadmin-local`)
- **PostgreSQL:** `localhost:5432` (User: `postgres`, Pass: `pg-local`)
- **MinIO:** `http://localhost:9001` (User: `admin`, Pass: `minioadmin`)

---

## 🔐 Automated Vault Secrets Structure

The automated setup populates Vault KV Engine (`secret/`) with the following schema:

```text
secret/
 ┣ 📂 database/postgres  -> { username, password }
 ┣ 📂 pgadmin           -> { admin_email, admin_password }
 ┣ 📂 minio             -> { root_user, root_password }
 ┣ 📂 artemis           -> { admin_user, admin_password }
 ┣ 📂 nexus             -> { admin_user, admin_password }
 ┣ 📂 argocd            -> { admin_user, admin_password }
 ┣ 📂 grafana           -> { admin_user, admin_password }
 ┣ 📂 jenkins/
 ┃ ┣ 📜 admin           -> { admin_user, admin_password }
 ┃ ┣ 📜 github          -> { username, token }
 ┃ ┗ 📜 dockerhub       -> { username, password }
```

---

## 🛠 Troubleshooting & Operations Guide

### 1. Automated Vault Re-initialization & Unseal
If Vault pods restart or the environment is re-deployed, `install.ps1` automatically reads `vault-keys.json`, executes the unseal operation, and verifies the KV v2 engine state.
* **Force Reset Vault:** To wipe and re-create Vault cleanly:
  ```powershell
  helm uninstall vault -n vault --no-hooks --ignore-not-found
  kubectl delete namespace vault --force --grace-period=0
  Remove-Item "vault-keys.json" -ErrorAction SilentlyContinue
  ```

---

### 2. Offline Mitigation & Local Artifactory (Nexus)
To prevent network timeouts (e.g., connection refused or HTTP 000 errors) during Jenkins image builds:
* The PowerShell installation script leverages the Nexus REST API to automatically create a `raw-binaries` repository near the end of environment initialization (Step 8). 
* Local binary files (`argocd-linux-amd64`, `kubectl`, `buildx`, `docker.tgz`) stored in `$env:LOCAL_PROJECT_PATH\bin` are uploaded automatically using `curl.exe` with `--fail` validation.

---

### 3. CI/CD Strategy: Image Promotion & Multi-Environment
To maintain production stability, the pipeline follows the **Build Once, Deploy Anywhere** pattern:
* **Dev Environment (`dev`):** Jenkins checks out source code, runs unit tests, builds the Docker image (e.g. `01-dev`), pushes to Docker Hub, and updates `values-dev.yaml`.
* **Staging / Production (`staging` / `prod`):** **No rebuilds allowed.** Pipeline accepts `IMAGE_TAG_TO_PROMOTE` (e.g. `01-dev`), pulls the stable image, re-tags it (e.g. `01-staging` or `01-prod`), and updates `values-staging.yaml` / `values-prod.yaml`.
* **Production Gate:** Pipeline enforces a manual **Approval Gate** (`input` step) before deploying to Production.
* **NodePort Allocation:** To prevent port collision, ports are segmented in values files:
  - Dev: `nodePort: 30001`
  - Staging: `nodePort: 30002`
  - Production: `nodePort: 30000`

---

### 4. Resolving ArgoCD OutOfSync & Kubernetes Deployment Errors

#### A. Error: `spec.selector: field is immutable`
* **Fix (Pipeline-level):** Pass `--replace` or `--sync-option Replace=true` during ArgoCD CLI sync execution:
  ```bash
  argocd app sync node-app-dev --replace
  ```

#### B. Error: `namespaces "dev-apps" not found`
* **Fix:** Enforce automated namespace creation during ArgoCD application registration:
  ```bash
  argocd app create node-app-dev \
    --sync-option CreateNamespace=true \
    --upsert
  ```

---

### 5. Resolving Jenkins Test & Build Counter Issues

#### A. Resetting Jenkins Build Number Counter
If build numbers get out of sync or you need to reset back to `#01-dev`:
1. Open **Jenkins -> Manage Jenkins -> Script Console**.
2. Run script to clear build history and reset counter:
   ```groovy
   def job = Jenkins.instance.getItem("npm-cicd")
   job.builds.each { it.delete() }
   job.nextBuildNumber = 1
   job.saveNextBuildNumber()
   println "Build history cleared. Next build will start at #1"
   ```

---

### 6. Docker & System Maintenance
```bash
# Clean unused containers, networks, and images
docker system prune -a --volumes

# Reset WSL2 Networking (If Docker Desktop on Windows experiences SSL/Network Timeout)
wsl --shutdown
```

---

## 🗑️ Uninstall & Cleanup

To teardown Kubernetes deployments and Docker containers:

* **Linux / macOS:** `cd scripts/bash && ./uninstall.sh`
* **Windows (PowerShell):** `cd scripts\powershell && .\uninstall.ps1`

---

## 👨‍💻 Connect & Contribute

[![LinkedIn Profile](https://img.shields.io/badge/LinkedIn-Dedi_Mohammad_Kurnia-0A66C2?style=for-the-badge&logo=linkedin)](https://www.linkedin.com/in/dedimohammadkurnia/)
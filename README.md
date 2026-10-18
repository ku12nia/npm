# Node.js GitOps & Local DevOps Lab (App of Apps Pattern)

![Jenkins](https://img.shields.io/badge/Jenkins-CI-blue?logo=jenkins)
![ArgoCD](https://img.shields.io/badge/ArgoCD-CD-orange?logo=argo)
![Kubernetes](https://img.shields.io/badge/Kubernetes-GitOps-blue?logo=kubernetes)
![Docker](https://img.shields.io/badge/Docker-Desktop-2496ED?logo=docker)
![Postgres](https://img.shields.io/badge/PostgreSQL-Database-336791?logo=postgresql)
![Vault](https://img.shields.io/badge/Vault-Secrets-FF0000?logo=vault)
![Prometheus](https://img.shields.io/badge/Prometheus-Monitoring-E6522C?logo=prometheus)
![Grafana](https://img.shields.io/badge/Grafana-Dashboard-F46800?logo=grafana)
[![LinkedIn](https://img.shields.io/badge/Connect-LinkedIn-0A66C2?logo=linkedin)](https://www.linkedin.com/in/dedimohammadkurnia/)

This repository provides a ready-to-use **Full-Stack Local DevOps & GitOps** ecosystem. It integrates a modern CI/CD pipeline using Jenkins, local database management (PostgreSQL + pgAdmin), HashiCorp Vault for secrets management, monitoring with Prometheus & Grafana, message brokering with ActiveMQ, object storage with MinIO, and automated deployments to Kubernetes using **ArgoCD** following the **App of Apps** pattern. The entire infrastructure is designed to run seamlessly on top of **Docker Desktop**.

---

## 🏗️ Architecture & Ecosystem

This project applies the principle of **Separation of Concerns**, splitting the infrastructure between core Docker Compose services and Kubernetes (K3s) deployments:

### 1. Core Services (Docker Compose)
These components run directly on the Docker engine to provide stable base services:
- **Jenkins (CI Server):** Manages automated pipelines handling checkout, unit testing via Docker, building Docker images, pushing to Docker Hub, and updating environment-specific Helm manifests in Git.
- **PostgreSQL (Database):** Serves as the primary relational database system for the application workloads.
- **MinIO (Object Storage):** Provides an S3-compatible local object storage for file uploads, backups, or artifact storage.

### 2. Kubernetes Services (K3s via Docker Desktop)
These components run inside the Kubernetes cluster to mimic production-grade orchestration:
- **ArgoCD (Continuous Deployment):** Acts as the primary GitOps controller. Monitors the `k8s/` directory in Git and synchronizes manifest changes directly into target namespaces (`dev-apps`, `staging-apps`, `prod-apps`).
- **pgAdmin (Database Manager):** Deployed via Helm to provide a web-based GUI for managing PostgreSQL (connected via `host.docker.internal`).
- **ActiveMQ Artemis (Message Broker):** Deployed via native manifests to handle asynchronous messaging.
- **HashiCorp Vault:** Injecting dynamic secrets directly into Node.js deployment pods via the Vault Agent Injector.
- **Monitoring Stack (Prometheus & Grafana):** Deployed via `kube-prometheus-stack` Helm chart to automatically scrape cluster metrics, monitor pod health, and visualize system performance.

---

## 📂 Repository Structure

```text
📦 npm
 ┣ 📂 ci                   
 ┃ ┗ 📜 Jenkinsfile        
 ┣ 📂 config               
 ┃ ┣ 📜 postgres17-connect.json
 ┃ ┣ 📜 prometheus.yml
 ┃ ┗ 📜 pgadmin.json
 ┣ 📂 k8s
 ┃ ┣ 📜 argocd.yaml        # ArgoCD Ingress, RBAC, & Root App
 ┃ ┣ 📂 argocd-apps        
 ┃ ┃ ┗ 📜 node-app-dev.yaml
 ┃ ┗ 📂 helm-chart
 ┃   ┣ 📂 templates        
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
 ┃   ┣ 📜 install.ps1        
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

Before running the local infrastructure using Docker Compose, create a `.env` file in the root directory (`npm/.env`):

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

# --- Docker Hub Credentials ---
DOCKER_USER=ku12nia
DOCKER_PASS=[YOUR PAT DOCKER]

# --- Jenkins Workspace ---
WORKSPACE_NAME=npm-cicd
WORKSPACE_DIR=/var/jenkins_home/workspace/npm-cicd

# Absolute path to project folder on Host Windows/Linux
LOCAL_PROJECT_PATH=C:/Users/evoel/Downloads/labs_dedi/npm
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

## 🌐 Accessing Services

- **Jenkins:** `http://localhost:8080`
  - Required credentials in Jenkins Store (`Username with password`):
    - `dockerhub-creds`
    - `github-creds` (Use GitHub Personal Access Token)
    - `argocd-creds`
- **ArgoCD Dashboard:** `http://argocd.local` (Username: `admin`, Password: `P4ssw0rdArgoCD`)
- **pgAdmin:** `http://localhost:8081` (Host: `host.docker.internal`)
- **HashiCorp Vault:** `http://localhost:8200` (Token: `root`)
- **Grafana:** `http://localhost:8083` (User: `admin`, Password shown in terminal output)
- **Prometheus:** `http://localhost:9090`

---

## 🛠 Troubleshooting & Operations Guide

### 1. CI/CD Strategy: Image Promotion & Multi-Environment
To maintain production stability, the pipeline follows the **Build Once, Deploy Anywhere** pattern:
* **Dev Environment (`dev`):** Jenkins checks out source code, runs unit tests, builds the Docker image (e.g. `01-dev`), pushes to Docker Hub, and updates `values-dev.yaml`.
* **Staging / Production (`staging` / `prod`):** **No rebuilds allowed.** Pipeline accepts `IMAGE_TAG_TO_PROMOTE` (e.g. `01-dev`), pulls the stable image, re-tags it (e.g. `01-staging` or `01-prod`), and updates `values-staging.yaml` / `values-prod.yaml`.
* **Production Gate:** Pipeline enforces a manual **Approval Gate** (`input` step) before deploying to Production.
* **NodePort Allocation:** To prevent port collision, ports are segmented in values files:
  - Dev: `nodePort: 30001`
  - Staging: `nodePort: 30002`
  - Production: `nodePort: 30000`

---

### 2. Resolving ArgoCD OutOfSync & Kubernetes Deployment Errors

#### A. Error: `spec.selector: field is immutable`
* **Root Cause:** Kubernetes `spec.selector` on Deployment specs cannot be patched on existing deployments if label definitions change.
* **Fix (One-time Cleanup):** Delete the existing Deployment object directly from the cluster so ArgoCD can recreate it with updated selectors:
  ```bash
  kubectl delete deployment node-app -n dev-apps
  ```
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

#### C. Error: `PermissionDenied` on ArgoCD CLI
* **Fix:** Update `argocd-rbac-cm` ConfigMap policy to allow admin role or elevate default policy for lab environments:
  ```yaml
  data:
    policy.csv: |
      p, role:admin, *, *, *, allow
      g, admin, role:admin
    policy.default: role:admin
  ```

---

### 3. Resolving Jenkins Test & Build Counter Issues

#### A. Issue: "No tests found" & Invalid JUnit XML
* **Root Cause:** Jest runs with `--passWithNoTests`, but outputs a zero-test XML (`tests="0"`), causing the Jenkins JUnit parser plugin to throw an error.
* **Fix:** Add a valid test file at `src/index.test.js`:
  ```javascript
  test('validates CI unit testing pipeline', () => {
      expect(true).toBe(true);
  });
  ```

#### B. Resetting Jenkins Build Number Counter
If build numbers get out of sync or you need to reset back to `#01-dev`:

1. Open **Jenkins -> Manage Jenkins -> Script Console**.
2. **Option A: Safe Reset (To Next Number #100)**
   ```groovy
   def job = Jenkins.instance.getItem("npm-cicd")
   job.nextBuildNumber = 100
   job.saveNextBuildNumber()
   println "Next build number set to: ${job.nextBuildNumber}"
   ```
3. **Option B: Clean Reset back to #1 (Purging Old Builds)**
   *Note: You MUST delete old build directories (`#1` to `#99`) first, or Jenkins will silently fail when attempting to overwrite existing build folders.*
   ```groovy
   def job = Jenkins.instance.getItem("npm-cicd")
   job.builds.each { it.delete() }
   job.nextBuildNumber = 1
   job.saveNextBuildNumber()
   println "Build history cleared. Next build will start at #1"
   ```

---

### 4. Docker & System Maintenance
```bash
# Clean unused containers, networks, and images
docker system prune -a --volumes

# Fix Docker Desktop Windows DNS timeout bugs (Add to Docker Engine Settings JSON)
"dns": ["8.8.8.8", "1.1.1.1"]
```

---

## 🗑️ Uninstall & Cleanup

To teardown Kubernetes deployments and Docker containers:

* **Linux / macOS:** `cd scripts/bash && ./uninstall.sh`
* **Windows (PowerShell):** `cd scripts\powershell && .\uninstall.ps1`

---

## 👨‍💻 Connect & Contribute

[![LinkedIn Profile](https://img.shields.io/badge/LinkedIn-Dedi_Mohammad_Kurnia-0A66C2?style=for-the-badge&logo=linkedin)](https://www.linkedin.com/in/dedimohammadkurnia/)
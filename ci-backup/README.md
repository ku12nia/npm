![Jenkins](https://img.shields.io/badge/Jenkins-CI-blue?logo=jenkins)
![ArgoCD](https://img.shields.io/badge/ArgoCD-CD-orange?logo=argo)
![Kubernetes](https://img.shields.io/badge/Kubernetes-GitOps-blue?logo=kubernetes)
![Docker](https://img.shields.io/badge/Docker-Desktop-2496ED?logo=docker)
![Vagrant](https://img.shields.io/badge/Vagrant-Virtualization-1563FF?logo=vagrant)
![Nexus](https://img.shields.io/badge/Nexus-Repository-1B1C1D?logo=sonatype)
![Postgres](https://img.shields.io/badge/PostgreSQL-Database-336791?logo=postgresql)
![Vault](https://img.shields.io/badge/Vault-Secrets-FF0000?logo=vault)
![Prometheus](https://img.shields.io/badge/Prometheus-Monitoring-E6522C?logo=prometheus)
![Grafana](https://img.shields.io/badge/Grafana-Dashboard-F46800?logo=grafana)
[![LinkedIn](https://img.shields.io/badge/Connect-LinkedIn-0A66C2?logo=linkedin)](https://www.linkedin.com/in/dedimohammadkurnia/)

This repository provides a ready-to-use **Full-Stack Local DevOps & GitOps** ecosystem. It integrates a modern CI/CD pipeline using Jenkins, local database management (PostgreSQL + pgAdmin), HashiCorp Vault for automated secrets management, monitoring with Prometheus & Grafana, message brokering with ActiveMQ, object storage with MinIO, a local artifactory via **Sonatype Nexus 3**, and automated deployments to Kubernetes using **ArgoCD** following the **App of Apps** pattern. 

The infrastructure is highly flexible and can be run either completely isolated inside an **Ubuntu Linux Virtual Machine (via Vagrant)** or natively on **Host Docker Desktop (Windows/macOS)**.

---

## 🏗️ Architecture & Ecosystem

This project applies the principle of **Separation of Concerns**, splitting the infrastructure between core Docker Compose services and Kubernetes (K3s) deployments:

### 1. Core Services (Docker Compose)
These components run directly on the Docker engine to provide stable base services:
- **Jenkins (CI Server):** Manages automated pipelines handling checkout, unit testing via Docker, building Docker images, pushing to Docker Hub, and updating environment-specific Helm manifests in Git.
  * *Hybrid Build Approach:* Uses a dual-Dockerfile setup (`Dockerfile.win` for the Windows Host workflow and `Dockerfile.jenkins.vagrant` for the Linux VM workflow) to resolve OS-specific DNS (`host.docker.internal`) and offline binary dependencies flawlessly.
- **Sonatype Nexus 3 (Artifactory):** Serves as a local repository manager (`raw-binaries`) hosting static binary files (such as `kubectl`, `argocd`, `buildx`, and `docker.tgz`). Uploads are automatically executed near the end of initialization to prevent boot timeouts.
- **PostgreSQL (Database):** Serves as the primary relational database system for application workloads.
- **MinIO (Object Storage):** Provides S3-compatible local object storage for file uploads, backups, and artifact storage.

### 2. Kubernetes Services (K3s)
These components run inside the Kubernetes cluster to mimic production-grade orchestration:
- **ArgoCD (Continuous Deployment):** Acts as the primary GitOps controller. Monitors the `k8s/` directory in Git and synchronizes manifest changes directly into target namespaces (`dev-apps`, `staging-apps`, `prod-apps`).
- **HashiCorp Vault:** Deployed via Helm with persistent storage (1Gi PVC). Automatically initialized, unsealed, and pre-populated (*auto-seeded*) with all service credentials and pipeline secrets under the `secret/` KV v2 engine.
- **pgAdmin (Database Manager):** Deployed via Helm to provide a web-based GUI for managing PostgreSQL.
- **ActiveMQ Artemis (Message Broker):** Deployed via Helm (`artemis` namespace) to handle asynchronous messaging.
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
 ┃    ┣ 📂 templates        
 ┃    ┣ 📜 Chart.yaml
 ┃    ┣ 📜 values-dev.yaml   # Environment specific values
 ┃    ┣ 📜 values-staging.yaml
 ┃    ┗ 📜 values-prod.yaml
 ┣ 📂 scripts              
 ┃ ┣ 📂 bash
 ┃ ┃ ┣ 📜 install.sh       # Automated K3s, Docker, & Vault setup script (Linux/Vagrant)
 ┃ ┃ ┣ 📜 teardown.sh      # Environment cleanup script
 ┃ ┃ ┗ 📜 Vagrantfile      # VM Configuration & Port Forwarding
 ┃ ┗ 📂 powershell
 ┃   ┣ 📜 install.ps1      # Automated setup script (Windows Docker Desktop)
 ┃   ┗ 📜 uninstall.ps1        
 ┣ 📂 src                  
 ┃ ┣ 📜 index.js, package.json
 ┃ ┣ 📜 index.test.js      # Jest unit test
 ┃ ┗ 📜 Dockerfile         
 ┣ 📜 docker-compose.yml   
 ┣ 📜 .env                 # MUST be created before running installation scripts
 ┣ 📜 Dockerfile.win       # Jenkins Dockerfile for Windows Host workflow
 ┗ 📜 Dockerfile.linux     # Jenkins Dockerfile for Linux Host workflow
```

---

## ⚙️ Environment Variables (.env Setup)

Before running the local infrastructure installation, create a `.env` file in the root directory (`npm/.env`):

```env
# --- Artemis ---
ARTEMIS_USER=admin
ARTEMIS_PASSWORD=artemisadmin

# --- ArgoCD ---
ARGOCD_USER=admin
ARGOCD_PASSWORD=P4ssw0rdArgoCD

# --- Database ---
POSTGRES_PASSWORD=pg-local

# --- PGAdmin ---
PGADMIN_EMAIL=dedimk.devops@gmail.com
PGADMIN_PASSWORD=pgadmin-local

# --- Docker Hub & GitHub Credentials ---
DOCKER_USER=ku12nia
DOCKER_PASS=[YOUR PAT DOCKER]

# --- MinIO ---
MINIO_ROOT_USER=admin
MINIO_ROOT_PASSWORD=minioadmin

# --- Nexus Artifactory ---
NEXUS_USERNAME=admin
NEXUS_PASSWORD=P4ssw0rdNexus

# --- Jenkins Access & Workspace ---
JENKINS_PASSWORD=jenkins
WORKSPACE_NAME=npm-cicd
WORKSPACE_DIR=/var/jenkins_home/workspace/npm-cicd

# Absolute path to project folder on Host Windows/Linux
# (Required for PowerShell workflow; Ignored by Vagrant workflow)
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

🚨 **Handling Accidental Credentials Exposure:**
If GitHub Push Protection blocks your commit:
```bash
git reset --soft origin/main
git add .
git commit -m "fix(security): sanitize exposed secrets"
git push
```

---

## 🚀 Step-by-Step Installation

You can run this ecosystem using either the **Vagrant Workflow** (fully isolated Linux VM) or the **Host OS Workflow** (requires Docker Desktop with Kubernetes enabled).

### Option A: The Vagrant Workflow (Recommended)
Ensure you have installed **VirtualBox** and **HashiCorp Vagrant**.

1. Open your terminal (PowerShell, CMD, or Git Bash) and navigate to the `scripts/bash` directory:
   ```bash
   cd scripts/bash
   ```

2. **Vagrant Management & Lifecycle Commands:**
   - `vagrant up`: Boots the VM, configures port forwarding, and mounts synced folders.
   - `vagrant up --debug`: Boots the VM with verbose debug logging (useful for troubleshooting SSH or boot timeouts).
   - `vagrant halt`: Gracefully shuts down the virtual machine.
   - `vagrant resume`: Resumes a suspended virtual machine.
   - `vagrant reload`: Restarts the VM and re-applies any changes made to `Vagrantfile`.

3. **Access VM via SSH:**
   ```bash
   vagrant ssh
   ```
   *(Note: Default credentials if logging in directly via VirtualBox GUI are **Username:** `vagrant`, **Password:** `vagrant`)*

4. **Execute Provisioning Script Inside VM:**
   Once inside the VM, switch to root user, navigate to the synced script directory, fix Windows line endings (CRLF to LF), and execute the installer:
   ```bash
   sudo su
   cd /workspace/scripts/bash
   sed -i -e 's/\r$//' install.sh
   ./install.sh
   ```

### Option B: Windows Host (PowerShell + Docker Desktop)
Ensure **Kubernetes** is enabled in your Docker Desktop settings.
1. Open PowerShell as Administrator.
2. Navigate to the PowerShell scripts folder:
   ```powershell
   cd scripts\powershell
   Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
   .\install.ps1
   ```

---

## 🌐 Accessing Services & Auto-Seeded Credentials

Regardless of the installation method (Vagrant or Host Docker), services are mapped to your `localhost`. Upon successful execution, credentials are automatically injected into **HashiCorp Vault KV v2** (`secret/`):

- **Jenkins:** `http://localhost:8080` (User: `jenkins`, Pass: `jenkins`)
  - Configured Credentials Store: `dockerhub-creds`, `github-creds`, `argocd-creds`.
- **Nexus 3:** `http://localhost:8082` (User: `admin`, Pass: `P4ssw0rdNexus`)
- **ArgoCD Dashboard:** `https://localhost` (User: `admin`, Pass: `P4ssw0rdArgoCD`)
- **HashiCorp Vault:** `http://localhost:8200` 
  - **Root Token:** Saved automatically in `vault-keys.json` in the root workspace and printed in terminal logs.
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
If Vault pods restart, the installation scripts automatically read `vault-keys.json` to execute the unseal operation.
* **Force Reset Vault:** To wipe and re-create Vault cleanly:
  ```bash
  helm uninstall vault -n vault --no-hooks --ignore-not-found
  kubectl delete namespace vault --force --grace-period=0
  rm vault-keys.json
  ```

### 2. Offline Mitigation & Local Artifactory (Nexus)
To prevent network timeouts (e.g., connection refused or HTTP 000 errors) during Jenkins image builds:
* The installation scripts leverage the Nexus REST API to automatically create a `raw-binaries` repository near the end of environment initialization. 
* Local binary files (e.g., `kubectl`, `docker.tgz`) stored in the `bin/` folder are uploaded automatically.

### 3. CI/CD Strategy: Image Promotion & Multi-Environment
To maintain production stability, the pipeline follows the **Build Once, Deploy Anywhere** pattern:
* **Dev Environment (`dev`):** Jenkins checks out source code, runs unit tests, builds the Docker image (e.g. `01-dev`), pushes to Docker Hub, and updates `values-dev.yaml`.
* **Staging / Production (`staging` / `prod`):** **No rebuilds allowed.** Pipeline accepts `IMAGE_TAG_TO_PROMOTE` (e.g. `01-dev`), pulls the stable image, re-tags it (e.g. `01-staging` or `01-prod`), and updates `values-staging.yaml` / `values-prod.yaml`.
* **Production Gate:** Pipeline enforces a manual **Approval Gate** before deploying to Production.
* **NodePort Allocation:** To prevent port collision, ports are segmented in values files:
  - Dev: `nodePort: 30001`
  - Staging: `nodePort: 30002`
  - Production: `nodePort: 30000`

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

### 5. Resolving Jenkins Test & Build Counter Issues
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

### 6. Docker & System Maintenance
```bash
# Clean unused containers, networks, and images
docker system prune -a --volumes

# Reset WSL2 Networking (For Windows Docker Desktop users experiencing SSL Timeout)
wsl --shutdown
```

---

## 🗑️ Uninstall & Cleanup

Depending on your installation method, you can clean up the environment as follows:

### For Vagrant Users:
To safely stop and destroy the environment, run the following commands from the `scripts/bash` directory on your host:
```bash
# To pause the VM without destroying data:
vagrant halt

# To completely wipe the VM and all its data:
vagrant destroy -f
```
Alternatively, to clean up Kubernetes resources while keeping the VM running, SSH into Vagrant and run the teardown script:
```bash
vagrant ssh
sudo bash /workspace/scripts/bash/teardown.sh
```

### For Windows PowerShell Users:
To teardown Kubernetes deployments and Docker containers from the host OS:
```powershell
cd scripts\powershell
.\uninstall.ps1
```

---

## 👨‍💻 Connect & Contribute

[![LinkedIn Profile](https://img.shields.io/badge/LinkedIn-Dedi_Mohammad_Kurnia-0A66C2?style=for-the-badge&logo=linkedin)](https://www.linkedin.com/in/dedimohammadkurnia/)
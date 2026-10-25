![Jenkins](https://img.shields.io/badge/Jenkins-CI-blue?logo=jenkins)
![ArgoCD](https://img.shields.io/badge/ArgoCD-CD-orange?logo=argo)
![Kubernetes](https://img.shields.io/badge/Kubernetes-GitOps-blue?logo=kubernetes)
![Vagrant](https://img.shields.io/badge/Vagrant-Virtualization-1563FF?logo=vagrant)
![Nexus](https://img.shields.io/badge/Nexus-Repository-1B1C1D?logo=sonatype)
![Postgres](https://img.shields.io/badge/PostgreSQL-Database-336791?logo=postgresql)
![Vault](https://img.shields.io/badge/Vault-Secrets-FF0000?logo=vault)
![Prometheus](https://img.shields.io/badge/Prometheus-Monitoring-E6522C?logo=prometheus)
![Grafana](https://img.shields.io/badge/Grafana-Dashboard-F46800?logo=grafana)
[![LinkedIn](https://img.shields.io/badge/Connect-LinkedIn-0A66C2?logo=linkedin)](https://www.linkedin.com/in/dedimohammadkurnia/)

This repository provides a ready-to-use **Full-Stack Local DevOps & GitOps** ecosystem. It integrates a modern CI/CD pipeline using Jenkins, local database management (PostgreSQL + pgAdmin), HashiCorp Vault for automated secrets management, monitoring with Prometheus & Grafana, message brokering with ActiveMQ, object storage with MinIO, a local artifactory via **Sonatype Nexus 3**, and automated deployments to Kubernetes using **ArgoCD** following the **App of Apps** pattern. 

The entire infrastructure is designed to run seamlessly in an isolated **Ubuntu Linux Virtual Machine** managed by **Vagrant** and VirtualBox, ensuring a consistent environment across any host OS.

---

## 🏗️ Architecture & Ecosystem

This project applies the principle of **Separation of Concerns**, splitting the infrastructure between core Docker Compose services and native Kubernetes (K3s) deployments, all housed within a single Vagrant VM:

### 1. Core Services (Docker Compose inside VM)
These components run directly on the Docker engine inside the Ubuntu VM to provide stable base services:
- **Jenkins (CI Server):** Manages automated pipelines handling checkout, unit testing via Docker, building Docker images, pushing to Docker Hub, and updating environment-specific Helm manifests in Git.
- **Sonatype Nexus 3 (Artifactory):** Serves as a local repository manager (`raw-binaries`) hosting static binary files. Uploads are automatically executed near the end of initialization.
- **PostgreSQL (Database):** Serves as the primary relational database system for application workloads.
- **MinIO (Object Storage):** Provides S3-compatible local object storage for file uploads, backups, and artifact storage.

### 2. Kubernetes Services (K3s running natively in VM)
These components run inside the lightweight K3s Kubernetes cluster to mimic production-grade orchestration:
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
 ┣ 📂 k8s
 ┃ ┣ 📜 argocd.yaml        # ArgoCD Ingress, RBAC, & Root App
 ┃ ┣ 📂 argocd-apps        
 ┃ ┗ 📂 helm-chart
 ┃    ┣ 📂 templates        
 ┃    ┣ 📜 Chart.yaml
 ┃    ┣ 📜 values-dev.yaml   # Environment specific values
 ┃    ┣ 📜 values-staging.yaml
 ┃    ┗ 📜 values-prod.yaml
 ┣ 📂 scripts              
 ┃ ┣ 📂 bash
 ┃ ┃ ┣ 📜 install.sh       # Automated K3s, Docker, & Vault setup script
 ┃ ┃ ┣ 📜 teardown.sh      # Environment cleanup script
 ┃ ┃ ┗ 📜 Vagrantfile      # VM Configuration & Port Forwarding
 ┃ ┗ 📂 powershell
 ┃   ┣ 📜 install.ps1      # (Legacy/Alternative) Docker Desktop setup
 ┃   ┗ 📜 uninstall.ps1        
 ┣ 📂 src                  
 ┃ ┣ 📜 index.js, package.json
 ┃ ┣ 📜 index.test.js      
 ┃ ┗ 📜 Dockerfile         
 ┣ 📜 docker-compose.yml   
 ┣ 📜 .env                 # MUST be created before running Vagrant
 ┗ 📜 README.md
```

---

## ⚙️ Environment Variables (.env Setup)

Before spinning up the Vagrant environment, create a `.env` file in the root directory (`npm/.env`):

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
```
*(Note: `LOCAL_PROJECT_PATH` is no longer strictly required for Vagrant, as Vagrant automatically mounts the root directory into the VM).*

---

## 🚀 Step-by-Step Installation (Vagrant Workflow)

### Prerequisites:
Ensure you have installed **VirtualBox** and **HashiCorp Vagrant** on your host machine.

1. Open your terminal (PowerShell, CMD, or Git Bash).
2. Navigate to the directory containing the `Vagrantfile`.
   ```bash
   cd scripts/bash
   ```
3. Boot the environment. Vagrant will automatically download Ubuntu, configure networking, install Docker & K3s, and run the `install.sh` provisioning script.
   ```bash
   vagrant up
   ```
   *(Note: The first run will take several minutes as it downloads the OS image and Docker containers).*

---

## 🌐 Accessing Services & Auto-Seeded Credentials

Thanks to Vagrant's port forwarding, you can access all services directly from your host machine's `localhost`. Upon successful execution, credentials are automatically injected into **HashiCorp Vault KV v2** (`secret/`):

- **Jenkins:** `http://localhost:8080` (User: `jenkins`, Pass: `jenkins`)
- **Nexus 3:** `http://localhost:8082` (User: `admin`, Pass: `P4ssw0rdNexus`)
- **ArgoCD Dashboard:** `https://localhost` (User: `admin`, Pass: `P4ssw0rdArgoCD`)
- **HashiCorp Vault:** `http://localhost:8200` 
  - **Root Token:** Saved automatically in `vault-keys.json` in the root workspace.
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

## 🛠 CI/CD Strategy: Image Promotion & Multi-Environment

To maintain production stability, the pipeline follows the **Build Once, Deploy Anywhere** pattern:
* **Dev Environment (`dev`):** Jenkins checks out source code, runs unit tests, builds the Docker image (e.g. `01-dev`), pushes to Docker Hub, and updates `values-dev.yaml`.
* **Staging / Production (`staging` / `prod`):** **No rebuilds allowed.** Pipeline accepts `IMAGE_TAG_TO_PROMOTE` (e.g. `01-dev`), pulls the stable image, re-tags it (e.g. `01-staging` or `01-prod`), and updates `values-staging.yaml` / `values-prod.yaml`.
* **Production Gate:** Pipeline enforces a manual **Approval Gate** before deploying to Production.

---

## 🗑️ Uninstall & Cleanup

To safely stop and destroy the environment, run the following command from the `scripts/bash` directory on your host:

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

---

## 👨‍💻 Connect & Contribute

[![LinkedIn Profile](https://img.shields.io/badge/LinkedIn-Dedi_Mohammad_Kurnia-0A66C2?style=for-the-badge&logo=linkedin)](https://www.linkedin.com/in/dedimohammadkurnia/)
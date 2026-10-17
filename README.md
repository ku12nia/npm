# Node.js GitOps & Local DevOps Lab (App of Apps Pattern)

![Jenkins](https://img.shields.io/badge/Jenkins-CI-blue?logo=jenkins)
![ArgoCD](https://img.shields.io/badge/ArgoCD-CD-orange?logo=argo)
![Kubernetes](https://img.shields.io/badge/Kubernetes-GitOps-blue?logo=kubernetes)
![Docker](https://img.shields.io/badge/Docker-Desktop-2496ED?logo=docker)
![Postgres](https://img.shields.io/badge/PostgreSQL-Database-336791?logo=postgresql)
![Vault](https://img.shields.io/badge/Vault-Secrets-FF0000?logo=vault)
![Prometheus](https://img.shields.io/badge/Prometheus-Monitoring-E6522C?logo=prometheus)
![Grafana](https://img.shields.io/badge/Grafana-Dashboard-F46800?logo=grafana)
[![LinkedIn](https://img.shields.io/badge/Connect-LinkedIn-0A66C2?logo=linkedin)]([https://www.linkedin.com/in/dedimohammadkurnia/](https://www.linkedin.com/in/dedimohammadkurnia/))

This repository provides a ready-to-use **Full-Stack Local DevOps & GitOps** ecosystem. It integrates a modern CI/CD pipeline using Jenkins, local database management (PostgreSQL + pgAdmin), HashiCorp Vault for secrets management, monitoring with Prometheus & Grafana, message brokering with ActiveMQ, object storage with MinIO, and automated deployments to Kubernetes using **ArgoCD** following the **App of Apps** pattern. The entire infrastructure is designed to run seamlessly on top of **Docker Desktop**.

---

## 🏗️ Architecture & Ecosystem

This project applies the principle of **Separation of Concerns**, splitting the infrastructure between core Docker Compose services and Kubernetes (K3s) deployments:

### 1. Core Services (Docker Compose)
These components run directly on the Docker engine to provide stable base services:
- **Jenkins (CI Server):** Manages automated pipelines that handle source code checkout, testing, building Docker images via embedded Buildx, pushing to Docker Hub, and updating Kubernetes manifests in the Git repository.
- **PostgreSQL (Database):** Serves as the primary relational database system for the application workloads.
- **MinIO (Object Storage):** Provides an S3-compatible local object storage for file uploads, backups, or artifact storage.

### 2. Kubernetes Services (K3s via Docker Desktop)
These components run inside the Kubernetes cluster to mimic production-grade orchestration:
- **ArgoCD (Continuous Deployment):** Acts as the primary GitOps controller. Monitors the `k8s/` directory in Git and synchronizes manifest changes directly into the local Kubernetes cluster.
- **pgAdmin (Database Manager):** Deployed via Helm to provide a web-based GUI for managing the PostgreSQL database (connected via `host.docker.internal`).
- **ActiveMQ Artemis (Message Broker):** Deployed via native manifests to handle asynchronous messaging and queue management for microservices communication.
- **HashiCorp Vault:** Manages sensitive credentials and injects dynamic secrets directly into the Node.js deployment pods via the Vault Agent Injector.
- **Monitoring Stack (Prometheus & Grafana):** Deployed via `kube-prometheus-stack` Helm chart to automatically scrape cluster metrics, monitor pod health, and visualize system performance on customized dashboards.

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
 ┃ ┣ 📜 root-app.yaml      
 ┃ ┣ 📂 argocd-apps          
 ┃ ┃ ┗ 📜 node-app-prod.yaml
 ┃ ┗ 📂 node-app-chart
 ┃   ┣ 📂 templates          
 ┃   ┃ ┣ 📜 deployment.yaml
 ┃   ┃ ┣ 📜 service.yaml
 ┃   ┃ ┗ 📜 ingress.yaml
 ┃   ┣ 📜 Chart.yaml
 ┃   ┗ 📜 values.yaml
 ┣ 📂 scripts              
 ┃ ┣ 📂 bash
 ┃ ┃ ┣ 📜 install.sh
 ┃ ┃ ┗ 📜 uninstall.sh
 ┃ ┗ 📂 powershell
 ┃   ┣ 📜 install.ps1        
 ┃   ┗ 📜 uninstall.ps1        
 ┣ 📂 src                  
 ┃ ┣ 📜 index.js, package.json
 ┃ ┗ 📜 Dockerfile         
 ┣ 📜 docker-compose.yml   
 ┗ 📜 Dockerfile.jenkins
```

### Directory & File Definitions

*   **`ci/`**: Contains the `Jenkinsfile` which defines the Continuous Integration pipeline. It automates the build, test, containerization, and registry push processes, as well as updating the image tag in the Git repository.
*   **`config/`**: Holds static configuration files required for provisioning external services, including PostgreSQL connection setups, Prometheus scrape targets, and pgAdmin server configurations.
*   **`k8s/`**: The core directory for Kubernetes orchestration and GitOps management.
    *   **`root-app.yaml` & `argocd-apps/`**: Implements the ArgoCD App of Apps pattern to bootstrap and synchronize cluster resources automatically.
    *   **`node-app-chart/`**: A custom Helm Chart for deploying the Node.js application. The `templates/` directory contains Kubernetes manifests (Deployment, Service, Ingress) with integrated HashiCorp Vault Agent Injector annotations, while `values.yaml` acts as the central configuration for dynamic variables (e.g., image tags, ports).
*   **`scripts/`**: Provides automation scripts in Bash (Linux/macOS) and PowerShell (Windows) for seamless environment setup (`install`) and teardown (`uninstall`).
*   **`src/`**: The application source code directory, including the `Dockerfile` used by Jenkins to containerize the Node.js application.
*   **`docker-compose.yml`**: The foundation for the local infrastructure. It defines and orchestrates the core services running outside of Kubernetes, such as Jenkins, PostgreSQL, and MinIO.
*   **`Dockerfile.jenkins`**: A custom Docker image definition for Jenkins, pre-configured with essential DevOps CLI tools including Docker, Buildx, Kubectl, and ArgoCD CLI to enable seamless pipeline execution.

---

## ⚙️ Environment Variables (.env Setup)

Before running the local infrastructure using Docker Compose, you must create a `.env` file in the root directory (`npm/.env`) to configure your local credentials and database secrets.

Create a file named `.env` and add the following configuration:

```.env
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

# --- Hashicorp Vault ---
#Method -> Token = root

# --- Jenkins Workspace ---
WORKSPACE_NAME=npm-cicd
WORKSPACE_DIR=/var/jenkins_home/workspace/npm-cicd

# The absolute path to your project folder on Host (Windows)
LOCAL_PROJECT_PATH=C:/Users/evoel/Downloads/labs_dedi/npm
```

---

## 🛠 Git Version Control Guide
Before committing your changes, ensure your local Git identity is correctly configured:

```bash
# Set your Git identity (use --global for system-wide or --local for this repository only)
git config --global user.name "Dedi Mohammad Kurnia"
git config --global user.email "kurniawan.noperfect@gmail.com"
git status
```

Standard Commit & Push Workflow

```bash
git status
git add .
git commit -m "your message"
git push
```

🚨 Handling Accidental Credentials Exposure

If you accidentally commit sensitive data (such as API tokens or passwords) and your push gets blocked by GitHub Push Protection:
- Remove or clean the secret from your file(s).
- Reset your local commit history back to the remote state without losing your code changes:

```bash
git reset --soft origin/main
```

- Re-add and create a clean commit:

```bash
git add .
git commit -m "preparation migrasi to vault (clean)"
```

- Push safely:

```bash
git add .
git commit -m "preparation migrasi to vault (clean)"
```

## 🚀 Step-by-Step Guide

Make sure that Kubernetes is enabled and running in **Docker Desktop** (green status indicator) before proceeding.

### Option A: Linux / macOS / Git Bash Users
Navigate to the `scripts/bash` directory and run the setup script:
```bash
cd scripts/bash
chmod +x install.sh && ./install.sh
```

### Option B: Windows (PowerShell) Users
Open PowerShell and navigate to the `scripts\powershell` directory. If you encounter execution policy restrictions, bypass them first:
```powershell
cd scripts\powershell
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
.\install.ps1
```

---

## 🌐 Accessing Services

Once the installation script completes, all passwords and access details will be automatically printed in your terminal. You can access the following dashboards and services directly:

- **Jenkins:** `http://localhost:8080` 
  - *Note:* The `InitialAdminPassword` is automatically extracted and printed in the terminal at the end of the installation script.
  - Next, add credentials at `http://localhost:8080/manage/credentials/` using the "Username with password" credential type, with the IDs `dockerhub-creds` and `github-creds`. For `github-creds`, create a new token (*classic* type) at [https://github.com/settings/tokens](https://github.com/settings/tokens), then update your password using that token. 
  - Ensure the "Lightweight checkout" option at `http://localhost:8080/job/(yourpipeline)/configure` is checked, and make sure the Jenkinsfile directory matches the Script Path, for example `ci/Jenkinsfile`.
- **PostgreSQL:** `localhost:5432` (Credentials configured via your `.env` file)
- **MinIO:** `http://localhost:9001` (Credentials configured via your `.env` file)
- **ActiveMQ Artemis:** `http://localhost:8161` (Credentials configured via your `.env` file)
- **pgAdmin:** `http://localhost:8081` (Credentials configured via your `.env` file)
  > *Important Note:* When registering the PostgreSQL server in pgAdmin, use `host.docker.internal` as the Hostname/Address, because pgAdmin runs inside Kubernetes while PostgreSQL runs in Docker Compose.
- **ArgoCD Dashboard:** `http://argocd.local`
  - Accept the self-signed certificate warning.
  - Login with Username: `admin`
  - Password: `P4ssw0rdArgoCD` (This password is permanently locked by the setup script).
  - kubectl port-forward svc/argocd-server -n argocd 8088:80
- **HashiCorp Vault (Dev Mode):** `http://localhost:8200` 
  - Login with Token: `root`
- **Grafana:** `http://localhost:8083` 
  - Login with Username: `admin`
  - *Note:* The password is automatically extracted and printed in the terminal at the end of the script (default is `prom-operator` if not fetched).
- **Prometheus:** `http://localhost:9090`

---

## 🛠 Troubleshooting & Maintenance

### 1. Cleaning up Docker Resources
Use the following commands to clean your system from unused containers, networks, and dangling images to keep your storage optimized:

```bash
# Remove all unused containers, networks, and images
docker system prune -a

# List all remaining volumes in the system
docker volume ls

# List all remaining images in the system
docker images
```

### 2. Fixing DNS/Timeout Issues on Docker Desktop (Windows)
If you experience network connection failures or timeouts (*exit code: 28*) when running the installation process or building images, this is often caused by a Windows DNS resolution bug in Docker Desktop. Follow these steps to set a static DNS:

1. Open the **Docker Desktop** application.
2. Click the gear icon (**Settings**) in the top right corner.
3. Navigate to the **Docker Engine** menu on the left panel.
4. Add static DNS configuration (e.g., Google and Cloudflare: `"dns": ["8.8.8.8", "1.1.1.1"]`) into the Docker daemon JSON settings.

**Configuration Example:**
```json
{
  "builder": {
    "gc": {
      "defaultKeepStorage": "20GB",
      "enabled": true
    }
  },
  "dns": ["8.8.8.8", "1.1.1.1"],
  "experimental": false
}
```
5. Click **Apply & restart** in the bottom right corner and wait a moment for the Docker Engine to restart.

## 🗑️ Uninstall & Cleanup

If you wish to remove ArgoCD, Vault, and Prometheus from your Kubernetes cluster and stop/clean up Docker containers and their volumes, use the provided uninstall script:

* **Linux / macOS / Git Bash:**
  ```bash
  cd scripts/bash
  chmod +x uninstall.sh && ./uninstall.sh
  ```
* **Windows (PowerShell):**
  ```powershell
  cd scripts\powershell
  Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
  .\uninstall.ps1
  ```

---

## 👨‍💻 Let's Connect!

This project is designed to demonstrate practical implementations of Modern CI/CD, GitOps, Kubernetes, Docker, and Infrastructure Automation. 

Interested in discussing DevOps practices, SRE, or potential project collaborations? Let's connect!

[![LinkedIn Profile](https://img.shields.io/badge/LinkedIn-Dedi_Mohammad_Kurnia-0A66C2?style=for-the-badge&logo=linkedin)](https://www.linkedin.com/in/dedimohammadkurnia/)
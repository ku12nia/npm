# 🚀 Node.js GitOps & Local DevOps Lab (App of Apps Pattern)

![Jenkins](https://img.shields.io/badge/Jenkins-CI-blue?logo=jenkins)
![ArgoCD](https://img.shields.io/badge/ArgoCD-CD-orange?logo=argo)
![Kubernetes](https://img.shields.io/badge/Kubernetes-GitOps-blue?logo=kubernetes)
![Docker](https://img.shields.io/badge/Docker-Desktop-2496ED?logo=docker)
![Postgres](https://img.shields.io/badge/PostgreSQL-Database-336791?logo=postgresql)
[![LinkedIn](https://img.shields.io/badge/Connect-LinkedIn-0A66C2?logo=linkedin)](https://www.linkedin.com/in/dedimohammadkurnia/)

This repository provides a ready-to-use **Full-Stack Local DevOps & GitOps** ecosystem. It integrates a modern CI/CD pipeline using Jenkins, local database management (PostgreSQL + pgAdmin), and automated deployments to Kubernetes using **ArgoCD** following the **App of Apps** pattern. The entire infrastructure is designed to run seamlessly on top of **Docker Desktop**.

---

## 🏗️ Architecture & Ecosystem

This project applies the principle of **Separation of Concerns** through the following components:

1. **Local Infrastructure (Docker Compose):** Manages Jenkins (CI Server), PostgreSQL (Database), and pgAdmin (Database Manager) within an isolated container environment.
2. **Jenkins (Continuous Integration):** Manages automated pipelines that handle source code checkout, testing, building Docker images for the Node.js application, pushing to Docker Hub, and updating Kubernetes manifests in the Git repository—all independently without direct interaction with the Kubernetes cluster.
3. **ArgoCD (Continuous Deployment):** Acts as the primary GitOps controller. ArgoCD monitors the `k8s/` directory in Git. Whenever Jenkins updates the image tag, ArgoCD automatically detects the change and synchronizes it to your local Kubernetes cluster.

---

## 📂 Repository Structure

```text
📦 npm
 ┣ 📂 k8s                  <-- ☸️ CD Layer (ArgoCD & Kubernetes)
 ┃ ┣ 📜 root-app.yaml      # Root App configuration (App of Apps Controller)
 ┃ ┣ 📂 argocd-apps          
 ┃ ┃ ┗ 📜 node-app-prod.yaml # Child App configuration for Node.js
 ┃ ┗ 📜 app-deployment.yaml# App Infrastructure Blueprint (Deployment & Service)
 ┣ 📂 src                  <-- 💻 Source Code Layer (Node.js)
 ┃ ┣ 📜 index.js, package.json
 ┃ ┗ 📜 Dockerfile         # Docker Image build instructions
 ┣ 📂 linux-bash           <-- 🐧 Setup scripts for Linux/macOS/Git Bash
 ┣ 📂 windows              <-- 🪟 Setup scripts for Windows (PowerShell)
 ┣ 📜 docker-compose.yml   <-- 🐳 Local Infra (Jenkins, Postgres, pgAdmin)
 ┗ 📜 Jenkinsfile          <-- ⚙️ CI Layer (Jenkins Pipeline definition)
```

---

## 🚀 Step-by-Step Guide

Make sure that Kubernetes is enabled and running in **Docker Desktop** (green status indicator) before proceeding.

### Option A: Linux / macOS / Git Bash Users
Navigate to the `linux-bash` directory and run the setup script:
```bash
cd linux-bash
chmod +x setup.sh && ./setup.sh
```

### Option B: Windows (PowerShell) Users
Open PowerShell and navigate to the `windows` directory. If you encounter execution policy restrictions, bypass them first:
```powershell
cd windows
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
.\install.ps1
```

---

## 🌐 Accessing Services

Once the installation script completes, you can access the following dashboards and services:

* **Jenkins:** `http://localhost:8080` *(Run `docker logs jenkins-server` to retrieve the initial password)*
* **PostgreSQL:** `localhost:5432` (User: `postgres`, Pass: `passwordku`)
* **pgAdmin:** `http://localhost:8050` or `http://localhost:5050` (User: `admin@admin.com`, Pass: `adminpassword`)
  > *Note: When registering a new server in pgAdmin, use `postgres` as the Hostname/Address.*
* **ArgoCD Dashboard:** 
  Run the following port-forward command in a separate terminal:
  ```bash
  kubectl port-forward svc/argocd-server -n argocd 8082:443
  ```
  Then access `https://localhost:8082` (Accept self-signed certificate warning, login with username `admin`).

---

## 🗑️ Uninstall & Cleanup

If you wish to remove ArgoCD from your Kubernetes cluster and stop/clean up Docker containers and their volumes, use the provided uninstall script:

* **Linux / macOS / Git Bash:**
  ```bash
  cd linux-bash
  chmod +x uninstall.sh && ./uninstall.sh
  ```
* **Windows (PowerShell):**
  ```powershell
  cd windows
  .\uninstall.ps1
  ```

---

## 👨‍💻 Let's Connect!

This project is designed to demonstrate practical implementations of Modern CI/CD, GitOps, Kubernetes, Docker, and Infrastructure Automation. 

Interested in discussing DevOps practices, SRE, or potential project collaborations? Let's connect!

[![LinkedIn Profile](https://img.shields.io/badge/LinkedIn-Dedi_Mohammad_Kurnia-0A66C2?style=for-the-badge&logo=linkedin)](https://www.linkedin.com/in/dedimohammadkurnia/)
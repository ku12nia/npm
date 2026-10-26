# 🚀 DevOps CI/CD Automation Environment

This repository contains an automated local environment setup for a complete DevOps CI/CD pipeline using **Vagrant** and **Ubuntu**. It provisions infrastructure using **Docker Compose** and **Kubernetes (K3s)**.

## 🏗️ Architecture Stack
* **Virtualization:** Vagrant, VirtualBox (Ubuntu 26.04)
* **Docker Compose:** Jenkins, Nexus Artifactory, PostgreSQL, MinIO
* **Kubernetes (K3s):** ArgoCD, Nginx Ingress, PGAdmin, Prometheus & Grafana, HashiCorp Vault, ActiveMQ Artemis

---

## 📋 Prerequisites
Ensure you have the following installed on your Windows Host:
1. [VirtualBox](https://www.virtualbox.org/wiki/Downloads)
2. [Vagrant](https://developer.hashicorp.com/vagrant/downloads)
3. [Git](https://git-scm.com/downloads)

---

## 🛠️ Step-by-Step Setup Guide

### 1. Clone the Repository
Open PowerShell or your preferred terminal and clone this repository:
```bash
git clone <your-repo-url>
cd npm
```

### 2. Configure Environment Variables
Create a `.env` file in the root of the project directory (e.g., `npm/.env`) and add your credentials. **The script will abort if this file is missing.**

```env
# Example .env configuration
POSTGRES_PASSWORD=pg-local
PGADMIN_EMAIL=admin@example.com
PGADMIN_PASSWORD=pgadmin-local
DOCKER_USER=your_docker_username
DOCKER_PASS=your_docker_pat
MINIO_ROOT_USER=admin
MINIO_ROOT_PASSWORD=minioadmin
NEXUS_USERNAME=admin
NEXUS_PASSWORD=P4ssw0rdNexus
JENKINS_PASSWORD=jenkins
```

### 3. Vagrant Operations & Lifecycle Commands
Navigate to the scripts directory where the `Vagrantfile` is located:
```bash
cd scripts
```

Here are the essential Vagrant commands to manage your Virtual Machine:
* **`vagrant up`**: Starts and provisions the virtual machine.
* **`vagrant up --debug`**: Starts the VM and outputs detailed debug logs (useful for troubleshooting booting or SSH issues).
* **`vagrant halt`**: Gracefully shuts down the virtual machine.
* **`vagrant resume`**: Resumes a suspended virtual machine.
* **`vagrant reload`**: Restarts the virtual machine and re-evaluates the `Vagrantfile` (useful after changing forwarded ports or RAM/CPU allocations).

### 4. SSH and Execution Flow
Once the VM is up and running (`vagrant up`), connect to it and run the installation script.

1. **Access the VM via SSH:**
   ```bash
   vagrant ssh
   ```
   *(Note: If prompted via the VirtualBox GUI, the default credentials are Username: `vagrant`, Password: `vagrant`)*

2. **Switch to Root User:**
   The installation requires administrative privileges.
   ```bash
   sudo su
   ```

3. **Navigate to the Scripts Directory:**
   Vagrant syncs your local project folder to `/workspace` inside the VM.
   ```bash
   cd /workspace/scripts/bash
   ```

4. **Fix Windows Line Endings (CRLF to LF):**
   If you edited the scripts on Windows, they might have carriage returns (`^M`) that cause a `bad interpreter` error. Fix it using `sed`:
   ```bash
   sed -i -e 's/\r$//' install.sh
   ```

5. **Run the Installation Script:**
   ```bash
   ./install.sh
   ```

---

## 🌐 Accessing the Services
Once the script completes successfully, you can access your services directly from your Windows host browser:

* **Jenkins:** `http://localhost:8080`
* **Nexus:** `http://localhost:8082`
* **Vault UI:** `http://localhost:8200`
* **Grafana:** `http://localhost:8083`
* **Prometheus:** `http://localhost:9090`
* **PGAdmin:** `http://localhost:8081`
* **MinIO Console:** `http://localhost:9001`
* **ArgoCD:** `https://localhost`

---
## 🧹 Teardown
To destroy the environment and free up resources, run the following from your host machine (`scripts` directory):
```bash
vagrant destroy -f
```
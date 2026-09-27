# 🚀 Node.js GitOps with ArgoCD (App of Apps Pattern)

Repositori ini adalah implementasi dari **Modern GitOps Architecture** menggunakan **Jenkins** untuk Continuous Integration (CI) dan **ArgoCD** untuk Continuous Deployment (CD). 

Kita menggunakan arsitektur **"App of Apps"** agar seluruh infrastruktur dan aplikasi dapat dikelola 100% secara *declarative* lewat Git (Infrastructure as Code).

---

## 🏗️ Arsitektur CI/CD

Arsitektur ini memisahkan tanggung jawab secara tegas (*Separation of Concerns*):
1. **Jenkins (Tukang Masak):** Bertugas melakukan *testing*, *build* Docker Image, dan meng-update versi *image tag* di repositori ini. Jenkins **TIDAK** menyentuh klaster Kubernetes.
2. **ArgoCD (Mandor):** Bertugas memantau repositori ini. Jika ada perubahan konfigurasi (misal *tag image* baru), ArgoCD akan otomatis menarik dan menerapkan perubahan tersebut ke klaster Kubernetes.

**Alur Kerja (Workflow):**
`Developer Push Code` ➡️ `Jenkins Build Image` ➡️ `Jenkins Push ke Docker Hub` ➡️ `Jenkins Update Tag di YAML & Push ke Git` ➡️ `ArgoCD Auto-Sync ke K8s`

---

## 📂 Penjelasan Struktur Folder

Perhatikan folder `k8s/` karena di sinilah "Magic" GitOps itu terjadi:

```text
📦 npm
 ┣ 📂 k8s                  
 ┃ ┣ 📜 root-app.yaml               <-- (1) Sang Mandor (Root App)
 ┃ ┣ 📂 argocd-apps          
 ┃ ┃ ┗ 📜 node-app-prod.yaml        <-- (2) Sang Tukang (Child App)
 ┃ ┗ 📜 app-deployment.yaml         <-- (3) Blueprint Rumah (K8s Manifest)
 ┣ 📜 Jenkinsfile                   <-- Pipeline CI
 ┣ 📂 src                  <-- Wilayah Source Code Aplikasi
 ┃ ┣ 📜 package.json
 ┃ ┣ 📜 index.js
 ┃ ┣ 📜 index.test.js
 ┃ ┗ 📜 Dockerfile         <-- (Pindahkan Dockerfile ke sini)
# 🚀 Node.js GitOps & Local DevOps Lab (App of Apps Pattern)

![Jenkins](https://img.shields.io/badge/Jenkins-CI-blue?logo=jenkins)
![ArgoCD](https://img.shields.io/badge/ArgoCD-CD-orange?logo=argo)
![Kubernetes](https://img.shields.io/badge/Kubernetes-GitOps-blue?logo=kubernetes)
![Docker](https://img.shields.io/badge/Docker-Desktop-2496ED?logo=docker)
![Postgres](https://img.shields.io/badge/PostgreSQL-Database-336791?logo=postgresql)
[![LinkedIn](https://img.shields.io/badge/Connect-LinkedIn-0A66C2?logo=linkedin)](https://www.linkedin.com/in/dedimohammadkurnia/)

Repositori ini adalah sebuah ekosistem **Full-Stack Local DevOps & GitOps** yang siap pakai. Kita memadukan **CI/CD Pipeline modern** menggunakan Jenkins, manajemen database lokal (Postgres + pgAdmin), dan *Automated Deployment* ke Kubernetes menggunakan **ArgoCD (Pola App of Apps)**.

Semuanya berjalan di atas **Docker Desktop**.

---

## 🏗️ Arsitektur & Ekosistem

Proyek ini memisahkan tanggung jawab (*Separation of Concerns*) dengan sangat rapi:

1. **Local Infra (Docker Compose):** Menjalankan Jenkins (CI Server), PostgreSQL (Database), dan pgAdmin (DB Manager) secara terisolasi.
2. **Jenkins (CI):** Mengambil kode, menjalankan *test*, melakukan *build* Docker Image aplikasi Node.js, mengirimnya ke Docker Hub, dan meng-update *manifest* K8s di Git. (Sama sekali tidak berinteraksi dengan K8s secara langsung).
3. **ArgoCD (CD - Si Mandor):** Memantau folder `k8s/` di Git. Begitu Jenkins memperbarui versi *image tag*, ArgoCD otomatis menarik dan mensinkronisasikan perubahan tersebut ke klaster Kubernetes lokal (Docker Desktop).

---

## 📂 Struktur Repositori

```text
📦 npm
 ┣ 📂 k8s                  <-- ☸️ Wilayah CD (ArgoCD & Kubernetes)
 ┃ ┣ 📜 root-app.yaml               # Sang Mandor (Root App of Apps)
 ┃ ┣ 📂 argocd-apps          
 ┃ ┃ ┗ 📜 node-app-prod.yaml        # Sang Tukang (Child App / Worker)
 ┃ ┗ 📜 app-deployment.yaml         # Blueprint Infrastruktur App (Deployment & Service)
 ┣ 📂 src                  <-- 💻 Wilayah Source Code (Node.js)
 ┃ ┣ 📜 index.js, package.json
 ┃ ┗ 📜 Dockerfile                  # Pemasak Image
 ┣ 📜 docker-compose.yml   <-- 🐳 Local Infra (Jenkins, Postgres, pgAdmin)
 ┣ 📜 setup.sh             <-- 🛠️ Script Otomasi Instalasi ArgoCD
 ┗ 📜 Jenkinsfile          <-- ⚙️ Wilayah CI (Definisi Pipeline Jenkins)

---

👨‍💻 Let's Connect!

Proyek ini mendemonstrasikan pemahaman mendalam tentang Modern CI/CD, GitOps, Kubernetes, Docker, dan Automasi Infrastruktur.

Tertarik untuk berdiskusi lebih lanjut tentang DevOps, SRE, atau kolaborasi proyek? Let's connect!

[![LinkedIn Profile](https://img.shields.io/badge/LinkedIn-Dedi_Mohammad_Kurnia-0A66C2?style=for-the-badge&logo=linkedin)](https://www.linkedin.com/in/dedimohammadkurnia/)
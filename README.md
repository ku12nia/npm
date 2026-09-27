# 🚀 Node.js GitOps & Local DevOps Lab (App of Apps Pattern)

![Jenkins](https://img.shields.io/badge/Jenkins-CI-blue?logo=jenkins)
![ArgoCD](https://img.shields.io/badge/ArgoCD-CD-orange?logo=argo)
![Kubernetes](https://img.shields.io/badge/Kubernetes-GitOps-blue?logo=kubernetes)
![Docker](https://img.shields.io/badge/Docker-Desktop-2496ED?logo=docker)
![Postgres](https://img.shields.io/badge/PostgreSQL-Database-336791?logo=postgresql)
[![LinkedIn](https://img.shields.io/badge/Connect-LinkedIn-0A66C2?logo=linkedin)](https://www.linkedin.com/in/dedimohammadkurnia/)

Repositori ini adalah sebuah ekosistem **Full-Stack Local DevOps & GitOps** yang siap pakai. Kita memadukan **CI/CD Pipeline modern** menggunakan Jenkins, manajemen database lokal (Postgres + pgAdmin), dan *Automated Deployment* ke Kubernetes menggunakan **ArgoCD (Pola App of Apps)**.

Semuanya berjalan secara harmonis di atas **Docker Desktop**.

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

🚀 Cara Menjalankan Lab Ini (Step-by-Step)
1. Jalankan Infrastruktur Lokal (CI & Database)

Pertama, kita akan menghidupkan Jenkins, PostgreSQL, dan pgAdmin di background.
Bash

docker-compose up -d

    Info Akses Lokal:

        Jenkins: http://localhost:8080 (Gunakan docker logs jenkins-server untuk melihat password awal).

        pgAdmin: http://localhost:5050

2. Setup K8s & Instalasi ArgoCD

Pastikan fitur Kubernetes di Docker Desktop sudah aktif (berwarna hijau). Jalankan script instalasi untuk memasang ArgoCD ke dalam klaster:
Bash

chmod +x setup.sh && ./setup.sh

Ambil password admin ArgoCD (disimpan di dalam K8s Secret):
Bash

kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d; echo

Lakukan Port-Forwarding agar UI ArgoCD bisa diakses melalui http://localhost:8081 (Biarkan terminal ini terbuka, buka tab terminal baru untuk langkah selanjutnya):
Bash

kubectl port-forward svc/argocd-server -n argocd 8081:443

3. Pancing "Magic" GitOps (The App of Apps)

Di tab terminal baru, pancing ArgoCD dengan "Aplikasi Induk" (Root App). Anda hanya butuh 1 perintah ini untuk men-deploy seluruh aplikasi Node.js Anda!
Bash

kubectl apply -f https://raw.githubusercontent.com/ku12nia/npm/main/k8s/root-app.yaml

Selesai! 🎉
Silakan buka Dashboard ArgoCD (http://localhost:8081). Aplikasi argocd-root-app akan muncul dan secara otomatis melahirkan ekosistem node-app-prod. Semua Pod akan tersinkronisasi otomatis setiap kali Jenkins melakukan push YAML baru!

---

## 👨‍💻 Let's Connect!

Proyek ini mendemonstrasikan pemahaman mendalam tentang **Modern CI/CD, GitOps, Kubernetes, dan Automasi Infrastruktur**. 

Tertarik untuk berdiskusi lebih lanjut tentang DevOps, SRE, atau kolaborasi proyek? Let's connect!

[![LinkedIn Profile](https://img.shields.io/badge/LinkedIn-Dedi_Mohammad_Kurnia-0A66C2?style=for-the-badge&logo=linkedin)](https://www.linkedin.com/in/dedimohammadkurnia/)
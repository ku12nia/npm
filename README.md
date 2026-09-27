# 🚀 Node.js GitOps & Local DevOps Lab (App of Apps Pattern)

![Jenkins](https://img.shields.io/badge/Jenkins-CI-blue?logo=jenkins)
![ArgoCD](https://img.shields.io/badge/ArgoCD-CD-orange?logo=argo)
![Kubernetes](https://img.shields.io/badge/Kubernetes-GitOps-blue?logo=kubernetes)
![Docker](https://img.shields.io/badge/Docker-Desktop-2496ED?logo=docker)
![Postgres](https://img.shields.io/badge/PostgreSQL-Database-336791?logo=postgresql)
[![LinkedIn](https://img.shields.io/badge/Connect-LinkedIn-0A66C2?logo=linkedin)](https://www.linkedin.com/in/dedimohammadkurnia/)

Repositori ini menyediakan ekosistem **Full-Stack Local DevOps & GitOps** yang siap pakai. Proyek ini mengintegrasikan *CI/CD Pipeline* modern menggunakan Jenkins, manajemen *database* lokal (PostgreSQL + pgAdmin), serta otomasi *deployment* ke Kubernetes menggunakan **ArgoCD** dengan menerapkan pola **App of Apps**. Seluruh infrastruktur dirancang untuk beroperasi secara terintegrasi di atas **Docker Desktop**.

---

## 🏗️ Arsitektur & Ekosistem

Proyek ini menerapkan prinsip pemisahan tanggung jawab (*Separation of Concerns*) secara terstruktur melalui komponen-komponen berikut:

1. **Local Infrastructure (Docker Compose):** Mengelola layanan Jenkins (CI Server), PostgreSQL (Database), dan pgAdmin (Database Manager) dalam *environment* kontainer yang terisolasi.
2. **Jenkins (Continuous Integration):** Mengelola *pipeline* otomatis yang mencakup penarikan *source code*, eksekusi *testing*, proses *build* Docker Image untuk aplikasi Node.js, *push* ke Docker Hub, hingga pembaruan *manifest* Kubernetes di repositori Git. Proses ini berjalan secara independen tanpa interaksi langsung dengan klaster Kubernetes.
3. **ArgoCD (Continuous Deployment):** Berperan sebagai pengontrol *deployment* utama (*GitOps Controller*). ArgoCD bertugas memantau direktori `k8s/` di Git. Saat Jenkins memperbarui versi *image tag*, ArgoCD akan mendeteksi perubahan tersebut dan secara otomatis melakukan sinkronisasi untuk menerapkannya ke klaster Kubernetes lokal.

---

## 📂 Struktur Repositori

```text
📦 npm
 ┣ 📂 k8s                  <-- ☸️ Wilayah CD (ArgoCD & Kubernetes)
 ┃ ┣ 📜 root-app.yaml               # Konfigurasi Root App (App of Apps Controller)
 ┃ ┣ 📂 argocd-apps          
 ┃ ┃ ┗ 📜 node-app-prod.yaml        # Konfigurasi Child App untuk Node.js
 ┃ ┗ 📜 app-deployment.yaml         # Blueprint Infrastruktur App (Deployment & Service)
 ┣ 📂 src                  <-- 💻 Wilayah Source Code (Node.js)
 ┃ ┣ 📜 index.js, package.json
 ┃ ┗ 📜 Dockerfile                  # Instruksi Build Docker Image
 ┣ 📜 docker-compose.yml   <-- 🐳 Local Infra (Jenkins, Postgres, pgAdmin)
 ┣ 📜 setup.sh             <-- 🛠️ Script Otomasi Instalasi ArgoCD
 ┗ 📜 Jenkinsfile          <-- ⚙️ Wilayah CI (Definisi Pipeline Jenkins)
```

---

## 🚀 Cara Menjalankan Lab Ini (Step-by-Step)

### 1. Inisialisasi Infrastruktur Lokal (CI & Database)

Jalankan layanan Jenkins, PostgreSQL, dan pgAdmin di *background* menggunakan Docker Compose:

```bash
docker-compose up -d
```

**Informasi Akses Lokal:**
* **Jenkins:** `http://localhost:8080` (Gunakan perintah `docker logs jenkins-server` untuk melihat *password* inisialisasi awal).
* **pgAdmin:** `http://localhost:5050`

### 2. Setup Kubernetes & Instalasi ArgoCD

Pastikan fitur Kubernetes di Docker Desktop sudah berstatus aktif (indikator hijau). Eksekusi *script* berikut untuk memasang ArgoCD ke dalam klaster:

```bash
chmod +x setup.sh && ./setup.sh
```

Dapatkan *password* admin ArgoCD yang tersimpan di dalam *Kubernetes Secret*:

```bash
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d; echo
```

Lakukan *Port-Forwarding* agar antarmuka pengguna (UI) ArgoCD dapat diakses melalui `http://localhost:8081`. 
*(Biarkan proses pada terminal ini tetap berjalan, dan buka tab terminal baru untuk langkah selanjutnya)*:

```bash
kubectl port-forward svc/argocd-server -n argocd 8081:443
```

### 3. Implementasi GitOps (The App of Apps)

Pada tab terminal yang baru, terapkan konfigurasi "Aplikasi Induk" (*Root App*) untuk menginisiasi *deployment* seluruh ekosistem aplikasi secara otomatis:

```bash
kubectl apply -f https://raw.githubusercontent.com/ku12nia/npm/main/k8s/root-app.yaml
```

**Selesai!** 🎉 
Silakan akses *Dashboard* ArgoCD (`http://localhost:8081`). Aplikasi `argocd-root-app` akan muncul dan secara otomatis mendeploy ekosistem `node-app-prod`. Seluruh *Pod* akan terus tersinkronisasi secara otomatis setiap kali Jenkins melakukan *push* pembaruan YAML ke repositori.

---

## 👨‍💻 Let's Connect!

Proyek ini didesain untuk mendemonstrasikan implementasi praktis dari Modern CI/CD, GitOps, Kubernetes, Docker, dan Automasi Infrastruktur.

Tertarik untuk berdiskusi lebih lanjut mengenai praktik DevOps, SRE, atau potensi kolaborasi proyek? *Let's connect!*

[![LinkedIn Profile](https://img.shields.io/badge/LinkedIn-Dedi_Mohammad_Kurnia-0A66C2?style=for-the-badge&logo=linkedin)](https://www.linkedin.com/in/dedimohammadkurnia/)
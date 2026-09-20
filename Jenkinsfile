pipeline {
    agent any
    stages {
        stage('1. Checkout Code') {
            steps {
                checkout([
                    $class: 'GitSCM',
                    branches: [[name: '*/main']], // Sesuaikan branch utama Anda (misal: main atau master)
                    userRemoteConfigs: [[
                        url: 'https://github.com/ku12nia/npm.git' 
                        // Karena publik, parameter credentialsId tidak perlu ditulis/dikosongkan
                    ]]
                ])
                echo "✅ Berhasil checkout dari GitHub yang didaftarkan."
            }
        }
        stage('2. Test App') {
            steps {
                nodejs('NodeJS LTS') {
                    sh 'npm install'
                    // Jalankan Jest, hasilkan file XML dan folder coverage
                    sh 'npx jest --ci --coverage --reporters=default --reporters=jest-junit'
                    echo "✅ Unit Test Berhasil."
                }
            }
            post {
                always {
                    // Menangkap file XML dan memunculkan grafik Test Result di dashboard
                    junit 'junit.xml'
                }
            }
        }
   
        stage('3. Build & Push Docker Image') {
            steps {
                // Menggunakan nomor build Jenkins sebagai tag dinamis
                script {
                    def imageTag = "${env.BUILD_NUMBER}"
                    sh "docker build -t ku12nia/nodejs:${imageTag} ."
                    sh "docker tag ku12nia/nodejs:${imageTag} ku12nia/nodejs:latest"
                    // Pastikan credential Docker sudah diset di Jenkins jika private, kalau public cukup langsung push:
                    sh "docker push ku12nia/nodejs:${imageTag}"
                    sh "docker push ku12nia/nodejs:latest"
                    echo "🚀 Berhasil push update ke Docker Hub"
                }
            }
        }
        stage('4. Git Manifest Update via Trigged ArgoCD') {
            steps {
                script {
                    def imageTag = "${env.BUILD_NUMBER}"
                    echo "Mengupdate tag di app-deployment.yaml menjadi version: ${imageTag}"
                    // Mengubah baris image di file app-deployment.yaml secara otomatis menggunakan sed
                    sh """
                        sed -i 's|image: ku12nia/nodejs:.*|image: ku12nia/nodejs:${imageTag}|g' k8s/app-deployment.yaml
                    """
                    // Konfigurasi git user untuk agent Jenkins
                    sh 'git config --global user.email "jenkins@local.com"'
                    sh 'git config --global user.name "Jenkins Automation"'
                    // Cek apakah ada perubahan file sebelum melakukan commit & push
                    def changes = sh(script: 'git status --porcelain', returnStdout: true).trim()
                    if (changes) {
                        sh 'git add k8s/app-deployment.yaml'
                        sh 'git commit -m "ci(argocd): update image tag to ${imageTag}"'
                        withCredentials([gitUsernamePassword(credentialsId: 'github-access-token')]) {
                            sh 'git push origin HEAD:main'
                        }
                        echo "🚀 Berhasil push update ke GitHub! Menjalankan sinkronisasi ke ArgoCD."
                    } else {
                        echo "⚠️ Tidak ada perubahan pada manifest, skip git commit & push, Auto sync ArgoCD."
                    }
                }
            }
        }
        stage('5. Ensure ArgoCD App Exists (Safe CLI)') {
            steps {
                script {
                    sh '''
                        curl -sSL -o argocd https://github.com/argoproj/argo-cd/releases/latest/download/argocd-linux-amd64
                        chmod +x argocd
                    '''
                    def hasArgocd = sh(script: 'test -x ./argocd', returnStatus: true) == 0
                    if (hasArgocd) {
                        def argocdServer = "host.docker.internal:8081"
                        def argocdPass = "USrwCKyHLfSgZPGp"
                        sh """
                            # 1. Login dulu ke server ArgoCD
                            ./argocd login ${argocdServer} --username admin --password ${argocdPass} --insecure
                            # 2. Baru create aplikasinya
                            ./argocd app create node-app \
                            --repo https://github.com/ku12nia/npm.git \
                            --path k8s \
                            --dest-server https://kubernetes.default.svc \
                            --dest-namespace apps \
                            --sync-policy automated \
                            --upsert
                        """
                        echo "✅ Berhasil sinkronisasi aplikasi ke ArgoCD."
                    } else {
                        echo "⚠️ Perintah 'argocd' tidak ditemukan di agent ini. Melewatkan stage (Pipeline tetap sukses)."
                    }
                }
            }
        }
// -- stage selanjutnya
    }
}

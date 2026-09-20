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
            }
        }
        stage('2. Test App') {
            steps {
                nodejs('NodeJS LTS') {
                    sh 'npm install'
                    echo "Unit testing berhasil!"
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
                    
                    // Pastikan credential Docker sudah diset di Jenkins jika private, 
                    // kalau public cukup langsung push:
                    sh "docker push ku12nia/nodejs:${imageTag}"
                    sh "docker push ku12nia/nodejs:latest"
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
                        sed -i 's|image: ku12nia/nodejs:.*|image: ku12nia/nodejs:${imageTag}|g' app-deployment.yaml
                    """
                    
                    // Konfigurasi git user untuk agent Jenkins
                    sh 'git config --global user.email "jenkins@local.com"'
                    sh 'git config --global user.name "Jenkins Automation"'
                    
                    // Cek apakah ada perubahan file sebelum melakukan commit & push
                    def changes = sh(script: 'git status --porcelain', returnStdout: true).trim()
                    if (changes) {
                        sh 'git add app-deployment.yaml'
                        sh 'git commit -m "ci(argocd): update image tag to ${imageTag}"'
                        
                        withCredentials([gitUsernamePassword(credentialsId: 'github-access-token')]) {
                            sh 'git push origin HEAD:main'
                        }
                        echo "🚀 Berhasil push update ke GitHub! Silahkan cek ArgoCD."
                    } else {
                        echo "⚠️ Tidak ada perubahan pada manifest, skip git commit & push."
                        echo "🔍 Silahkan cek ArgoCD."
                    }
                }
            }
        }
// -- stage selanjutnya
    }
}

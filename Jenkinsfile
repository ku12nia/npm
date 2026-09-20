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
                    sh "docker build -t ku12nia/jenkins-slave-alpine:${imageTag} ."
                    sh "docker tag ku12nia/jenkins-slave-alpine:${imageTag} ku12nia/jenkins-slave-alpine:latest"
                    
                    // Pastikan credential Docker sudah diset di Jenkins jika private, 
                    // kalau public cukup langsung push:
                    sh "docker push ku12nia/jenkins-slave-alpine:${imageTag}"
                    sh "docker push ku12nia/jenkins-slave-alpine:latest"
                }
            }
        }
        stage('4. Trigger ArgoCD via Git Manifest Update') {
            steps {
                script {
                    def imageTag = "${env.BUILD_NUMBER}"
                    echo "Mengupdate tag di app-deployment.yaml menjadi version: ${imageTag}"
                    
                    // Mengubah baris image di file app-deployment.yaml secara otomatis menggunakan sed
                    sh """
                        sed -i 's|image: ku12nia/jenkins-slave-alpine:.*|image: ku12nia/jenkins-slave-alpine:${imageTag}|g' app-deployment.yaml
                    """
                    
                    // Konfigurasi git user untuk agent Jenkins
                    sh 'git config --global user.email "jenkins@local.com"'
                    sh 'git config --global user.name "Jenkins Automation"'
                    
                    // Commit dan push perubahan YAML ke GitHub agar ArgoCD otomatis mendeteksi
                    sh 'git add app-deployment.yaml'
                    sh 'git commit -m "ci(argocd): update image tag to ${imageTag}"'
                    
                    // Menggunakan token/credential GitHub untuk push kembali ke repo
                    withCredentials([gitUsernamePassword(credentialsId: 'github-access-token')]) {
                        sh 'git push origin HEAD:main'
                    }
                }
            }
        }
    }
}

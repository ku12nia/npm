pipeline {
    agent any
    stages {
        stage('1. Checkout Code') {
            steps {
                checkout scm
            }
        }
        stage('2. Test & Info') {
            steps {
                sh 'node -v || echo "Node belum terinstall di agent utama"'
                sh 'npm -v || echo "NPM belum terinstall di agent utama"'
                echo "Pipeline berjalan mulus di agent utama!"
            }
        }
        stage('3. Sync to ArgoCD') {
            steps {
                echo "Kode aman! Silakan atur ArgoCD untuk melakukan deployment otomatis menggunakan file app-deployment.yaml."
            }
        }
    }
}

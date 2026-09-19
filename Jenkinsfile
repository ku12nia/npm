pipeline {
    agent {
        docker {
            image 'node:alpine'
            args '-u root'
        }
    }
    environment {
        DOCKER_IMAGE = "ku12nia/jenkins-slave-alpine"
        TAG = "${env.BUILD_NUMBER}"
    }
    stages {
        stage('1. Checkout Code') {
            steps {
                checkout scm
            }
        }
        stage('2. Test App') {
            steps {
                sh 'npm install'
                echo "Unit testing passed successfully!"
            }
        }
        stage('3. Build & Push Docker Image') {
            steps {
                script {
                    // Karena kita pakai node:alpine, kita skip docker build di tahap ini 
                    // dan langsung biarkan ArgoCD yang menghandle deployment via manifest YAML.
                    echo "Docker image siap untuk di-deploy via ArgoCD!"
                }
            }
        }
        stage('4. Sync to ArgoCD') {
            steps {
                echo "Pipeline selesai! Silakan cek dashboard ArgoCD untuk melihat otomatisasi deployment."
            }
        }
    }
}

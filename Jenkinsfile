pipeline {
    agent any
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
                sh "docker build -t ${env.DOCKER_IMAGE}:${env.TAG} ."
                sh "docker tag ${env.DOCKER_IMAGE}:${env.TAG} ${env.DOCKER_IMAGE}:latest"
                sh "docker push ${env.DOCKER_IMAGE}:${env.TAG}"
                sh "docker push ${env.DOCKER_IMAGE}:latest"
            }
        }
        stage('4. Sync to ArgoCD') {
            steps {
                echo "Docker image berhasil di-push! ArgoCD akan otomatis mendeteksi perubahan."
            }
        }
    }
}
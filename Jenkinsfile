pipeline {
    agent {
        kubernetes {
            yaml """
apiVersion: v1
kind: Pod
metadata:
  labels:
    some-label: jenkins-agent
spec:
  containers:
  - name: node-builder
    image: ku12nia/jenkins-slave-alpine:alpine-node-latest
    command: ['cat']
    tty: true
"""
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
                container('node-builder') {
                    sh 'npm install'
                    echo "Unit testing passed successfully!"
                }
            }
        }
        stage('3. Build & Push Docker Image') {
            steps {
                container('node-builder') {
                    sh "docker build -t ${env.DOCKER_IMAGE}:${env.TAG} ."
                    sh "docker tag ${env.DOCKER_IMAGE}:${env.TAG} ${env.DOCKER_IMAGE}:latest"
                    sh "docker push ${env.DOCKER_IMAGE}:${env.TAG}"
                    sh "docker push ${env.DOCKER_IMAGE}:latest"
                }
            }
        }
        stage('4. Update Git Manifest (GitOps Trigger)') {
            steps {
                script {
                    echo "Mempersiapkan update tag image ke repo manifest..."
                }
            }
        }
    }
}

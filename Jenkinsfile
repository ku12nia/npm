pipeline {
    agent any

    parameters {
        choice(name: 'DEPLOY_ENV', choices: ['dev', 'staging', 'prod'], description: 'Target environment')
    }

    options {
        buildDiscarder(logRotator(numToKeepStr: '10'))
        disableConcurrentBuilds() // Cegah bentrok jika pipeline jalan bersamaan
    }

    environment {
        DOCKER_CREDS = credentials('dockerhub-creds')
        GIT_TOKEN    = credentials('github-access-token')
        IMAGE_REPO   = "ku12nia/nodejs"
        IMAGE_TAG    = "${env.BUILD_NUMBER}-${params.DEPLOY_ENV}"
        TARGET_BRANCH = (params.DEPLOY_ENV == 'prod') ? 'main' : params.DEPLOY_ENV
    }

    stages {
        stage('1. Checkout') {
            steps {
                script {
                    currentBuild.displayName = "#${env.BUILD_NUMBER} - ${params.DEPLOY_ENV}"
                }
                checkout scm
            }
        }

        stage('2. Test App') {
            steps {
                sh '''
                docker run --rm -v ${WORKSPACE}:/app -w /app/src node:22-alpine sh -c "
                    npm ci &&
                    npm install --save-dev jest jest-junit &&
                    npx jest --ci --coverage --reporters=default --reporters=jest-junit
                "
                '''
            }
            post {
                success {
                    junit 'junit.xml'
                }
            }
        }

        stage('3. Build & Push Image') {
            steps {
                echo "🏗️ Build Image: ${IMAGE_REPO}:${IMAGE_TAG}"
                sh "docker build -t ${IMAGE_REPO}:${IMAGE_TAG} ./src"
                
                if (params.DEPLOY_ENV == 'prod') {
                    sh "docker tag ${IMAGE_REPO}:${IMAGE_TAG} ${IMAGE_REPO}:latest"
                }

                echo "🔐 Push ke Docker Hub..."
                sh "echo \$DOCKER_CREDS_PSW | docker login -u \$DOCKER_CREDS_USR --password-stdin"
                sh "docker push ${IMAGE_REPO}:${IMAGE_TAG}"
                
                if (params.DEPLOY_ENV == 'prod') {
                    sh "docker push ${IMAGE_REPO}:latest"
                }
            }
        }

        stage('4. Update Manifest (Trigger GitOps)') {
            steps {
                echo "✨ Update YAML di branch: ${TARGET_BRANCH}"
                sh """
                    # Konfigurasi Git Identity
                    git config user.email "dedimk.devops@gmail.com"
                    git config user.name "Jenkins GitOps Bot"

                    # Update file manifest (menggunakan sed seperti kode asli Anda)
                    sed -i 's|image: ${IMAGE_REPO}:.*|image: ${IMAGE_REPO}:${IMAGE_TAG}|g' k8s/app-deployment.yaml

                    if ! git diff --quiet; then
                        git add k8s/app-deployment.yaml
                        # Tambahkan [skip ci] agar Jenkins tidak terpicu ulang oleh push ini!
                        git commit -m "ci(argocd): update image to ${IMAGE_TAG} [skip ci]"
                        
                        # Push menggunakan token secara aman
                        git push https://\${GIT_TOKEN_USR}:\${GIT_TOKEN_PSW}@github.com/ku12nia/npm.git HEAD:${TARGET_BRANCH}
                        echo "🚀 Berhasil update Git. ArgoCD akan segera sinkronisasi secara otomatis!"
                    else
                        echo "⚠️ Tidak ada perubahan manifest."
                    fi
                """
            }
        }
        
        // STAGE 5 (ArgoCD CLI) DIHAPUS - Karena ArgoCD sudah disetting 'automated sync' di argocd-app.yaml
    }
    
    post {
        always {
            cleanWs()
            sh "docker logout"
        }
    }
}
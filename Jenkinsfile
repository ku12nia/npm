pipeline {
    agent any

    parameters {
        choice(name: 'DEPLOY_ENV', choices: ['dev', 'staging', 'prod'], description: 'Target environment')
    }

    options {
        buildDiscarder(logRotator(numToKeepStr: '10'))
        disableConcurrentBuilds() // Prevent conflicts if pipelines operate simultaneously.
    }

    environment {
        DOCKER_CREDS = credentials('dockerhub-creds')
        GIT_TOKEN    = credentials('github-creds')
        IMAGE_REPO   = "ku12nia/nodejs"
        // IMAGE_TAG    = "${env.BUILD_NUMBER}-${params.DEPLOY_ENV}"
        // TARGET_BRANCH = (params.DEPLOY_ENV == 'prod') ? 'main' : params.DEPLOY_ENV
    }

    stages {
        stage('1. Checkout') {
            steps {
                script {
		    env.IMAGE_TAG = "${env.BUILD_NUMBER}-${params.DEPLOY_ENV}"
                    env.TARGET_BRANCH = (params.DEPLOY_ENV == 'prod') ? 'main' : params.DEPLOY_ENV
                    currentBuild.displayName = "#${env.BUILD_NUMBER} - ${params.DEPLOY_ENV}"
                }
                checkout scm
            }
        }

        stage('2. Test App') {
            steps {
                sh '''
                echo "FROM node:22-alpine" > Dockerfile.test
                echo "WORKDIR /app" >> Dockerfile.test
                echo "COPY src/ ./src/" >> Dockerfile.test

                docker build -t temp-test-env -f Dockerfile.test .
                set +e
                docker run --name test-runner temp-test-env sh -c "cd src && sed -i '1s/^\\xEF\\xBB\\xBF//' package.json && npm install && npm install --save-dev jest jest-junit && npx jest --ci --coverage --reporters=default --reporters=jest-junit"
                TEST_RESULT=$?
                set -e
                docker cp test-runner:/app/src/junit.xml ./junit.xml || echo "Warning: File junit.xml tidak ditemukan"
                
                # Cleanup container and files
                docker rm -f test-runner
                rm -f Dockerfile.test
                exit $TEST_RESULT
                '''
            }
            post {
                always {
                    junit allowEmptyResults: true, testResults: 'junit.xml'
                }
            }
        }

        stage('3. Build & Push Image') {
            steps {
                echo "🏗️ Build Image: ${IMAGE_REPO}:${IMAGE_TAG}"
                echo "🔐 Push ke Docker Hub..."
                
                sh """
                    # 1. Build image dengan tag spesifik
                    docker build -t ${IMAGE_REPO}:${IMAGE_TAG} ./src
                    
                    # 2. Login Docker Hub
                    echo \$DOCKER_CREDS_PSW | docker login -u \$DOCKER_CREDS_USR --password-stdin
                    
                    # 3. Push tag spesifik
                    docker push ${IMAGE_REPO}:${IMAGE_TAG}
                    
                    # 4. Jika environment prod, lakukan tag latest dan push menggunakan BASH Script
                    if [ "${params.DEPLOY_ENV}" = "prod" ]; then
                        echo "🚀 Environment PROD terdeteksi, pushing latest tag..."
                        docker tag ${IMAGE_REPO}:${IMAGE_TAG} ${IMAGE_REPO}:latest
                        docker push ${IMAGE_REPO}:latest
                    fi
                """
            }
        }

        stage('4. Update Manifest (Trigger GitOps)') {
            steps {
                echo "✨ Update YAML on branch: ${TARGET_BRANCH}"
                sh """
                    # Git Identity Configuration
                    git config user.email "dedimk.devops@gmail.com"
                    git config user.name "Jenkins GitOps Bot"

                    # Update file manifest
                    sed -i 's|image: ${IMAGE_REPO}:.*|image: ${IMAGE_REPO}:${IMAGE_TAG}|g' k8s/app-deployment.yaml

                    if ! git diff --quiet; then
                        git add k8s/app-deployment.yaml
                        git commit -m "ci(argocd): update image to ${IMAGE_TAG} [skip ci]"
                        
                        git push https://\${GIT_TOKEN_USR}:\${GIT_TOKEN_PSW}@github.com/ku12nia/npm.git HEAD:${TARGET_BRANCH}
                        echo "🚀 Git update successful. ArgoCD will automatically synchronize shortly!"
                    else
                        echo "⚠️ There are no changes to the manifest."
                    fi
                """
            }
        }
        
        // STAGE 5 (ArgoCD CLI) REMOVED – Because 'automated sync' has already been configured in argocd-app.yaml for ArgoCD.
    }
    
    post {
        always {
            cleanWs()
            sh "docker logout"
        }
    }
}
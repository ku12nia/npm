pipeline {
    agent {
        kubernetes {
            yaml '''
apiVersion: v1
kind: Pod
metadata:
  labels:
    some-label: nodejs-jenkins-agent
spec:
  containers:
  - name: jnlp
    image: jenkins/inbound-agent:latest
    workingDir: /home/jenkins/agent
  - name: docker
    image: docker:24.0.5-cli
    command: ['cat']
    tty: true
    volumeMounts:
    - name: docker-sock
      mountPath: /var/run/docker.sock
  volumes:
  - name: docker-sock
    hostPath:
      path: /var/run/docker.sock
            '''
        }
    }

    parameters {
        choice(name: 'DEPLOY_ENV', choices: ['dev', 'staging', 'prod'], description: 'Target environment')
    }

    options {
        buildDiscarder(logRotator(numToKeepStr: '10'))
        disableConcurrentBuilds()
    }

    environment {
        DOCKER_CREDS = credentials('dockerhub-creds')
        GIT_TOKEN    = credentials('github-creds')
        IMAGE_REPO   = "ku12nia/npm/nodejs" // Disesuaikan jika perlu
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
                container('docker') {
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
                    
                    docker rm -f test-runner
                    rm -f Dockerfile.test
                    exit $TEST_RESULT
                    '''
                }
            }
            post {
                always {
                    junit allowEmptyResults: true, testResults: 'junit.xml'
                }
            }
        }

        stage('3. Build & Push Image') {
            steps {
                container('docker') {
                    echo "🏗️ Build Image: ${IMAGE_REPO}:${IMAGE_TAG}"
                    echo "🔐 Push ke Docker Hub..."
                    
                    sh """
                        set -e
                        docker build -t ${IMAGE_REPO}:${IMAGE_TAG} -f src/Dockerfile ./src
                        echo \$DOCKER_CREDS_PSW | docker login -u \$DOCKER_CREDS_USR --password-stdin
                        
                        push_with_retry() {
                            local image_tag=\$1
                            echo "🚀 Memulai push untuk: \$image_tag"
                            
                            for i in {1..3}; do
                                if docker push \$image_tag; then
                                    echo "✅ Push berhasil!"
                                    return 0
                                else
                                    echo "⚠ Push gagal (Percobaan \$i dari 3). Retry dalam 5 detik..."
                                    sleep 5
                                fi
                            done
                            
                            echo "❌ Gagal push \$image_tag setelah 3 kali percobaan."
                            return 1
                        }
                        
                        push_with_retry ${IMAGE_REPO}:${IMAGE_TAG}
                        
                        if [ "${params.DEPLOY_ENV}" = "prod" ]; then
                            echo "🚀 Environment PROD terdeteksi, menyiapkan tag latest..."
                            docker tag ${IMAGE_REPO}:${IMAGE_TAG} ${IMAGE_REPO}:latest
                            push_with_retry ${IMAGE_REPO}:latest
                        fi
                    """
                }
            }
        }

        stage('4. Update Manifest (Trigger GitOps)') {
            steps {
                // Menggunakan container default/jnlp atau container terpisah yang ada git-nya
                sh """
                    git config user.email "dedimk.devops@gmail.com"
                    git config user.name "Jenkins GitOps Bot"

                    sed -i -E "s/tag: \\\".*\\\"/tag: \\\"${IMAGE_TAG}\\\"/" k8s/node-app-chart/values.yaml

                    if ! git diff --quiet; then
                        git add k8s/node-app-chart/values.yaml
                        git commit -m "ci(argocd): update helm image tag to ${IMAGE_TAG} [skip ci]"
                        
                        git push https://\${GIT_TOKEN_USR}:\${GIT_TOKEN_PSW}@github.com/ku12nia/npm.git HEAD:${TARGET_BRANCH}
                        echo "🚀 Git update successful. ArgoCD will automatically synchronize shortly!"
                    else
                        echo "⚠️ There are no changes to the manifest."
                    fi
                """
            }
        }
        
        stage('5. Wait for ArgoCD Sync') {
            options {
                retry(10)
            }
            steps {
                script {
                    try {
                        sh '''
                            echo "⏳ Waiting for ArgoCD synchronization..."
                            kubectl get deployment node-app -n prod-apps --server=https://kubernetes.default.svc --insecure-skip-tls-verify
                    
                            echo "✅ Deployment found! Checking Pod readiness status..."
                            kubectl rollout status deployment/node-app -n prod-apps \
                                --server=https://kubernetes.default.svc \
                                --insecure-skip-tls-verify \
                                --timeout=120s
                        '''
                    } catch (Exception e) {
                        sleep(time: 15, unit: 'SECONDS')
                        error "Deployment not found, retrying..."
                    }
                }
            }
        }
    }
    post {
        always {
            cleanWs()
            sh "docker logout || true"
        }
    }
}
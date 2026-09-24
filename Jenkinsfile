pipeline {
    agent any
    
    parameters {
        choice(name: 'DEPLOY_ENV', choices: ['dev', 'staging', 'prod'], description: 'Pilih target environment untuk deployment')
        booleanParam(name: 'IS_PRIVATE_REPO', defaultValue: false, description: 'Centang jika Docker Hub repository bersifat Private')
    }
    
    options {
        buildDiscarder(logRotator(numToKeepStr: '10'))
    }
    
    stages {
        stage('0. Setup Build Name') {
            steps {
                script {
                    currentBuild.displayName = "#${env.BUILD_NUMBER} - ${params.DEPLOY_ENV}"
                }
            }
        }
        
        stage('1. Checkout Code') {
            steps {
                script {
                    def targetBranch = (params.DEPLOY_ENV == 'prod') ? 'main' : params.DEPLOY_ENV
                    retry(3) {
                        checkout([
                            $class: 'GitSCM',
                            branches: [[name: "*/${targetBranch}"]],
                            extensions: [[$class: 'CloneOption', timeout: 30, noTags: false, reference: '', shallow: false]],
                            userRemoteConfigs: [[
                                url: 'https://github.com/ku12nia/npm.git' 
                            ]]
                        ])
                    }
                    echo "✅ Berhasil checkout dari branch ${targetBranch}."
                }
            }
        }
        
        stage('2. Persiapan Docker & Test App') {
            steps {
                script {
                    def hasDocker = sh(script: 'command -v docker', returnStatus: true) == 0
                    if (!hasDocker) {
                        echo "⚙️ Docker belum ada. Mengunduh Docker CLI..."
                        sh 'curl -sSL -o docker.tgz https://download.docker.com/linux/static/stable/x86_64/docker-24.0.9.tgz'
                        sh 'tar -xzf docker.tgz'
                        sh 'mv docker/docker /usr/bin/docker'
                        sh 'chmod +x /usr/bin/docker'
                        sh 'rm -rf docker docker.tgz'
                        echo "✅ Docker CLI berhasil dipasang!"
                    } else {
                        echo "✅ Docker CLI sudah tersedia."
                    }
                    echo "🛠️ Menjalankan Unit Test via Docker"
                    sh """
                    docker run --rm --volumes-from jenkins-9090 -w \${WORKSPACE} node:22-alpine sh -c "\
                        sed -i '1s/^\\\\xEF\\\\xBB\\\\xBF//' package.json && \
                        npm install && \
                        npm install --save-dev jest jest-junit && \
                        npx jest --ci --coverage --reporters=default --reporters=jest-junit \
                    "
                    """
                    echo "✅ Unit Test Berhasil."
                }
            }
            post {
                always {
                    junit 'junit.xml'
                    sh 'rm -rf node_modules coverage junit.xml'
                }
            }
        }
        
        stage('3. Build & Push Docker Image') {
            steps {
                script {
                    def targetEnv = params.DEPLOY_ENV
                    def imageTag = "${env.BUILD_NUMBER}-${targetEnv}"
                    echo "🏗️ Membangun Docker Image untuk: ${targetEnv}"
                    sh "docker build -t ku12nia/nodejs:${imageTag} ."
                    
                    if (targetEnv == 'prod') {
                        sh "docker tag ku12nia/nodejs:${imageTag} ku12nia/nodejs:latest"
                    }
                    def loginSuccess = true 
                    if (params.IS_PRIVATE_REPO) {
                        echo "🔒 Repo diatur sebagai Private. Memulai proses autentikasi Docker Hub..."
                        withCredentials([usernamePassword(credentialsId: 'dockerhub-credentials', usernameVariable: 'DOCKER_USER', passwordVariable: 'DOCKER_PASS')]) {
                            def loginStatus = sh(script: "echo \$DOCKER_PASS | docker login -u \$DOCKER_USER --password-stdin", returnStatus: true)
                            if (loginStatus != 0) {
                                loginSuccess = false 
                                echo "⚠️ PERINGATAN: Gagal login ke Docker Hub. Melewati tahap push..."
                                unstable("Docker Login Failed")
                            }
                        }
                    } else {
                        echo "🌍 Repo diatur sebagai Public. Melompati tahap login Docker Hub..."
                    }

                    if (loginSuccess) {
                        def pushStatusTag = sh(script: "docker push ku12nia/nodejs:${imageTag}", returnStatus: true)
                        if (pushStatusTag == 0) {
                            echo "🚀 Berhasil push image tag ${imageTag} ke Docker Hub"
                            if (targetEnv == 'prod') {
                                def pushLatest = sh(script: "docker push ku12nia/nodejs:latest", returnStatus: true)
                                if (pushLatest != 0) {
                                    echo "⚠️ PERINGATAN: Gagal push image tag latest."
                                    unstable("Docker Push Latest Failed")
                                }
                            }
                        } else {
                            echo "⚠️ PERINGATAN: Gagal push image ke Docker Hub."
                            unstable("Docker Push Failed")
                        }
                    }
                }
            }
        }
        
        stage('4. Update Manifest & Push ke Git') {
            steps {
                script {
                    def imageTag = "${env.BUILD_NUMBER}-${params.DEPLOY_ENV}"
                    def targetBranch = (params.DEPLOY_ENV == 'prod') ? 'main' : params.DEPLOY_ENV
                    
                    echo "✨ Mengupdate manifest di branch: ${targetBranch}"
                    sh "sed -i 's|image: ku12nia/nodejs:.*|image: ku12nia/nodejs:${imageTag}|g' k8s/app-deployment.yaml"
                    sh 'git config --global user.email "jenkins@local.com"'
                    sh 'git config --global user.name "Jenkins Automation"'
                    
                    def changes = sh(script: 'git status --porcelain', returnStdout: true).trim()
                    
                    if (changes != "") {
                        sh "git add k8s/app-deployment.yaml"
                        sh "git commit -m 'ci(argocd): update image tag to ${imageTag}'"
                        
                        withCredentials([gitUsernamePassword(credentialsId: 'github-access-token')]) {
                            def gitPushStatus = sh(script: "git push origin HEAD:${targetBranch}", returnStatus: true)
                            if (gitPushStatus == 0) {
                                echo "🚀 Berhasil push update manifest ke GitHub branch ${targetBranch}!"
                            } else {
                                echo "⚠️ PERINGATAN: Gagal push ke GitHub."
                                unstable("GitHub Push Failed")
                            }
                        }
                    } else {
                        echo "⚠️ Tidak ada perubahan pada manifest, skip git commit."
                    }
                }
            }
        }
        
        stage('5. Trigger Sync ArgoCD') {
            steps {
                script {
                    sh 'curl -sSL -o argocd https://github.com/argoproj/argo-cd/releases/latest/download/argocd-linux-amd64 && chmod +x argocd'
                    
                    def hasArgocd = sh(script: 'test -x ./argocd', returnStatus: true) == 0
                    if (hasArgocd) {
                        def argocdServer = "host.docker.internal:8081"
                        def argocdPass = "USrwCKyHLfSgZPGp"
                        def targetBranch = (params.DEPLOY_ENV == 'prod') ? 'main' : params.DEPLOY_ENV
                        def appName = "node-app-${params.DEPLOY_ENV}" 
                        def namespace = "${params.DEPLOY_ENV}-apps" 
                        def argoLoginStatus = sh(script: "./argocd login ${argocdServer} --username admin --password ${argocdPass} --insecure", returnStatus: true)
                        if (argoLoginStatus == 0) {
                            sh "./argocd app create ${appName} --repo https://github.com/ku12nia/npm.git --path k8s --revision ${targetBranch} --dest-server https://kubernetes.default.svc --dest-namespace ${namespace} --sync-policy automated --upsert"
                            echo "🔄 Berhasil sinkronisasi aplikasi ${appName} ke ArgoCD memantau branch ${targetBranch}."
                        } else {
                            echo "⚠️ PERINGATAN: Gagal terhubung ke server ArgoCD. Sinkronisasi CLI dilewati."
                            unstable("ArgoCD Login Failed")
                        }
                    } else {
                        echo "⚠️ Perintah 'argocd' tidak ditemukan. Stage dilewati."
                    }
                }
            }
        }
        
    }
}

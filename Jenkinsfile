pipeline {
    agent any
    parameters {
        choice(name: 'DEPLOY_ENV', choices: ['dev', 'staging', 'prod'], description: 'Pilih target environment untuk deployment')
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
                checkout([
                    $class: 'GitSCM',
                    branches: [[name: '*/main']],
                    userRemoteConfigs: [[
                        url: 'https://github.com/ku12nia/npm.git' 
                        // Perlu define config jika repo private
                    ]]
                ])
                echo "✅ Berhasil checkout dari GitHub yang didaftarkan."
            }
        }
        stage('2. Test App') {
            steps {
                nodejs('NodeJS LTS') {
                    sh "sed -i '1s/^\\xEF\\xBB\\xBF//' package.json"
                    sh 'npm install'
                    sh 'npm install --save-dev jest jest-junit'
                    sh 'npx jest --ci --coverage --reporters=default --reporters=jest-junit'
                    echo "✅ Unit Test Berhasil."
                }
            }
            post {
                always {
                    junit 'junit.xml'
                }
            }
        }
        stage('3. Build & Push Docker Image') {
            steps {
                script {
                    def imageTag = "${env.BUILD_NUMBER}-${params.DEPLOY_ENV}"
                    def targetEnv = "${params.DEPLOY_ENV}"
                    echo "Membangun Docker Image untuk: ${targetEnv}"
                    sh "docker build -t ku12nia/nodejs:${imageTag} ."
                    if (targetEnv == 'prod') {
                        sh "docker tag ku12nia/nodejs:${imageTag} ku12nia/nodejs:latest"
                    }
                    withCredentials([usernamePassword(credentialsId: 'dockerhub-credentials', usernameVariable: 'DOCKER_USER', passwordVariable: 'DOCKER_PASS')]) {
                        def loginStatus = sh(script: "echo \$DOCKER_PASS | docker login -u \$DOCKER_USER --password-stdin", returnStatus: true)
                        if (loginStatus == 0) {
                            def pushStatusTag = sh(script: "docker push ku12nia/nodejs:${imageTag}", returnStatus: true)
                            if (pushStatusTag == 0) {
                                echo "🚀 Berhasil push image tag ${imageTag} ke Docker Hub"
                                if (targetEnv == 'prod') {
                                    sh "docker push ku12nia/nodejs:latest"
                                }
                            } else {
                                echo "⚠️ PERINGATAN: Gagal push image ke Docker Hub."
                                unstable("Docker Push Failed")
                            }
                        } else {
                            echo "⚠️ PERINGATAN: Gagal login ke Docker Hub. Melewati tahap push..."
                            unstable("Docker Login Failed")
                        }
                    }
                }
            }
        }
        
        stage('4. Update Manifest & Push ke Git') {
            steps {
                script {
                    def imageTag = "${env.BUILD_NUMBER}-${params.DEPLOY_ENV}"
                    def targetEnv = "${params.DEPLOY_ENV}"
                    echo "Mengupdate manifest Kubernetes di folder: k8s/${targetEnv}/"
                    sh """
                        sed -i 's|image: ku12nia/nodejs:.*|image: ku12nia/nodejs:${imageTag}|g' k8s/${targetEnv}/app-deployment.yaml
                    """
                    sh 'git config --global user.email "jenkins@local.com"'
                    sh 'git config --global user.name "Jenkins Automation"'
                    def changes = sh(script: 'git status --porcelain', returnStdout: true).trim()
                    if (changes) {
                        sh "git add k8s/${targetEnv}/app-deployment.yaml"
                        sh "git commit -m 'ci(argocd): update ${targetEnv} image tag to ${imageTag}'"
                        withCredentials([gitUsernamePassword(credentialsId: 'github-access-token')]) {
                            def gitPushStatus = sh(script: 'git push origin HEAD:main', returnStatus: true)
                            if (gitPushStatus == 0) {
                                echo "🚀 Berhasil push update manifest ke GitHub!"
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
                    sh '''
                        curl -sSL -o argocd https://github.com/argoproj/argo-cd/releases/latest/download/argocd-linux-amd64
                        chmod +x argocd
                    '''
                    def hasArgocd = sh(script: 'test -x ./argocd', returnStatus: true) == 0
                    if (hasArgocd) {
                        def argocdServer = "host.docker.internal:8081"
                        def argocdPass = "USrwCKyHLfSgZPGp"
                        def targetEnv = "${params.DEPLOY_ENV}"
                        def appName = "node-app-${targetEnv}" 
                        def namespace = "${targetEnv}-apps" 
                        def argoLoginStatus = sh(
                            script: "./argocd login ${argocdServer} --username admin --password ${argocdPass} --insecure", 
                            returnStatus: true
                        )
                        if (argoLoginStatus == 0) {
                            sh """
                                ./argocd app create ${appName} \
                                --repo https://github.com/ku12nia/npm.git \
                                --path k8s/${targetEnv} \
                                --dest-server https://kubernetes.default.svc \
                                --dest-namespace ${namespace} \
                                --sync-policy automated \
                                --upsert
                            """
                            echo "✅ Berhasil sinkronisasi aplikasi ${appName} ke ArgoCD di namespace ${namespace}."
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
// -- stage selanjutnya
    }
}

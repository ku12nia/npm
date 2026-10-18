pipeline {
    agent any
    
    parameters {
        choice(name: 'DEPLOY_ENV', choices: ['dev', 'staging', 'prod'], description: 'Select the target environment for deployment.')
        string(name: 'IMAGE_TAG_TO_PROMOTE', defaultValue: '', description: 'Enter the Image Tag from the stable Dev/Staging environment. Leave blank if env = dev.')
        booleanParam(name: 'IS_PRIVATE_REPO', defaultValue: false, description: 'Check this box if the Docker Hub repository is private.')
    }
    
    options {
        buildDiscarder(logRotator(numToKeepStr: '10'))
    }
    
    stages {
        stage('0. Setup Build Name') {
            steps {
                script {
                    env.PADDED_BUILD_NUMBER = String.format("%02d", env.BUILD_NUMBER.toInteger())
                    currentBuild.displayName = "#${env.PADDED_BUILD_NUMBER} - ${params.DEPLOY_ENV}"
                }
            }
        }
        
        stage('1. Checkout Code') {
            steps {
                script {
                    def targetBranch = (params.DEPLOY_ENV == 'prod') ? 'main' : params.DEPLOY_ENV
                    
                    if (env.LOCAL_SRC_PATH) {
                        echo "💻 Local Directory Mode Active!"
                        if (!fileExists('Jenkinsfile')) {
                            error("❌ Workspace kosong! Pastikan repo sudah di-clone ke folder Windows host.")
                        } else {
                            echo "✅ Local source code is ready to build."
                        }
                    } else {
                        echo "🌐 Server Mode Active. Fetching from GitHub repository..."
                        cleanWs()
                        try {
                            checkout([
                                $class: 'GitSCM',
                                branches: [[name: "*/${targetBranch}"]],
                                extensions: [
                                    [$class: 'CleanBeforeCheckout'],
                                    [$class: 'CloneOption', timeout: 30, noTags: false, reference: '', shallow: false]
                                ],
                                userRemoteConfigs: [[
                                    url: 'https://github.com/ku12nia/npm.git',
                                    credentialsId: 'github-creds'
                                ]]
                            ])
                            echo "✅ Berhasil checkout dari branch: ${targetBranch}."
                        } catch (Exception e) {
                            echo "❌ Gagal checkout kode dari branch: ${targetBranch}."
                            error("Pipeline dihentikan karena checkout repositori gagal: ${e.getMessage()}")
                        }
                    }
                }
            }
        }

        stage('2. Test App via Docker') {
            when {
                environment name: 'DEPLOY_ENV', value: 'dev'
            }
            steps {
                script {
                    def containerId = sh(script: 'hostname', returnStdout: true).trim()
                    echo "🛠️ Menjalankan Unit Tests via Docker (Container ID: ${containerId})..."
                    
                    dir('src') {
                        sh """
                        docker run --rm --volumes-from ${containerId} -w \${WORKSPACE}/src node:22-alpine sh -c "\
                            sed -i '1s/^\\\\xEF\\\\xBB\\\\xBF//' package.json && \
                            npm install && \
                            npm install --save-dev jest jest-junit && \
                            npx jest --ci --coverage --reporters=default --reporters=jest-junit --passWithNoTests \
                        "
                        """
                    }
                }
            }
            post {
                success {
                    script {
                        if (fileExists('src/junit.xml')) {
                            try { junit 'src/junit.xml' } catch (e) { echo "⚠️ JUnit report tidak valid, dilewati..." }
                        }
                    }
                }
            }
        }
        
        stage('3. Approval Gate (Production)') {
            when {
                environment name: 'DEPLOY_ENV', value: 'prod'
            }
            steps {
                script {
                    echo "Menunggu persetujuan (Approval) untuk deploy ke Production..."
                    timeout(time: 1, unit: 'HOURS') {
                        input(
                            id: 'DeployToProd',
                            message: "⚠️ Lanjutkan deployment ke PRODUCTION menggunakan image tag: ${params.IMAGE_TAG_TO_PROMOTE}?",
                            ok: 'Approve & Deploy'
                        )
                    }
                    echo "✅ Deployment ke Production disetujui!"
                }
            }
        }

        stage('4. Build / Promote & Push Docker Image') {
            steps {
                script {
                    def targetEnv = params.DEPLOY_ENV
                    def imageRepo = "ku12nia/nodejs" 
                    def newImageTag = "${env.PADDED_BUILD_NUMBER}-${targetEnv}"
                    
                    dir('src') {
                        if (targetEnv == 'dev') {
                            echo "🏗️ Membangun Docker image baru dari source code untuk Dev..."
                            sh "DOCKER_BUILDKIT=1 docker build -t ${imageRepo}:${newImageTag} ."            
                        } else {
                            if (!params.IMAGE_TAG_TO_PROMOTE?.trim()) {
                                error("❌ Deployment ke ${targetEnv} dibatalkan! Parameter 'IMAGE_TAG_TO_PROMOTE' wajib diisi dengan image tag yang sudah stable (misal: 01-dev).")
                            }
                            echo "🔄 Mempromosikan image stable (Tag: ${params.IMAGE_TAG_TO_PROMOTE}) ke env ${targetEnv}..."
                            
                            sh "docker pull ${imageRepo}:${params.IMAGE_TAG_TO_PROMOTE}"
                            sh "docker tag ${imageRepo}:${params.IMAGE_TAG_TO_PROMOTE} ${imageRepo}:${newImageTag}"
                            
                            if (targetEnv == 'prod') {
                                sh "docker tag ${imageRepo}:${newImageTag} ${imageRepo}:latest"
                            }
                        }
                    }
                    
                    echo "🔐 Melakukan autentikasi otomatis ke Docker Hub..."
                    withCredentials([usernamePassword(credentialsId: 'dockerhub-creds', passwordVariable: 'DOCKER_PASS', usernameVariable: 'DOCKER_USER')]) {
                        def loginStatus = sh(
                            script: """
                                set +x
                                echo "\$DOCKER_PASS" | docker login -u "\$DOCKER_USER" --password-stdin
                            """, 
                            returnStatus: true
                        )
                        
                        if (loginStatus != 0) {
                            error("❌ Gagal login ke Docker Hub! Cek kredensial 'dockerhub-creds'.")
                        }
                        
                        echo "🚀 Pushing image tag: ${newImageTag} ke Docker Hub..."
                        def pushStatus = sh(script: "docker push ${imageRepo}:${newImageTag}", returnStatus: true)
                        
                        if (pushStatus != 0) {
                            error("❌ Gagal push image tag ${newImageTag} ke Docker Hub! Pipeline dihentikan.")
                        }
                        
                        if (targetEnv == 'prod') {
                            def pushLatest = sh(script: "docker push ${imageRepo}:latest", returnStatus: true)
                            if (pushLatest != 0) {
                                error("❌ Gagal push image 'latest'. Pipeline dihentikan.")
                            }
                        }
                    } 
                }
            }
        }
        
        stage('5. Update Manifest & Push ke Git') {
            steps {
                script {
                    def newImageTag = "${env.PADDED_BUILD_NUMBER}-${params.DEPLOY_ENV}"
                    def targetBranch = (params.DEPLOY_ENV == 'prod') ? 'main' : params.DEPLOY_ENV
                    def targetValuesFile = "k8s/helm-chart/values-${params.DEPLOY_ENV}.yaml" // <-- DINAMIS
                    
                    echo "✨ Mengupdate ${targetValuesFile} pada branch: ${targetBranch}"
                    
                    // Hanya update tag pada file environment yang spesifik
                    sh "sed -i 's/tag: .*/tag: \"${newImageTag}\"/g' ${targetValuesFile}"
                    
                    sh 'git config --global user.email "dedimk.devops@gmail.com"'
                    sh 'git config --global user.name "Dedi Mohammad Kurnia"'
                    
                    def changes = sh(script: 'git status --porcelain', returnStdout: true).trim()
                    
                    if (changes != "") {
                        sh "git add ${targetValuesFile}"
                        sh "git commit -m 'ci(argocd): update helm image tag for ${params.DEPLOY_ENV} to ${newImageTag} [skip ci]'"
                        
                        withCredentials([gitUsernamePassword(credentialsId: 'github-creds')]) {
                            sh "git push origin HEAD:${targetBranch}"
                        }
                    }
                }
            }
        }

        stage('6. Trigger ArgoCD Sync CLI') {
            steps {
                script {
                    def targetEnv = params.DEPLOY_ENV
                    def targetBranch = (targetEnv == 'prod') ? 'main' : targetEnv
                    def appName = "node-app-${targetEnv}" 
                    def namespace = "${targetEnv}-apps"
                    def targetValuesFile = "values-${targetEnv}.yaml"
                    def argocdServer = "host.docker.internal:80"
                    
                    withCredentials([usernamePassword(credentialsId: 'argocd-creds', passwordVariable: 'ARGOCD_PASS', usernameVariable: 'ARGOCD_USER')]) {
                        sh """
                            set +x
                            echo "🔐 Logging in to ArgoCD via CLI..."
                            argocd login ${argocdServer} --username \$ARGOCD_USER --password \$ARGOCD_PASS --plaintext --grpc-web
                            
                            echo "📝 Ensuring application ${appName} is registered..."
                            argocd app create ${appName} \
                              --repo https://github.com/ku12nia/npm.git \
                              --path k8s/helm-chart \
                              --revision ${targetBranch} \
                              --dest-server https://kubernetes.default.svc \
                              --dest-namespace ${namespace} \
                              --sync-option CreateNamespace=true \
                              --upsert
                            
                            echo "🚀 Syncing application: ${appName}..."
                            argocd app sync ${appName}
                        """
                    }
                    echo "🔄 Sinkronisasi ArgoCD berhasil untuk ${appName}!"
                }
            }
        }
    }    
    post {
        always {
            script {
                try {
                    echo "🧹 Membersihkan workspace untuk menghindari disk penuh pada server."
                    sh 'rm -rf node_modules coverage junit.xml docker.tgz docker'
                    echo "✨ Workspace sudah bersih kembali!"
                } catch (Exception e) {
                    echo "⚠️ Cleanup dilewati karena workspace tidak siap."
                }
            }
        }
    }
}
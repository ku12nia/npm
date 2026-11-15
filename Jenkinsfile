pipeline {
    agent any
    
    parameters {
        choice(name: 'DEPLOY_ENV', choices: ['dev', 'staging', 'prod'], description: 'Select the target environment for deployment.')
        string(name: 'IMAGE_TAG_TO_PROMOTE', defaultValue: '', description: 'Enter the Image Tag from stable env. Leave blank if env = dev.')
        booleanParam(name: 'IS_PRIVATE_REPO', defaultValue: false, description: 'Check if Docker Hub repo is private.')
    }
    
    options {
        buildDiscarder(logRotator(numToKeepStr: '10'))
    }
    
    triggers {
        githubPush()
    }

    stages {
        stage('0. Setup Build Name & Dynamic Environment') {
            steps {
                script {
                    env.PADDED_BUILD_NUMBER = String.format("%02d", env.BUILD_NUMBER.toInteger())
                    def buildCauses = currentBuild.getBuildCauses()
                    def isWebhook = buildCauses.any { it._class?.contains('GitHubPushCause') || it._class?.contains('SCMTriggerCause') }
                    
                    env.TARGET_ENV = isWebhook ? 'dev' : params.DEPLOY_ENV
                    currentBuild.displayName = "#${env.PADDED_BUILD_NUMBER} ${env.TARGET_ENV}"
                }
            }
        }

        stage('1. Checkout Code') {
            steps {
                script {
                    def targetEnv = env.TARGET_ENV
                    def targetBranch = (targetEnv == 'prod') ? 'main' : (targetEnv == 'staging') ? 'staging' : 'dev'
                    
                    cleanWs()
                    checkout([
                        $class: 'GitSCM',
                        branches: [[name: "*/${targetBranch}"]],
                        extensions: [[$class: 'CleanBeforeCheckout']],
                        userRemoteConfigs: [[
                            url: 'https://github.com/ku12nia/npm.git',
                            credentialsId: 'github-creds'
                        ]]
                    ])
                    
                    env.GIT_COMMIT_MSG = sh(script: 'git log -1 --pretty=%B', returnStdout: true).trim()
                    env.GIT_COMMIT_AUTHOR = sh(script: 'git log -1 --pretty=%an', returnStdout: true).trim()
                }
            }
        }

        stage('2. Test App via Docker') {
            when { environment name: 'TARGET_ENV', value: 'dev' }
            steps {
                script {
                    def containerId = sh(script: 'hostname', returnStdout: true).trim()
                    dir('src') {
                        sh """
                        docker run --rm --volumes-from ${containerId} -w \${WORKSPACE}/src node:22-alpine sh -c "\
                            npm install && npm install --save-dev jest jest-junit && \
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
                            try { junit 'src/junit.xml' } catch (e) { echo "⚠️ JUnit report skipped." }
                        }
                    }
                }
            }
        }

        // 🔥 SonarQube SAST Analysis Stage
        stage('2.5. Security - SonarQube SAST') {
            when { environment name: 'TARGET_ENV', value: 'dev' }
            steps {
                script {
                    echo "🔍 Menjalankan analisis SonarQube SAST..."
                    withSonarQubeEnv('sonar-server') { // Pastikan nama server SonarQube sesuai di Jenkins Global Config
                        sh 'sonar-scanner'
                    }
                }
            }
        }

        // 🔥 SonarQube Quality Gate Check Stage
        stage('2.6. Security - SonarQube Quality Gate') {
            when { environment name: 'TARGET_ENV', value: 'dev' }
            steps {
                script {
                    echo "⏳ Menunggu hasil Quality Gate dari SonarQube..."
                    timeout(time: 5, unit: 'MINUTES') {
                        def qg = waitForQualityGate()
                        if (qg.status != 'OK') {
                            error "❌ Pipeline dibatalkan: SonarQube Quality Gate berstatus ${qg.status} (Ditemukan celah/bugs yang melanggar aturan)."
                        } else {
                            echo "✅ SonarQube Quality Gate Lolos!"
                        }
                    }
                }
            }
        }

        stage('3. Approval Gate (Production)') {
            when { environment name: 'TARGET_ENV', value: 'prod' }
            steps {
                input(message: "Proceed to PRODUCTION using image tag: ${params.IMAGE_TAG_TO_PROMOTE}?", ok: 'Approve & Deploy')
            }
        }

        stage('4. Build & Push Docker Image') {
            steps {
                script {
                    def targetEnv = env.TARGET_ENV
                    def imageRepo = "ku12nia/nodejs" 
                    def newImageTag = "${env.PADDED_BUILD_NUMBER}-${targetEnv}"
                    
                    dir('src') {
                        if (targetEnv == 'dev') {
                            sh "docker pull ${imageRepo}:dev-cache || true"
                            sh "DOCKER_BUILDKIT=1 docker build --cache-from ${imageRepo}:dev-cache -t ${imageRepo}:${newImageTag} -t ${imageRepo}:dev-cache ."
                        } else {
                            sh "docker pull ${imageRepo}:${params.IMAGE_TAG_TO_PROMOTE}"
                            sh "docker tag ${imageRepo}:${params.IMAGE_TAG_TO_PROMOTE} ${imageRepo}:${newImageTag}"
                            if (targetEnv == 'prod') { sh "docker tag ${imageRepo}:${newImageTag} ${imageRepo}:latest" }
                        }
                    }

                    withCredentials([usernamePassword(credentialsId: 'dockerhub-creds', passwordVariable: 'DOCKER_PASS', usernameVariable: 'DOCKER_USER')]) {
                        sh '''
                            set +x
                            echo "$DOCKER_PASS" | docker login -u "$DOCKER_USER" --password-stdin
                        '''
                        sh "docker push ${imageRepo}:${newImageTag}"
                        if (targetEnv == 'dev') { sh "docker push ${imageRepo}:dev-cache" }
                        else if (targetEnv == 'prod') { sh "docker push ${imageRepo}:latest" }
                        sh "docker logout"
                    }
                }
            }
        }

        stage('5. Update Manifest & Push to Git') {
            steps {
                script {
                    def targetEnv = env.TARGET_ENV
                    def targetBranch = (targetEnv == 'prod') ? 'main' : (targetEnv == 'staging') ? 'staging' : 'dev' 
                    def newImageTag = "${env.PADDED_BUILD_NUMBER}-${targetEnv}"
                    def targetValuesFile = "k8s/helm-chart/values-${targetEnv}.yaml"
                    
                    sh "sed -i 's/tag: .*/tag: \"${newImageTag}\"/g' ${targetValuesFile}"
                    
                    def changes = sh(script: 'git status --porcelain', returnStdout: true).trim()
                    if (changes) {
                        sh "git add ${targetValuesFile}"
                        sh "git commit -m 'ci(argocd): update helm image tag for ${targetEnv} to ${newImageTag} [skip ci]'"
                        
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
                    def targetEnv = env.TARGET_ENV
                    def appName = "node-app-${targetEnv}" 
                    
                    withCredentials([usernamePassword(credentialsId: 'argocd-creds', passwordVariable: 'ARGOCD_PASS', usernameVariable: 'ARGOCD_USER')]) {
                        sh """
                            argocd login host.docker.internal:80 --username \$ARGOCD_USER --password \$ARGOCD_PASS --plaintext --grpc-web
                            argocd app sync ${appName} --replace
                        """
                    }
                }
            }
        }
    }
    
    post {
        always {
            cleanWs(deleteDirs: true, disableDeferredWipeout: true)
        }
    }
}
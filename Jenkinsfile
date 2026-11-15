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
                    
                    try {
                        cleanWs(deleteDirs: true, disableDeferredWipeout: true)
                    } catch (Exception e) {
                        echo "⚠️ Warning: cleanWs failed, forcing cleanup..."
                        sh 'rm -rf * .git || true'
                    }

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

        // 🔥 SonarQube SAST Analysis via Docker Scanner CLI
        stage('2.5. Security - SonarQube SAST') {
            steps {
                script {
                    echo "🔍 Running SonarQube SAST analysis via the latest SonarScanner (Java 21 Ready)..."
                    withCredentials([string(credentialsId: 'sonar-token', variable: 'SONAR_TOKEN')]) {
                        sh """
                        docker run --rm \
                        -v /var/jenkins_home/workspace/npm-cicd/src:/usr/src \
                        -w /usr/src \
                        sonarsource/sonar-scanner-cli:latest \
                        -Dsonar.projectKey=node-app-backend \
                        -Dsonar.sources=. \
                        -Dsonar.host.url=http://192.168.0.136:9002 \
                        -Dsonar.token=${SONAR_TOKEN}
                        """
                    }
                }
            }
        }

        // 🔥 SonarQube Quality Gate Check via REST API Curl
        stage('2.6. Security - SonarQube Quality Gate') {
            steps {
                script {
                    echo "⏳ Menunggu hasil Quality Gate dari SonarQube..."
                    withCredentials([string(credentialsId: 'sonar-token', variable: 'SONAR_TOKEN')]) {
                        sleep 5
                        def qgResponse = sh(script: "curl -s -u \${SONAR_TOKEN}: http://192.168.0.136:9002/api/qualitygates/project_status?projectKey=node-app-backend", returnStdout: true).trim()
                        echo "API Response: ${qgResponse}"
                        if (!qgResponse.contains('"status":"OK"') && !qgResponse.contains('"status":"NONE"')) {
                            error("❌ Quality Gate failed! Status not OK.")
                        } else {
                            echo "✅ Quality Gate passed or safe to proceed."
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
                    def targetEnv = env.TARGET_ENV ?: 'dev'
                    def targetBranch = (targetEnv == 'prod') ? 'main' : (targetEnv == 'staging') ? 'staging' : 'dev' 
                    def newImageTag = "${env.PADDED_BUILD_NUMBER}-${targetEnv}"
                    def targetValuesFile = "k8s/helm-chart/values-${targetEnv}.yaml"
                    
                    echo "📂 Updating manifest for environment: ${targetEnv} (File: ${targetValuesFile})"
                    
                    // 1. Update image tag in the corresponding Helm values file
                    sh "sed -i 's/tag: .*/tag: \"${newImageTag}\"/g' ${targetValuesFile}"
                    
                    // 2. Check if there are any actual file changes
                    def changes = sh(script: 'git status --porcelain', returnStdout: true).trim()
                    if (changes) {
                        // 3. Enforce push policy: Only 'dev' is allowed to auto-push
                        if (targetEnv == 'dev') {
                            echo "🚀 Environment is 'dev'. Automatically committing and pushing to branch '${targetBranch}'..."
                            
                            sh """
                            git config user.name "Dedi Mohammad Kurnia"
                            git config user.email "kurniawan.noperfect@gmail.com"
                            git add ${targetValuesFile}
                            git commit -m "ci(argocd): update helm image tag for ${targetEnv} to ${newImageTag} [skip ci]"
                            """
                            
                            withCredentials([gitUsernamePassword(credentialsId: 'github-creds')]) {
                                sh "git push origin HEAD:${targetBranch}"
                            }
                            echo "✅ Manifest successfully pushed to branch '${targetBranch}'."
                        } else {
                            echo "⚠️ Security Policy: Auto-push is DISABLED for environment '${targetEnv}' (Staging/Prod)."
                            echo "💡 Skipping git commit & push. Manifest changes remain local for this pipeline run."
                            
                            // Revert local changes to keep the workspace clean
                            sh "git checkout ${targetValuesFile}"
                        }
                    } else {
                        echo "ℹ️ No changes detected in ${targetValuesFile}."
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
            script {
                try {
                    echo "📱 Sending notification to Telegram..."
                    def buildStatus = currentBuild.currentResult ?: 'SUCCESS'
                    def statusEmoji = (buildStatus == 'SUCCESS') ? '✅' : '❌'
                    def targetEnv = env.TARGET_ENV ?: 'N/A'
                    def rawBuildUrl = env.BUILD_URL ?: "http://localhost:8080/job/${env.JOB_NAME}/${env.BUILD_NUMBER}/"
                    def buildUrl = rawBuildUrl.replace("localhost", "192.168.0.136")
                    // def buildUrl = "${env.BUILD_URL}"
                    
                    def commitInfo = env.GIT_COMMIT_MSG ? "\n📌 <b>Commit:</b> ${env.GIT_COMMIT_MSG}\n👤 <b>Author:</b> ${env.GIT_COMMIT_AUTHOR}" : ""
                    
                    def tgMessage = "===============================\n" +
                                    "🚀 <b>Jenkins Pipeline Update</b>\n" +
                                    "===============================\n" +
                                    "📂 <b>Project:</b> ${env.JOB_NAME}\n" +
                                    "🏷️ <b>Build No:</b> #${env.BUILD_NUMBER}\n" +
                                    "🌿 <b>Environment:</b> ${targetEnv}${commitInfo}\n" +
                                    "${statusEmoji} <b>Status:</b> ${buildStatus}\n" +
                                    "===============================\n" +
                                    "📝 <a href='${buildUrl}'>Log Build = ${buildUrl}</a>"

                    withCredentials([string(credentialsId: 'telegram-bot-token', variable: 'TELEGRAM_TOKEN')]) {
                        def chatId = "-1003786747095"
                        sh """
                            curl -s -X POST "https://api.telegram.org/bot\${TELEGRAM_TOKEN}/sendMessage" \
                            -d chat_id="${chatId}" \
                            -d parse_mode="HTML" \
                            --data-urlencode text="${tgMessage}"
                        """
                    }
                    echo "📨 Telegram notification successfully sent."
                } catch (Exception e) {
                    echo "⚠️ Failed to send Telegram notification: ${e.getMessage()}"
                }
            }
        }
    }
}
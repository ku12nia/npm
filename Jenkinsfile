pipeline {
    agent any
    
    // Parameters: User input provided when running manually (Build with Parameters)
    parameters {
        choice(name: 'DEPLOY_ENV', choices: ['dev', 'staging', 'prod'], description: 'Select the target environment for deployment.')
        string(name: 'IMAGE_TAG_TO_PROMOTE', defaultValue: '', description: 'Enter the Image Tag from the stable Dev/Staging environment. Leave blank if env = dev.')
        booleanParam(name: 'IS_PRIVATE_REPO', defaultValue: false, description: 'Check this box if the Docker Hub repository is private.')
    }
    
    options {
        buildDiscarder(logRotator(numToKeepStr: '10'))
    }
    
    // Automatic trigger from GitHub/Smee.io (Ensure the Webhook on GitHub is set to "Just the push event")
    triggers {
        githubPush()
    }

    stages {
        // Stage 0. Setup Build Name & Dynamic Environment
        stage('0. Setup Build Name') {
            steps {
                script {
                    env.PADDED_BUILD_NUMBER = String.format("%02d", env.BUILD_NUMBER.toInteger())
                    // Detect whether this build was triggered by a Webhook or manually
                    def buildCauses = currentBuild.getBuildCauses()
                    def isWebhook = buildCauses.any { it._class?.contains('GitHubPushCause') || it._class?.contains('SCMTriggerCause') }
                    
                    if (isWebhook) {
                        // If triggered automatically by a webhook, we lock the env to 'dev'
                        env.TARGET_ENV = 'dev'
                        echo "🔄 Trigger otomatis dari Webhook terdeteksi. Memaksa environment ke: ${env.TARGET_ENV}"
                    } else {
                        // If triggered manually (by clicking a button in Jenkins)
                        env.TARGET_ENV = params.DEPLOY_ENV
                        echo "👤 Trigger manual terdeteksi. Menggunakan environment: ${env.TARGET_ENV}"
                    }
                    
                    currentBuild.displayName = "#${env.PADDED_BUILD_NUMBER} - ${env.TARGET_ENV}"
                }
            }
        }

        // Stage 1. Checkout Code
        stage('1. Checkout Code') {
            steps {
                script {
                    def targetBranch = (env.TARGET_ENV == 'prod') ? 'main' : env.TARGET_ENV
                    
                    if (env.LOCAL_SRC_PATH) {
                        echo "💻 Local Directory Mode Active!"
                        if (!fileExists('Jenkinsfile')) {
                            error("❌ Workspace is empty! Ensure the repo has been cloned into the Windows host folder.")
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
                            echo "✅ Successfully checked out from branch: ${targetBranch}."

                            // Git commit info extraction
                            env.GIT_COMMIT_MSG = sh(script: 'git log -1 --pretty=%B', returnStdout: true).trim()
                            env.GIT_COMMIT_AUTHOR = sh(script: 'git log -1 --pretty=%an', returnStdout: true).trim()
                            echo "Trigger disebabkan oleh Push dari: ${env.GIT_COMMIT_AUTHOR}"
                            echo "Pesan Commit: ${env.GIT_COMMIT_MSG}"

                        } catch (Exception e) {
                            echo "❌ Failed to check out code from branch: ${targetBranch}."
                            error("Pipeline stopped because the repository checkout failed: ${e.getMessage()}")
                        }
                    }
                }
            }
        }

        // Stage 2. Test App via Docker
        stage('2. Test App via Docker') {
            when {
                environment name: 'TARGET_ENV', value: 'dev'
            }
            steps {
                script {
                    def containerId = sh(script: 'hostname', returnStdout: true).trim()
                    echo "🛠️ Running Unit Tests via Docker (Container ID: ${containerId})..."
                    
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
                            try { junit 'src/junit.xml' } catch (e) { echo "⚠️ Unit report is invalid, skipping." }
                        }
                    }
                }
            }
        }

        // Stage 3. Approval Gate (Production)
        stage('3. Approval Gate (Production)') {
            when {
                environment name: 'TARGET_ENV', value: 'prod'
            }
            steps {
                script {
                    echo "Waiting approval to deploy to Production."
                    timeout(time: 1, unit: 'HOURS') {
                        input(
                            id: 'DeployToProd',
                            message: "⚠️ Proceed with deployment to PRODUCTION using the image tag: ${params.IMAGE_TAG_TO_PROMOTE}?",
                            ok: 'Approve & Deploy'
                        )
                    }
                    echo "✅ Deployment to production approved!"
                }
            }
        }

        // Stage 4. Build / Promote & Push Docker Image
        stage('4. Build / Promote & Push Docker Image') {
            steps {
                script {
                    def targetEnv = env.TARGET_ENV
                    def imageRepo = "ku12nia/nodejs" 
                    def newImageTag = "${env.PADDED_BUILD_NUMBER}-${targetEnv}"
                    
                    dir('src') {
                        if (targetEnv == 'dev') {
                            echo "🔍 Pulling the previous dev image for cache reference."
                            sh "docker pull ${imageRepo}:dev-cache || true"
                            echo "🏗️ Building a new Docker image (using BuildKit cache)."
                            sh "DOCKER_BUILDKIT=1 docker build --cache-from ${imageRepo}:dev-cache --build-arg BUILDKIT_INLINE_CACHE=1 -t ${imageRepo}:${newImageTag} -t ${imageRepo}:dev-cache ."
                        } else {
                            if (!params.IMAGE_TAG_TO_PROMOTE?.trim()) {
                                error("❌ Deployment to ${targetEnv} has been cancelled! The 'IMAGE_TAG_TO_PROMOTE' parameter must be provided with a stable image tag (e.g., 01-dev).")
                            }
                            echo "🔄 Promote stable image (Tag: ${params.IMAGE_TAG_TO_PROMOTE}) to env ${targetEnv}."
                            
                            sh "docker pull ${imageRepo}:${params.IMAGE_TAG_TO_PROMOTE}"
                            sh "docker tag ${imageRepo}:${params.IMAGE_TAG_TO_PROMOTE} ${imageRepo}:${newImageTag}"
                            
                            if (targetEnv == 'prod') {
                                sh "docker tag ${imageRepo}:${newImageTag} ${imageRepo}:latest"
                            }
                        }
                    }

                    echo "🔐 Performing automatic authentication to Docker Hub."
                    withCredentials([usernamePassword(credentialsId: 'dockerhub-creds', passwordVariable: 'DOCKER_PASS', usernameVariable: 'DOCKER_USER')]) {
                        try {
                            sh '''
                                set +x
                                echo "$DOCKER_PASS" | docker login -u "$DOCKER_USER" --password-stdin
                            '''
                            echo "🚀 Pushing image tag: ${newImageTag} ke Docker Hub..."
                            sh "docker push ${imageRepo}:${newImageTag}"
                            
                            if (targetEnv == 'dev') {
                                echo "🚀 Pushing image cache referensi (dev-cache)."
                                sh "docker push ${imageRepo}:dev-cache"
                            } else if (targetEnv == 'prod') {
                                echo "🚀 Pushing image latest..."
                                sh "docker push ${imageRepo}:latest"
                            }
                        } catch (Exception e) {
                            error("❌ Process Docker push failed: ${e.getMessage()}")
                        } finally {
                            sh "docker logout"
                            echo "🔒 Docker logged out successfully. State cleaned."
                        }
                    } 
                }
            }
        }

        // Stage 5: Update Manifest & Push ke Git
        stage('5. Update Manifest & Push ke Git') {
            steps {
                script {
                    def targetEnv = env.TARGET_ENV
                    def targetBranch = (targetEnv == 'prod') ? 'main' : targetEnv
                    def newImageTag = "${env.PADDED_BUILD_NUMBER}-${targetEnv}"
                    def targetValuesFile = "k8s/helm-chart/values-${targetEnv}.yaml"
                    
                    echo """
                    ==========================================================
                    🚀 [GIT OPS] UPDATING HELM MANIFEST
                    ==========================================================
                    📌 Target Env   : ${targetEnv}
                    📌 Target File  : ${targetValuesFile}
                    🌿 Target Branch: ${targetBranch}
                    🏷️  New Image Tag: ${newImageTag}
                    ==========================================================
                    """
                    sh "sed -i 's/tag: .*/tag: \"${newImageTag}\"/g' ${targetValuesFile}"
                    echo "✅ File ${targetValuesFile} has been successfully updated with tag: ${newImageTag}"
                    
                    sh 'git config --global user.email "dedimk.devops@gmail.com"'
                    sh 'git config --global user.name "Dedi Mohammad Kurnia"'
                    
                    def changes = sh(script: 'git status --porcelain', returnStdout: true).trim()
                    if (changes) {
                        echo "🔍 File changes detected:\n${changes}"
                        echo "⚙️ Performing commit & push process."
                        sh "git add ${targetValuesFile}" 
                        sh "git commit -m 'ci(argocd): update helm image tag for ${targetEnv} to ${newImageTag} [skip ci]'"
                        withCredentials([gitUsernamePassword(credentialsId: 'github-creds')]) {
                            def gitPushStatus = sh(script: "git push origin HEAD:${targetBranch}", returnStatus: true)
                            if (gitPushStatus == 0) {
                                echo "🎉 [SUCCESS] Successfully pushed Helm manifest update to the branch: ${targetBranch}!"
                            } else {
                                unstable("⚠️ [WARNING] Failed to push to GitHub. Check the logs or the 'github-creds' credentials.")
                            }
                        }
                    } else {
                        echo "⚠️ [SKIPPED] No changes to the manifest; skipping the git commit & push process."
                    }
                }
            }
        }

        // Stage 6: Trigger ArgoCD Sync CLI
        stage('6. Trigger ArgoCD Sync CLI') {
            steps {
                script {
                    def targetEnv = env.TARGET_ENV
                    def targetBranch = (targetEnv == 'prod') ? 'main' : targetEnv
                    def appName = "node-app-${targetEnv}" 
                    def namespace = "${targetEnv}-apps" 
                    def targetValuesFile = "values-${targetEnv}.yaml"
                    def argocdServer = "argocd.local"

                    withCredentials([usernamePassword(credentialsId: 'argocd-creds', passwordVariable: 'ARGOCD_PASS', usernameVariable: 'ARGOCD_USER')]) {
                        try {
                            sh """
                                set +x
                                echo "🔐 Logging in to ArgoCD via CLI..."
                                argocd login ${argocdServer} --username \$ARGOCD_USER --password \$ARGOCD_PASS --plaintext --insecure --grpc-web
                                
                                echo "📝 Ensuring application ${appName} is registered..."
                                argocd app create ${appName} \
                                  --repo https://github.com/ku12nia/npm.git \
                                  --path k8s/helm-chart \
                                  --revision ${targetBranch} \
                                  --values ${targetValuesFile} \
                                  --dest-server https://kubernetes.default.svc \
                                  --dest-namespace ${namespace} \
                                  --sync-option CreateNamespace=true \
                                  --sync-option Replace=true \
                                  --upsert
                                
                                echo "🚀 Syncing application: ${appName}..."
                                argocd app sync ${appName} --replace
                            """
                            echo "🔄 ArgoCD synchronization was successful for ${appName}!"
                        } finally {
                            sh "argocd logout ${argocdServer} || true"
                            echo "🔒 ArgoCD logged out successfully. State cleaned."
                        }
                    }
                }
            }
        }
    }    
    post {
        always {
            // 1. Cleaning Workspace
            script {
                try {
                    echo "🧹 Cleaning up the workspace to prevent the server disk from becoming full."
                    cleanWs()
                    echo "✨ Workspace cleaned successfully."
                } catch (Exception e) {
                    echo "⚠️ Cleanup was skipped because the workspace was not ready."
                }
            }

            // 2. Telegram Notification
            script {
                try {
                    echo "📱 Sending notification to Telegram..."
                    def buildStatus = currentBuild.currentResult ?: 'SUCCESS'
                    def statusEmoji = (buildStatus == 'SUCCESS') ? '✅' : '❌'
                    def targetEnv = env.TARGET_ENV ?: 'N/A'
                    // Compile commit info, if available
                    def commitInfo = env.GIT_COMMIT_MSG ? "\n📌 *Commit:* ${env.GIT_COMMIT_MSG}\n👤 *Author:* ${env.GIT_COMMIT_AUTHOR}" : ""
                    def tgMessage = """
======================================
🚀 *Jenkins Pipeline Update*
======================================
📌 *Project:* ${env.JOB_NAME}
🏷️ *Build No:* #${env.BUILD_NUMBER}
🌿 *Environment:* ${targetEnv}${commitInfo}
${statusEmoji} *Status:* ${buildStatus}
======================================
[📝 Klik untuk melihat log build](${env.BUILD_URL})
                    """

                    withCredentials([string(credentialsId: 'telegram-bot-token', variable: 'TELEGRAM_TOKEN')]) {
                        def chatId = "-1003786747095"
                        sh """
                            curl -s -X POST "https://api.telegram.org/bot${TELEGRAM_TOKEN}/sendMessage" \
                            -d chat_id="${chatId}" \
                            -d parse_mode="Markdown" \
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
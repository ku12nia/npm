pipeline {
    agent any
    // Parameters: Prompts the user to select the target environment (dev, staging, or prod), specify an IMAGE_TAG_TO_PROMOTE when deploying to upper environments, and indicate if the Docker Hub repository is private
    parameters {
        choice(name: 'DEPLOY_ENV', choices: ['dev', 'staging', 'prod'], description: 'Select the target environment for deployment.')
        string(name: 'IMAGE_TAG_TO_PROMOTE', defaultValue: '', description: 'Enter the Image Tag from the stable Dev/Staging environment. Leave blank if env = dev.')
        booleanParam(name: 'IS_PRIVATE_REPO', defaultValue: false, description: 'Check this box if the Docker Hub repository is private.')
    }
    // Options: Uses buildDiscarder with logRotator to keep only the last 10 build logs, preventing the Jenkins server disk from filling up.
    options {
        buildDiscarder(logRotator(numToKeepStr: '10'))
    }
    stages {
        // Stage 0. Setup Build Name: Formats the build number (padding it to two digits) and customizes the build display name in the Jenkins dashboard (e.g., #01 - dev).
        stage('0. Setup Build Name') {
            steps {
                script {
                    env.PADDED_BUILD_NUMBER = String.format("%02d", env.BUILD_NUMBER.toInteger())
                    currentBuild.displayName = "#${env.PADDED_BUILD_NUMBER} - ${params.DEPLOY_ENV}"
                }
            }
        }
        // Stage 1. Checkout Code: Determines the target GitHub branch based on the deployment environment (main for production, or the respective environment name for dev/staging). It also supports a local directory mode if LOCAL_SRC_PATH is configured.
        stage('1. Checkout Code') {
            steps {
                script {
                    def targetBranch = (params.DEPLOY_ENV == 'prod') ? 'main' : params.DEPLOY_ENV
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
                        } catch (Exception e) {
                            echo "❌ Failed to check out code from branch: ${targetBranch}."
                            error("Pipeline stopped because the repository checkout failed: ${e.getMessage()}")
                        }
                    }
                }
            }
        }
        // Stage 2. Test App via Docker: Runs exclusively in the dev environment. It spins up a temporary node:22-alpine container to install dependencies and execute unit tests via Jest, publishing the JUnit XML test results.
        stage('2. Test App via Docker') {
            when {
                environment name: 'DEPLOY_ENV', value: 'dev'
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
        // Stage 3. Approval Gate (Production): Pauses the pipeline for up to 1 hour, requiring manual approval from an administrator before allowing any deployment to proceed to production.
        stage('3. Approval Gate (Production)') {
            when {
                environment name: 'DEPLOY_ENV', value: 'prod'
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
        // Stage 4. Build / Promote & Push Docker Image: For Dev: Pulls the previous dev image for cache reference and For Staging/Prod: Skips building entirely. Instead, it pulls the stable image specified by IMAGE_TAG_TO_PROMOTE
        stage('4. Build / Promote & Push Docker Image') {
            steps {
                script {
                    def targetEnv = params.DEPLOY_ENV
                    def imageRepo = "ku12nia/nodejs" 
                    def newImageTag = "${env.PADDED_BUILD_NUMBER}-${targetEnv}"
                    dir('src') {
                        // For Dev: Pulls the previous dev image for cache reference, builds a new Docker image using BuildKit caching (--cache-from), and pushes it to Docker Hub.
                        if (targetEnv == 'dev') {
                            echo "🔍 Pulling the previous dev image for cache reference."
                            sh "docker pull ${imageRepo}:dev-cache || true"
                            echo "🏗️ Building a new Docker image (using BuildKit cache)."
                            sh "DOCKER_BUILDKIT=1 docker build --cache-from ${imageRepo}:dev-cache --build-arg BUILDKIT_INLINE_CACHE=1 -t ${imageRepo}:${newImageTag} -t ${imageRepo}:dev-cache ."
                        //  For Staging/Prod: Skips building entirely. Instead, it pulls the stable image specified by IMAGE_TAG_TO_PROMOTE, re-tags it for the target environment, and pushes it.             
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
                    //  Environment-Specific Routing:
                    //  If dev: The pipeline pushes an additional dev-cache tag. This acts as a caching reference for Docker BuildKit, which significantly speeds up subsequent image builds in the development environment.
                    //  If prod: The pipeline pushes an additional latest tag. This guarantees that the production repository always has a definitive pointer to the most recent stable release. It also includes error handling to abort if the latest push fails.

                    echo "🔐 Performing automatic authentication to Docker Hub."
                    withCredentials([usernamePassword(credentialsId: 'dockerhub-creds', passwordVariable: 'DOCKER_PASS', usernameVariable: 'DOCKER_USER')]) {
                        try {
                            // Docker Login.
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
                            // Always execute Logout, even if the push fails.
                            sh "docker logout"
                            echo "🔒 Docker logged out successfully. State cleaned."
                        }
                    } 
 
                    // echo "🔐 Performing automatic authentication to Docker Hub."
                    // withCredentials([usernamePassword(credentialsId: 'dockerhub-creds', passwordVariable: 'DOCKER_PASS', usernameVariable: 'DOCKER_USER')]) {
                    //     def loginStatus = sh(
                    //         script: """
                    //             set +x
                    //             echo "\$DOCKER_PASS" | docker login -u "\$DOCKER_USER" --password-stdin
                    //         """, 
                    //         returnStatus: true
                    //     )
                    //     if (loginStatus != 0) {
                    //         error("❌ Failed to log in to Docker Hub! Check the 'dockerhub-creds' credentials.")
                    //     }
                    //     echo "🚀 Pushing image tag: ${newImageTag} ke Docker Hub..."
                    //     def pushStatus = sh(script: "docker push ${imageRepo}:${newImageTag}", returnStatus: true)
                        
                    //     if (pushStatus != 0) {
                    //         error("❌ Failed to push image tag ${newImageTag} to Docker Hub! Pipeline stopped.")
                    //     }
                    //     if (targetEnv == 'dev') {
                    //         echo "🚀 Pushing image cache referensi (dev-cache)."
                    //         sh "docker push ${imageRepo}:dev-cache"
                    //     } else if (targetEnv == 'prod') {
                    //         echo "🚀 Pushing image latest..."
                    //         def pushLatest = sh(script: "docker push ${imageRepo}:latest", returnStatus: true)
                    //         if (pushLatest != 0) {
                    //             error("❌ Failed to push the 'latest' image. Pipeline stopped.")
                    //         }
                    //     }
                    // }

                }
            }
        }
        // Stage 5: Update Manifest & Push to Gi. This stage automates the GitOps workflow by updating your infrastructure repository to point to the newly built Docker image. Update: Replaces the old image tag in the Helm values.yaml file with the new one, Commit & Push: Pushes the updated file to GitHub. It uses [skip ci] in the commit message to prevent Jenkins from triggering another build in an infinite loop, and Cleanup: Removes the Git credentials from the Jenkins server to keep the environment clean (stateless)
        stage('5. Update Manifest & Push ke Git') {
            steps {
                script {
                    def targetEnv = params.DEPLOY_ENV
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
                    // 1. Modify values ​​files using sed
                    sh "sed -i 's/tag: .*/tag: \"${newImageTag}\"/g' ${targetValuesFile}"
                    echo "✅ File ${targetValuesFile} has been successfully updated with tag: ${newImageTag}"
                    // 2. Set up local Git configuration in the Jenkins workspace
                    sh 'git config --global user.email "dedimk.devops@gmail.com"'
                    sh 'git config --global user.name "Dedi Mohammad Kurnia"'
                    // 3. Checking Git status (porcelain returns an empty string if clean)
                    def changes = sh(script: 'git status --porcelain', returnStdout: true).trim()
                    if (changes) {
                        echo "🔍 File changes detected:\n${changes}"
                        echo "⚙️ Performing commit & push process."
                        sh "git add ${targetValuesFile}" 
                        sh "git commit -m 'ci(argocd): update helm image tag for ${targetEnv} to ${newImageTag} [skip ci]'"
                        // 4. Push to GitHub with credentials
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

        // stage('5. Update Manifest & Push ke Git') {
        //     steps {
        //         script {
        //             def targetEnv = params.DEPLOY_ENV
        //             def targetBranch = (targetEnv == 'prod') ? 'main' : targetEnv
        //             def newImageTag = "${env.PADDED_BUILD_NUMBER}-${targetEnv}"
        //             def targetValuesFile = "k8s/helm-chart/values-${targetEnv}.yaml"
                    
        //             echo "✨ Updating ${targetValuesFile} on branch: ${targetBranch}"
        //             sh "sed -i 's/tag: .*/tag: \"${newImageTag}\"/g' ${targetValuesFile}"

        //             echo "✨ Updating ${targetValuesFile} on branch: ${targetBranch}"
        //             sh 'git config --global user.email "dedimk.devops@gmail.com"'
        //             sh 'git config --global user.name "Dedi Mohammad Kurnia"'
        //             def changes = sh(script: 'git status --porcelain', returnStdout: true).trim()
                    
        //             if (changes != "") {
        //                 sh "git add ${targetValuesFile}" // <-- Dynamic git add
        //                 sh "git commit -m 'ci(argocd): update helm image tag for ${targetEnv} to ${newImageTag} [skip ci]'"
                        
        //                 withCredentials([gitUsernamePassword(credentialsId: 'github-creds')]) {
        //                     def gitPushStatus = sh(script: "git push origin HEAD:${targetBranch}", returnStatus: true)
        //                     if (gitPushStatus == 0) {
        //                         echo "🚀 Berhasil push update manifest Helm ke branch GitHub ${targetBranch}!"
        //                     } else {
        //                         unstable("⚠️ WARNING: Gagal push ke GitHub.")
        //                     }
        //                 }
        //             } else {
        //                 echo "⚠️ Tidak ada perubahan pada manifest, melewatkan proses git commit."
        //             }
        //         }
        //     }
        // }

        // Stage 6: Trigger ArgoCD Sync CLI. Setup: Securely logs into ArgoCD and ensures the application is registered to the correct GitHub repo and Kubernetes namespace, Sync: Forces an immediate deployment, bypassing ArgoCD's default 3-minute polling delay, Cleanup: Securely logs out of ArgoCD to destroy the active session token.
        stage('6. Trigger ArgoCD Sync CLI') {
            steps {
                script {
                    def targetEnv = params.DEPLOY_ENV
                    def targetBranch = (targetEnv == 'prod') ? 'main' : targetEnv
                    def appName = "node-app-${targetEnv}" 
                    def namespace = "${targetEnv}-apps" 
                    def targetValuesFile = "values-${targetEnv}.yaml"
                    def argocdServer = "host.docker.internal:80"
                    
                    // withCredentials([usernamePassword(credentialsId: 'argocd-creds', passwordVariable: 'ARGOCD_PASS', usernameVariable: 'ARGOCD_USER')]) {
                    //     sh """
                    //         set +x
                    //         echo "🔐 Logging in to ArgoCD via CLI..."
                    //         argocd login ${argocdServer} --username \$ARGOCD_USER --password \$ARGOCD_PASS --plaintext --grpc-web
                            
                    //         echo "📝 Ensuring application ${appName} is registered..."
                    //         argocd app create ${appName} \
                    //           --repo https://github.com/ku12nia/npm.git \
                    //           --path k8s/helm-chart \
                    //           --revision ${targetBranch} \
                    //           --values ${targetValuesFile} \
                    //           --dest-server https://kubernetes.default.svc \
                    //           --dest-namespace ${namespace} \
                    //           --sync-option CreateNamespace=true \
                    //           --sync-option Replace=true \
                    //           --upsert
                            
                    //         echo "🚀 Syncing application: ${appName}..."
                    //         argocd app sync ${appName} --replace
                    //     """
                    // }
                    // echo "🔄 ArgoCD synchronization was successful for ${appName}!"

                    withCredentials([usernamePassword(credentialsId: 'argocd-creds', passwordVariable: 'ARGOCD_PASS', usernameVariable: 'ARGOCD_USER')]) {
                        try {
                            sh """
                                set +x
                                echo "🔐 Logging in to ArgoCD via CLI..."
                                argocd login ${argocdServer} --username \$ARGOCD_USER --password \$ARGOCD_PASS --plaintext --grpc-web
                                
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
                            // Pastikan Logout setelah sync atau jika terjadi error
                            sh "argocd logout ${argocdServer} || true"
                            echo "🔒 ArgoCD logged out successfully. State cleaned."
                        }
                    }
                }
            }
        }
        // NEXT STAGE
    }    
    post {
        always {
            script {
                // 1. Cleaning the Workspace (State Clean)
                try {
                    echo "🧹 Cleaning up the workspace to prevent the server disk from becoming full."
                    // cleanWs()
                    // echo "✨ Workspace cleaned successfully."
                } catch (Exception e) {
                    echo "⚠️ Cleanup was skipped because the workspace was not ready."
                }
            }

            // 2. Sending Telegram Notifications
            script {
                try {
                    echo "📱 Sending notification to Telegram..."

                    def buildStatus = currentBuild.currentResult ?: 'SUCCESS'
                    def statusEmoji = (buildStatus == 'SUCCESS') ? '✅' : '❌'
                    def targetEnv = params.DEPLOY_ENV ?: 'N/A'
                    
                    def tgMessage = """
${statusEmoji} *Jenkins Pipeline Update* ${statusEmoji}

*Project:* ${env.JOB_NAME}
*Build No:* #${env.BUILD_NUMBER}
*Environment:* ${targetEnv}
*Status:* ${buildStatus}

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
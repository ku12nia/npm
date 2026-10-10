pipeline {
    agent any
    
    parameters {
        choice(name: 'DEPLOY_ENV', choices: ['dev', 'staging', 'prod'], description: 'Select the target environment for deployment.')
        booleanParam(name: 'IS_PRIVATE_REPO', defaultValue: false, description: 'Check this box if the Docker Hub repository is private.')
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
        
        stage('1. Checkout code or Directly mounted to workspace') {
            steps {
                script {
                    def targetBranch = (params.DEPLOY_ENV == 'prod') ? 'main' : params.DEPLOY_ENV
                    
                    if (env.LOCAL_SRC_PATH) {
                        echo "💻 Local Directory Mode Active!"
                        if (!fileExists('Jenkinsfile')) {
                            error("❌ The workspace is empty! Make sure you have cloned the repo into the Windows host folder.")
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
                            echo "✅ Successfully checked out from the branch: ${targetBranch}."
                        } catch (Exception e) {
                            echo "❌ Failed to check out code from the branch: ${targetBranch}."
                            echo "Reason: ${e.getMessage()}"
                            error("The pipeline was stopped because the repository checkout failed.")
                        }
                    }
                }
            }
        }
        
        // stage('2. Docker Preparation & Test App') {
        //     steps {
        //         script {
        //             def hasDocker = sh(script: 'command -v docker', returnStatus: true) == 0
        //             if (!hasDocker) {
        //                 echo "⚙️ Docker is not present. Downloading Docker CLI."
        //                 sh 'curl -sSL -o docker.tgz https://download.docker.com/linux/static/stable/x86_64/docker-24.0.9.tgz'
        //                 sh 'tar -xzf docker.tgz'
        //                 sh 'mv docker/docker /usr/bin/docker'
        //                 sh 'chmod +x /usr/bin/docker'
        //                 sh 'rm -rf docker docker.tgz'
        //                 echo "✅ Docker CLI successfully installed!"
        //             }

        //             def hasBuildx = sh(script: 'docker buildx version', returnStatus: true) == 0
        //             if (!hasBuildx) {
        //                 echo "⚙️ The Buildx plugin is not yet installed. Downloading Buildx."
        //                 sh 'mkdir -p ~/.docker/cli-plugins'
        //                 sh 'curl -sSL -o ~/.docker/cli-plugins/docker-buildx https://github.com/docker/buildx/releases/download/v0.14.0/buildx-v0.14.0.linux-amd64'
        //                 sh 'chmod +x ~/.docker/cli-plugins/docker-buildx'
        //                 echo "✅ Docker Buildx has been successfully installed!"
        //             }

        //             def containerId = sh(script: 'hostname', returnStdout: true).trim()
        //             echo "ℹ️ Jenkins is running in container ID: ${containerId}"

        //             echo "🛠️ Running Unit Tests via Docker."
                    
        //             dir('src') {
        //                 sh """
        //                 docker run --rm --volumes-from ${containerId} -w \${WORKSPACE}/src node:22-alpine sh -c "\
        //                     sed -i '1s/^\\\\xEF\\\\xBB\\\\xBF//' package.json && \
        //                     npm install && \
        //                     npm install --save-dev jest jest-junit && \
        //                     npx jest --ci --coverage --reporters=default --reporters=jest-junit --passWithNoTests \
        //                 "
        //                 """
        //             }
        //             echo "✅ Unit Test Passed."
        //         }
        //     }
        //     post {
        //         success {
        //             script {
        //                 def junitFile = 'src/junit.xml'
        //                 if (fileExists(junitFile)) {
        //                     try {
        //                         junit junitFile
        //                         echo "✅ JUnit test report recorded successfully."
        //                     } catch (Exception e) {
        //                         echo "⚠️ JUnit report found but empty or invalid, skipping..."
        //                     }
        //                 } else {
        //                     echo "⚠️ No JUnit report found, skipping..."
        //                 }
        //             }
        //         }
        //     }
        // }

        stage('2. Test App via Docker') {
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
                            try { junit 'src/junit.xml' } catch (e) { echo "⚠️ Invalid JUnit report, skipping..." }
                        }
                    }
                }
            }
        }

        stage('3. Build & Push Docker Image') {
            steps {
                script {
                    def targetEnv = params.DEPLOY_ENV
                    def imageRepo = "ku12nia/nodejs" 
                    def imageTag = "${env.BUILD_NUMBER}-${targetEnv}"
                    
                    echo "🏗️ Building Docker image for: ${targetEnv}"
                    dir('src') {
                        sh "DOCKER_BUILDKIT=1 docker build -t ${imageRepo}:${imageTag} ."            
                        if (targetEnv == 'prod') {
                            sh "docker tag ${imageRepo}:${imageTag} ${imageRepo}:latest"
                        }
                    }
                    echo "🔐 Perform automatic authentication to Docker Hub."
                    withCredentials([usernamePassword(credentialsId: 'dockerhub-creds', passwordVariable: 'DOCKER_PASS', usernameVariable: 'DOCKER_USER')]) {
                        def loginStatus = sh(
                            script: """
                                set +x
                                echo "\$DOCKER_PASS" | docker login -u "\$DOCKER_USER" --password-stdin
                            """, 
                            returnStatus: true
                        )
                        
                        // Guard Clause
                        if (loginStatus != 0) {
                            error("❌ Failed to log in to Docker Hub! Check the 'dockerhub-creds' credentials in the Jenkins settings.")
                        }
                        echo "✅ Automatic login successful!"
                        
                        // Push Image
                        echo "🚀 Pushing the image to Docker Hub."
                        def pushStatus = sh(script: "docker push ${imageRepo}:${imageTag}", returnStatus: true)
                        
                        if (pushStatus != 0) {
                            error("❌ Failed to push image tag ${imageTag} ke Docker Hub! Pipeline dihentikan.")
                        }
                        echo "✅ Push successfull ${imageRepo}:${imageTag}"
                        
                        // Push Image Latest (Khusus Prod)
                        if (targetEnv == 'prod') {
                            def pushLatest = sh(script: "docker push ${imageRepo}:latest", returnStatus: true)
                            if (pushLatest != 0) {
                                error("❌ Failed to push image with 'latest' tag. Pipeline stopped.")
                            }
                            echo "✅ Push successfull ${imageRepo}:latest"
                        }
                    } // End withCredentials
                }
            }
        }
        
        stage('4. Update Manifest & Push ke Git') {
            steps {
                script {
                    def imageTag = "${env.BUILD_NUMBER}-${params.DEPLOY_ENV}"
                    def targetBranch = (params.DEPLOY_ENV == 'prod') ? 'main' : params.DEPLOY_ENV
                    
                    echo "✨ Updating the Helm values.yaml in the branch: ${targetBranch}"
                    
                    sh "sed -i 's/tag: .*/tag: \"${imageTag}\"/g' k8s/node-app-chart/values.yaml"
                    
                    sh 'git config --global user.email "dedimk.devops@gmail.com"'
                    sh 'git config --global user.name "Dedi Mohammad Kurnia"'
                    
                    def changes = sh(script: 'git status --porcelain', returnStdout: true).trim()
                    
                    if (changes != "") {
                        // sh "git add k8s/app-deployment.yaml"
                        sh "git add k8s/node-app-chart/values.yaml"
                        sh "git commit -m 'ci(argocd): update helm image tag to ${imageTag} [skip ci]'"
                        
                        withCredentials([gitUsernamePassword(credentialsId: 'github-creds')]) {
                            def gitPushStatus = sh(script: "git push origin HEAD:${targetBranch}", returnStatus: true)
                            if (gitPushStatus == 0) {
                                echo "🚀 Successfully pushed the Helm manifest update to the GitHub branch. ${targetBranch}!"
                            } else {
                                echo "⚠️ WARNING: Failed to push to GitHub."
                                unstable("GitHub Push Failed")
                            }
                        }
                    } else {
                        echo "⚠️ No changes to the manifest; skip git commit."
                    }
                }
            }
        }

        stage('5. Trigger ArgoCD Sync') {
            steps {
                script {
                    def targetBranch = (params.DEPLOY_ENV == 'prod') ? 'main' : params.DEPLOY_ENV
                    def appName = "node-app-${params.DEPLOY_ENV}" 
                    def namespace = "${params.DEPLOY_ENV}-apps" 
                    def argocdServer = "host.docker.internal:8081"
                    
                    withCredentials([usernamePassword(credentialsId: 'argocd-creds', passwordVariable: 'ARGOCD_PASS', usernameVariable: 'ARGOCD_USER')]) {
                        sh """
                            set +x
                            argocd login ${argocdServer} --username \$ARGOCD_USER --password \$ARGOCD_PASS --insecure
                            argocd app create ${appName} --repo https://github.com/ku12nia/npm.git --path k8s/node-app-chart --revision ${targetBranch} --dest-server https://kubernetes.default.svc --dest-namespace ${namespace} --sync-policy automated --upsert
                            argocd app sync ${appName}
                        """
                    }
                    echo "🔄 App synchronization successful for ${appName}!"
                }
            }
        }

        // stage('5. Trigger Sync ArgoCD') {
        //     steps {
        //         script {
        //             sh 'curl -sSL -o argocd https://github.com/argoproj/argo-cd/releases/latest/download/argocd-linux-amd64 && chmod +x argocd'
                    
        //             def hasArgocd = sh(script: 'test -x ./argocd', returnStatus: true) == 0
        //             if (hasArgocd) {
        //                 def argocdServer = "host.docker.internal:8081"
        //                 def targetBranch = (params.DEPLOY_ENV == 'prod') ? 'main' : params.DEPLOY_ENV
        //                 def appName = "node-app-${params.DEPLOY_ENV}" 
        //                 def namespace = "${params.DEPLOY_ENV}-apps" 
                        
        //                 withCredentials([usernamePassword(credentialsId: 'argocd-creds', passwordVariable: 'ARGOCD_PASS', usernameVariable: 'ARGOCD_USER')]) {
        //                     def argoLoginStatus = sh(
        //                         script: """
        //                             set +x
        //                             ./argocd login ${argocdServer} --username \$ARGOCD_USER --password \$ARGOCD_PASS --insecure
        //                         """, 
        //                         returnStatus: true
        //                     )
                            
        //                     if (argoLoginStatus == 0) {
        //                         sh "./argocd app create ${appName} --repo https://github.com/ku12nia/npm.git --path k8s/node-app-chart --revision ${targetBranch} --dest-server https://kubernetes.default.svc --dest-namespace ${namespace} --sync-policy automated --upsert"
        //                         sh "./argocd app sync ${appName}"
                                
        //                         echo "🔄 App synchronization successful ${appName} to ArgoCD monitoring the branch ${targetBranch}."
        //                     } else {
        //                         echo "⚠️ WARNING: Failed to connect to the ArgoCD server. CLI synchronization skipped."
        //                         unstable("ArgoCD Login Failed")
        //                     }
        //                 }
        //             } else {
        //                 echo "⚠️ The 'argocd' command was not found. Stage skipped."
        //             }
        //         }
        //     }
        // }
// Next Stage
    }    
    post {
        always {
            script {
                try {
                    echo "🧹 Cleaning up the workspace to fix the full disk on the server."
                    sh 'rm -rf node_modules coverage junit.xml docker.tgz docker'
                    echo "✨ The workspace is sparkling clean again!"
                } catch (Exception e) {
                    echo "⚠️ Cleanup was skipped because the workspace was not ready or initialized."
                }
            }
        }
    }
}

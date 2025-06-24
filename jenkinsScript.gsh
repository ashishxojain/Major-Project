def pipelineType = '' // shared pipeline-level variable

pipeline {
    agent any

    environment {
        SCANNER_HOME = tool 'sonar-scanner'
        DOCKER_CRED = 'docker-cred'
        GIT_CRED = 'git-cred'
        SONAR_NAME = 'sonar'
    }

    tools {
        maven 'maven3'
        jdk 'jdk17'
        
    }

    stages {
        stage('Clean Workspace') {
            steps {
                deleteDir()
            }
        }

        stage('Git Checkout') {
            steps {
                git branch: 'master', credentialsId: env.GIT_CRED, url: 'https://github.com/ashishxojain/python-app.git'
                
                // git branch: 'master', credentialsId: env.GIT_CRED, url: 'https://github.com/ashishxojain/docker-maven-repo.git'
                // git branch: 'main', credentialsId: env.GIT_CRED, url: 'https://github.com/ashishxojain/3-Tier-Full-Stack.git'


            }
        }

        stage('Detect Project Type') {
            steps {
                script {
                    if (fileExists('package.json')) {
                        pipelineType = 'node'
                    } else if (fileExists('pom.xml')) {
                        pipelineType = 'java'
                    } else if (fileExists('requirements.txt')) {
                        pipelineType = 'python'
                    } else {
                        error "No recognizable project files (package.json, pom.xml, requirements.txt) found."
                    }
                    echo "Detected project type: ${pipelineType}"
                }
            }
        }

        stage('Node.js Pipeline') {
            when { expression { return pipelineType == 'node' } }
            stages {
                stage('Install Dependencies') {
                    steps { sh "npm install" }
                }
                stage('Unit Tests') {
                    steps { sh "npm test" }
                }
                stage('File System Scan') {
                    steps { sh "trivy fs --format table -o nodejs-fs-report.html ." }
                }
                stage('SonarQube Analysis') {
                    steps {
                        withSonarQubeEnv(env.SONAR_NAME) {
                            sh "${env.SCANNER_HOME}/bin/sonar-scanner -Dsonar.projectKey=NodeProject -Dsonar.projectName=NodeProject"
                        }
                    }
                }
                stage('Docker Build') {
                    steps {
                        sh "docker build -t ashishjjain/node-app:latest ."
                    }
                }
                stage('Image Scan') {
                    steps {
                        sh "trivy image --format table -o node-image-report.html ashishjjain/node-app:latest"
                    }
                }
                stage('Docker Push') {
                    steps {
                        script {
                            withDockerRegistry(credentialsId: env.DOCKER_CRED, toolName: 'docker') {
                                sh "docker push ashishjjain/node-app:latest"
                            }
                        }
                    }
                }
            }
        }

        stage('Java Maven Pipeline') {
            when { expression { return pipelineType == 'java' } }
            stages {
                stage('Compile') {
                    steps { sh "mvn compile" }
                }
                stage('Tests') {
                    steps { sh "mvn test" }
                }
                stage('File System Scan') {
                    steps { sh "trivy fs --scanners vuln --format table -o maven-fs-report.html ." }
                }
                stage('SonarQube Analysis') {
                    steps {
                        withSonarQubeEnv(env.SONAR_NAME) {
                            sh "${env.SCANNER_HOME}/bin/sonar-scanner -Dsonar.projectKey=JavaProject -Dsonar.projectName=JavaProject -Dsonar.java.binaries=."
                        }
                    }
                }
                stage('Package') {
                    steps {
                        sh "mvn package"
                    }
                }
                stage('Docker Build') {
                    steps {
                        sh "docker build -t ashishjjain/java-app:latest ."
                    }
                }
                stage('Image Scan') {
                    steps {
                        sh "trivy image --format table -o java-image-report.html ashishjjain/java-app:latest"
                    }
                }
                stage('Docker Push') {
                    steps {
                        script {
                            withDockerRegistry(credentialsId: env.DOCKER_CRED, toolName: 'docker') {
                                sh "docker push ashishjjain/java-app:latest"
                            }
                        }
                    }
                }
            }
        }

        stage('Python Pipeline') {
            when { expression { return pipelineType == 'python' } }
            stages {
                stage('Install Dependencies') {
                    steps {
                        script {
                            // Use system Python (python3) to install dependencies
                            sh 'pip install --break-system-packages -r requirements.txt'
                        }
                    }
                }
                stage('Unit Tests') {
                    steps {
                        script {
                            // Run unit tests with system Python (python3)
                            sh 'python3 -m pytest || true'
                        }
                    }
                }
                stage('File System Scan') {
                    steps {
                        sh "trivy fs --format table -o python-fs-report.html ."
                    }
                }
                stage('SonarQube Analysis') {
                    steps {
                        script {
                            // Run SonarQube analysis for Python project
                            withSonarQubeEnv(env.SONAR_NAME) {
                                sh "${env.SCANNER_HOME}/bin/sonar-scanner -Dsonar.projectKey=PythonProject -Dsonar.projectName=PythonProject -Dsonar.sources=."
                            }
                        }
                    }
                }
                stage('Docker Build') {
                    steps {
                        sh "docker build -t ashishjjain/python-app:latest ."
                    }
                }
                stage('Image Scan') {
                    steps {
                        sh "trivy image --format table -o python-image-report.html ashishjjain/python-app:latest"
                    }
                }
                stage('Docker Push') {
                    steps {
                        script {
                            withDockerRegistry(credentialsId: env.DOCKER_CRED, toolName: 'docker') {
                                sh "docker push ashishjjain/python-app:latest"
                            }
                        }
                    }
                }
            }
        }

        stage('Completion') {
            steps {
                echo 'Pipeline execution completed.'
            }
        }
    }

    post {
        always {
            emailext(
                subject: "Pipeline Notification: Build #${BUILD_NUMBER} - ${currentBuild.currentResult}",
                body: """<html>
                            <head>
                                <style>
                                    body { font-family: Arial, sans-serif; background-color: #f9f9f9; color: #333; }
                                    .container { background-color: #fff; padding: 20px; border-radius: 8px; box-shadow: 0 2px 4px rgba(0,0,0,0.1); }
                                    .header { font-size: 20px; font-weight: bold; margin-bottom: 10px; }
                                    .status {
                                        display: inline-block;
                                        padding: 5px 10px;
                                        border-radius: 4px;
                                        color: #fff;
                                        background-color: ${currentBuild.currentResult == 'SUCCESS' ? '#4CAF50' : (currentBuild.currentResult == 'FAILURE' ? '#F44336' : '#FFC107')};
                                    }
                                    .details { margin-top: 10px; }
                                    .details p { margin: 5px 0; }
                                    .footer { margin-top: 20px; font-size: 12px; color: #777; }
                                </style>
                            </head>
                            <body>
                                <div class="container">
                                    <div class="header">Jenkins Pipeline Notification</div>
                                    <p>Build Status: <span class="status">${currentBuild.currentResult}</span></p>
                                    <div class="details">
                                        <p><strong>Job Name:</strong> ${env.JOB_NAME}</p>
                                        <p><strong>Build Number:</strong> ${env.BUILD_NUMBER}</p>
                                        <p><strong>Build URL:</strong> <a href="${env.BUILD_URL}">${env.BUILD_URL}</a></p>
                                        <p><strong>Build Time:</strong> ${new Date()}</p>
                                        <p><strong>Pipeline Type:</strong> ${pipelineType}</p>
                                    </div>
                                    <div class="footer">
                                        This is an automated email from Jenkins. Please do not reply.
                                    </div>
                                </div>
                            </body>
                        </html>""",
                to: 'ashish.jain124@yahoo.com',
                from: 'jenkins@example.com',
                replyTo: 'jenkins@example.com',
                mimeType: 'text/html'
            )
        }
    }
}


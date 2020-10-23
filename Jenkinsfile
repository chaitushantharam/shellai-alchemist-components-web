// Constants
DEPLOYER_IMAGE = 'shellai.azurecr.io/shellai-deployer:0.5.0'
OWNER = 'alchemist'
NAMESPACE = 'alchemist'
TEMPLATED_FILE = 'templated.yaml'
CHART_PATH = './charts/'
COMPONENT = 'alchemist-web'
TASK_COMPONENT = 'alchemist-task'
CHART_NAME = COMPONENT
LOCATIONS = ShellAi.locations()
ENVIRONMENTS = ShellAi.environments()
OPERATIONS = ['upgrade', 'rollback', 'delete']
SHELLAI_SHARED_LIB_TAG = 'stable'
CONTAINER_NAME = deployerContainerName()
DEPLOYMENT_ID = ''

pipeline {
    options {
        disableConcurrentBuilds()
    }
    agent {
        kubernetes {
            label deployerContainerName()
            defaultContainer 'jnlp'
            yaml shellaiDeployerYaml(CONTAINER_NAME, DEPLOYER_IMAGE)
        }
    }
    parameters {
        choice(
                name: 'LOCATION',
                choices: LOCATIONS,
                description: 'Location to deploy to'
        )
        choice(
                name: 'ENVIRONMENT',
                choices: ENVIRONMENTS,
                description: 'Environment to deploy to'
        )
        choice(
                name: 'OPERATION',
                choices: OPERATIONS,
                description: 'Operation type (use upgrade for install operations)'
        )
        string(
                name: 'REVISION',
                defaultValue: '0',
                description: 'deployment revision to rollback to (leaving it as zero means rollback to previous revision)'
        )
        string(
                name: 'IMAGE_TAG',
                defaultValue: '',
                description: 'Image tag to override. Can be used in CD to dev environment'
        )

        booleanParam(
                name: 'APPROVAL_GATE',
                defaultValue: true,
                description: 'APPROVAL for Component deployment'
        )
    }

    stages {
        stage('Prepare') {
            steps {
                setKubeconfig(CONTAINER_NAME)
                addGitCredentials(CONTAINER_NAME)
                container(CONTAINER_NAME) {
                    sh "git clone -b ${SHELLAI_SHARED_LIB_TAG} --single-branch https://github.com/shellagilehub/shellai-jenkins-shared-lib"
                }
            }
        }

        stage('PlanEnv') {
            steps {
                container(CONTAINER_NAME) {
                    script {
                        String helmOverrides = generateHelmOverrides()
                        template(helmOverrides)
                    }
                }
            }
        }

        stage('Audit Deployment Manifest') {
            when {
                expression {
                    return false
                }
            }
            steps {
                script {
                    echo "[WARNING]: Manifest Audit is disabled"
                    // auditManifestWithPolaris("./finalcharts/${COMPONENT}", CONTAINER_NAME)
                }
            }
        }

        stage('DeployEnv') {
            when { not { buildingTag() } }
            steps {
                container(CONTAINER_NAME) {
                    script {
                        deploy()
                    }
                }
            }
        }
    }
}

def deploy() {
    script {
        echo "APPROVAL_GATE:$APPROVAL_GATE"
        if (APPROVAL_GATE && (APPROVAL_GATE == true || APPROVAL_GATE == "true")) {
            approvalPrompt("Deploy to ${LOCATION}/${ENVIRONMENT}?")
        } else {
            echo "Skipping approval step..."
        }
    }

    container(CONTAINER_NAME) {

        createOrDeleteK8sSecret()

        sh """
            ./shellai-jenkins-shared-lib/utilities/helm_deploy.py \
            --namespace ${NAMESPACE} \
            --chartName ${COMPONENT} \
            --chartPath "./finalcharts/${COMPONENT}" \
            --operation ${OPERATION} \
            --revision ${REVISION}
        """

        checkDeployment()
    }
}

def template(String helmOverrides) {

    container(CONTAINER_NAME) {

        echo "helm overrides: " + helmOverrides

        sh """

            echo "[INFO] Helm Version:"
            helm version

            ./shellai-jenkins-shared-lib/utilities/generate_manifest.py \
            --template "./templates/${COMPONENT}-values.yaml.jinja2" \
            --data "values_data.yaml" \
            --setkeys "${helmOverrides}" \
            --location "${LOCATION}" \
            --environment "${ENVIRONMENT}" \
            --chartName "${CHART_NAME}" \
            --chartsPath "${CHART_PATH}" \
            --namespace "${NAMESPACE}" \
            --component "${COMPONENT}" \
            --costcenter "none" \
            --owner "${OWNER}" \
            --createdBy "helm" \
            --outfile ${ENVIRONMENT}_${TEMPLATED_FILE}
            
            kubectl config use-context "shellai-${LOCATION}-${ENVIRONMENT}"

            ./shellai-jenkins-shared-lib/utilities/helm_deploy.py \
            --namespace ${NAMESPACE} \
            --chartName ${CHART_NAME} \
            --chartPath "./finalcharts/${CHART_NAME}" \
            --operation ${OPERATION} \
            --revision ${REVISION} \
            --dryRun true
        """
    }
}

def checkDeployment() {
    if (OPERATION != 'delete') {
        sh """
            chmod +x ./deploymentCheck.sh
            ./deploymentCheck.sh --namespace="${NAMESPACE}" --componentname="${COMPONENT}"
            
            chmod +x ./removePreviousRevisions.sh
            ./removePreviousRevisions.sh --namespace="${NAMESPACE}" --componentname="${TASK_COMPONENT}" --deploymentid="${DEPLOYMENT_ID}"
        """
    }
}

def generateHelmOverrides() {

    def overrides = []
    container(CONTAINER_NAME) {
        script {
            echo "IMAGE_TAG: |${IMAGE_TAG}|"
            if (!['', null, 'null'].contains(IMAGE_TAG)) {
                overrides.add("image.tag=${IMAGE_TAG}")
            } else {
                IMAGE_TAG = shWithReturnValue(""" 
                                grep -m1 "tag:" ./templates/${COMPONENT}-values.yaml.jinja2 | awk -F":" '{ print \$2 }'| xargs
                            """).trim().replace("\"", "")
            }

            SHORTENED_IMAGE_TAG = shWithReturnValue("echo ${IMAGE_TAG}").take(12)
            DEPLOYMENT_ID = dnsify("${SHORTENED_IMAGE_TAG}-bld${env.BUILD_NUMBER}")
            overrides.add("config.deploymentId=${DEPLOYMENT_ID}")

            def createdTimestamp = shWithReturnValue("""echo \$(date +\"%Y-%m-%d_%H-%M-%S\")""")
            overrides.add("config.deploymentTimestamp=${createdTimestamp}")
        }
    }

    return overrides.join(",")
}

def createOrDeleteK8sSecret() {

    if (OPERATION == 'delete') {
        cmd = """./createOrDeleteK8sSecret.sh --delete --namespace="${NAMESPACE}" --keyvaultName="${keyVaultName}" """
    } else {
        cmd = """./createOrDeleteK8sSecret.sh --create --namespace="${NAMESPACE}" --keyvaultName="${keyVaultName}" """
    }

    withCredentials([azureServicePrincipal("sp-${LOCATION}-${ENVIRONMENT}")]) {
        keyVaultName = getKeyVaultName()
        sh """
            set +x
            kubectl config use-context "shellai-${LOCATION}-${ENVIRONMENT}"
            az login --service-principal --username=${AZURE_CLIENT_ID} --password=${AZURE_CLIENT_SECRET} --tenant=${AZURE_TENANT_ID} > /dev/null
            ${cmd}
        """
    }
}

def dnsify(String aValue) {
    return aValue.replaceAll("[^A-Za-z0-9]", '-')
}

def getKeyVaultName() {
    if (LOCATION.length() >= 7)
        SHORT_LOCATION = LOCATION.substring(0, 7)
    else
        SHORT_LOCATION = LOCATION
    if (ENVIRONMENT.length() >= 9)
        SHORT_ENVIRONMENT = ENVIRONMENT.substring(0, 9)
    else
        SHORT_ENVIRONMENT = ENVIRONMENT
    if (NAMESPACE.length() >= 6)
        SHORT_TEAM = NAMESPACE.substring(0, 6)
    else
        SHORT_TEAM = NAMESPACE
    KEYVAULT_NAME = "${SHORT_LOCATION}${SHORT_ENVIRONMENT}${SHORT_TEAM}kv"
    return KEYVAULT_NAME
}
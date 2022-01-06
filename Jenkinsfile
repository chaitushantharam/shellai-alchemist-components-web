// this file helps to use AKS cluster (note: the previous one is now renamed to kubespray_jenkinsfile)
// TODO: can we use application user's handle rather than personal handle??
 
// Applicable shared libraries 
@Library(value="shellai-jenkins-shared-lib@master", changelog=true)
import com.shell.shellai.enums.ShellAiEnvironment
import static com.shell.shellai.CommonUtils.*

// Constants
DEPLOYER_IMAGE = 'shellai.azurecr.io/shellai-deployer:0.6.1'
OWNER = 'alchemist'
NAMESPACE = 'alchemist'
TEMPLATED_FILE = 'templated.yaml'
CHART_PATH = './charts/'
COMPONENT = 'alchemist-web'
TASK_COMPONENT = 'alchemist-task'
CHART_NAME = COMPONENT
LOCATION = 'westeurope'
ENVIRONMENT = 'dev'
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
                choices: LOCATION,
                description: 'Location to deploy to'
        )
        choice(
                name: 'ENVIRONMENT',
                choices: ENVIRONMENT,
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
                script {
                    aksLogin(CONTAINER_NAME)
                    addGitCredentials(CONTAINER_NAME)
                    container(CONTAINER_NAME) {
                        sh """
                            git clone -b ${SHELLAI_SHARED_LIB_TAG} -c advice.detachedHead=false  https://github.com/shellagilehub/shellai-jenkins-shared-lib
                        """
                    }

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

            echo "templated..."
            cat dev_templated.yaml
            
            kubectl config use-context "${LOCATION}-${ENVIRONMENT}"

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

// ONLY CHECKS WEB AND NOT KNATIVE
def checkDeployment() {
    if (OPERATION != 'delete') {
        sh """
            chmod +x ./deploymentCheck.sh
            ./deploymentCheck.sh --namespace="${NAMESPACE}" --componentname="${COMPONENT}"
        """
    }
}
// DO NOT DELETE THE FOLLOWING.  CHECK FOR KNATIVE SERVICE IS CURRENTLY GIVING AN ISSUE DUE TO HUGE DOCKER SIZE AND KNATIVE IS NOT CURRENTLY BEING USED
// def checkDeployment() {
//     if (OPERATION != 'delete') {
//         sh """
//             chmod +x ./deploymentCheck.sh
//             ./deploymentCheck.sh --namespace="${NAMESPACE}" --componentname="${COMPONENT}"
//
//             chmod +x ./removePreviousRevisions.sh
//             ./removePreviousRevisions.sh --namespace="${NAMESPACE}" --componentname="${TASK_COMPONENT}" --deploymentid="${DEPLOYMENT_ID}"
//         """
//     }
// }
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

    beagileAzcli.azLogin(LOCATION, ENVIRONMENT)

    keyVaultName = getKeyVaultName()
    echo "keykeykey"
    echo keyVaultName

    sh """
        set +x
        kubectl config use-context "shellai-${LOCATION}-${ENVIRONMENT}"
        ${cmd}
    """
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

// [note copied from https://github.com/sede-x/be.agile/blob/master/docs/aks-migration-guide/python-flask-app/README.md and 
// https://github.com/shellagilehub/beagile-examples-python-flask-app/blob/master/Jenkinsfile]
// NOTE: This function will eventually be copied to Frontera release management v2 https://github.com/sede-x/beagile-frontera-release-management-jsl
def aksLogin(String containerName) {
    ShellAiEnvironment environmentInfo = ShellAi.environmentInfo(ENVIRONMENT)

    container(containerName) {
        withCredentials([sshUserPrivateKey(
            credentialsId: "sp-${LOCATION}-${ENVIRONMENT}-pem",
            keyFileVariable: 'AZ_PASSWORD',
            usernameVariable: 'AZ_USERNAME'
        )]) {
        sh """
        echo "[Info] Performing AZ login"
        az login --service-principal -u ${AZ_USERNAME} -p ${AZ_PASSWORD} --tenant ${environmentInfo.tenantId}
        echo "[Info] Changing AZ subscription"
        az account set --subscription ${environmentInfo.subscriptionId}
        echo "[Info] Retrieving Kubeconfig"
        az aks get-credentials --resource-group ${LOCATION}-${ENVIRONMENT}-platform-aks-rg --name ${LOCATION}-${ENVIRONMENT} --context ${LOCATION}-${ENVIRONMENT} --overwrite-existing
        kubectl config get-contexts
        """
        }
    }
}
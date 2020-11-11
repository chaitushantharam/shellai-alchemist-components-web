#!/usr/bin/env bash

set -o errexit          # Exit on most errors (see the manual)
set -o errtrace         # Make sure any error trap is inherited
set -o nounset          # Disallow expansion of unset variables
set -o pipefail         # Use last non-zero exit code in a pipeline
#set -o xtrace          # Trace the execution of the script (debug)


SECRET_NAME="alchemist-web"


# DESC: Usage help
# ARGS: None
# OUTS: None
function script_usage() {
    cat << EOF
Usage:
     -h|--help                  Displays this help
     -c|--create                Create the secret
     -d|--delete                Delete the secret
     -n|--namespace             [REQUIRED] kubernetes namespace to be used (e.g. platform, vadr)
     -k|--keyvaultName          [REQUIRED] keyvault name
EOF
}

# DESC: Parameter parser
# ARGS: $@ (optional): Arguments provided to the script
# OUTS: Variables indicating command-line parameters and options
function parse_params() {
    local param
    while [[ $# -gt 0 ]]; do
        param="$1"
        shift
        case $param in
            -h|--help)
                script_usage
                exit 0
                ;;
            -d|--delete)
                DELETE_SECRET=true
                CREATE_SECRET=false
                ;;
            -c|--create)
                CREATE_SECRET=true
                DELETE_SECRET=false
                ;;
            -n=*|--namespace=*)
                NAMESPACE="${param#*=}"
                ;;
            -k=*|--keyvaultName=*)
                KEY_VAULT_NAME="${param#*=}"
                ;;
            *)
                script_exit "Invalid parameter was provided: $param" 2
                ;;
        esac
    done

    if [ -z ${NAMESPACE-} ] ; then
        script_usage
        script_exit "no namespace provided" 2
    fi

    if [ -z ${KEY_VAULT_NAME-} ] ; then
        script_usage
        script_exit "no keyvault name provided" 2
    fi
}

function delete_secret() {
    if [[ -n ${DELETE_SECRET-} ]]; then
        if [ "$(kubectl -n ${NAMESPACE} get secret ${SECRET_NAME} 2> /dev/null)" ] ; then
            pretty_print "Deleting secret..."
            kubectl -n ${NAMESPACE} delete secret ${SECRET_NAME}
        fi
    fi
}

function get_secret_from_keyvault() {
    secretValue=$(az keyvault secret show --vault-name "${KEY_VAULT_NAME}" --name "$1"  -ojson| jq -r ".value")
    echo $secretValue
}

function create_secret() {
    pretty_print "Creating secret..."

# make sure the key is the same as the environment variable in the code

    kubectl create secret generic "${SECRET_NAME}" \
        --namespace ${NAMESPACE} \
        --from-literal AAD_APP_CLIENT_ID=$(get_secret_from_keyvault "AADAPPCLIENTID") \
        --from-literal AAD_APP_CLIENT_ID_2=$(get_secret_from_keyvault "AADAPPCLIENTID2") \
        --from-literal AAD_APP_CLIENT_SECRET=$(get_secret_from_keyvault "AADAPPCLIENTSECRET") \
        --from-literal AAD_APP_CLIENT_SECRET_2=$(get_secret_from_keyvault "AADAPPCLIENTSECRET2") \
        --from-literal azure_client_secret=$(get_secret_from_keyvault "azureclientsecret") \
        --from-literal azure_tenant_id=$(get_secret_from_keyvault "azuretenantid") \
        --from-literal azure_client_secret_mahs=$(get_secret_from_keyvault "azureclientsecretmahs") \
        --from-literal azure_tenant_id_mahs=$(get_secret_from_keyvault "azuretenantidmahs") \
        --from-literal AZURE_CLIENT_ID_MAHS=$(get_secret_from_keyvault "AZURECLIENTIDMAHS") \
        --from-literal AZURE_DATALAKE_DEV_MAHS=$(get_secret_from_keyvault "AZUREDATALAKEDEVMAHS") \
        --from-literal celery_broker_url=$(get_secret_from_keyvault "celerybrokerurl") \
        --from-literal REDIS_URL=$(get_secret_from_keyvault "REDISURL") \
        --from-literal SECRET_KEY=$(get_secret_from_keyvault "SECRETKEY") \
        --from-literal slack_api_token=$(get_secret_from_keyvault "slackapitoken") \
        --from-literal zema_username=$(get_secret_from_keyvault "zemausername") \
        --from-literal zema_password=$(get_secret_from_keyvault "zemapassword") \
        --from-literal sqlalchemy_url=$(get_secret_from_keyvault "sqlalchemyurl") \
        --from-literal DEV_CLUSTER_PRICEVIEWER_USER=$(get_secret_from_keyvault "DEVCLUSTERPRICEVIEWERUSER") \
        --from-literal DEV_CLUSTER_PRICEVIEWER_PWD=$(get_secret_from_keyvault "DEVCLUSTERPRICEVIEWERPWD") \
        --from-literal sqlalchemy_url_jenkins=$(get_secret_from_keyvault "sqlalchemyurljenkins")
}

# DESC: Main control flow
# ARGS: $@ (optional): Arguments provided to the script
# OUTS: None
function main() {
    source "./shellai-jenkins-shared-lib/utilities/source.sh"
    trap script_trap_err ERR
    trap script_trap_exit EXIT
    script_init "$@"
    cron_init
    colour_init
    parse_params "$@"

    check_binary "kubectl" 1

    if [[ ${DELETE_SECRET} == true || ${DELETE_SECRET} == 'true' ]] ; then
      delete_secret
    elif [[ ${CREATE_SECRET} == true || ${CREATE_SECRET} == 'true' ]] ; then
      delete_secret
      create_secret
    else
      script_exit "no valid operation" 2
    fi
}

# Make it rain
main "$@"

# vim: syntax=sh cc=80 tw=79 ts=4 sw=4 sts=4 et sr


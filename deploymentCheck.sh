#!/usr/bin/env bash
set -o errexit          # Exit on most errors (see the manual)
set -o errtrace         # Make sure any error trap is inherited
set -o nounset          # Disallow expansion of unset variables
set -o pipefail         # Use last non-zero exit code in a pipeline



# DESC: Usage help
# ARGS: None
# OUTS: None
function script_usage() {
    cat << EOF
Usage:
     -h|--help                  Displays this help
     -c|--componentname         [REQUIRED] component name
     -n|--namespace             [REQUIRED] kubernetes namespace to be used (e.g. exmaples)
     -hn|--hostname             [OPTIONAL] hostname of the application, can extend to check the ingress

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
            -c=*|--componentname=*)
                COMPONENT_NAME="${param#*=}"
                ;;
            -n=*|--namespace=*)
                NAMESPACE="${param#*=}"
                ;;
            -hn=*|--hostname=*)
                HOST_NAME="${param#*=}"
                ;;
            *)
                script_exit "Invalid parameter was provided: $param" 2
                ;;
        esac
    done

    if [ -z ${COMPONENT_NAME-} ] ; then
        script_usage
        script_exit "No component name provided" 2
    fi

    if [ -z ${NAMESPACE-} ] ; then
        script_usage
        script_exit "no namespace provided" 2
    fi

#    if [ -z ${HOST_NAME-} ] ; then
#        script_usage
#        script_exit "no hostname provided" 2
#    fi

}


function checkComponentStatus() {
    RETRIES=60
    SLEEP_FOR=10
    while [[ $(kubectl get pods --selector=app.kubernetes.io/name=${COMPONENT_NAME} -n ${NAMESPACE}  | grep '2/2     Running' | wc -l) -eq 0 ]]; do
        if [[ RETRIES -ne 0 ]]; then
            echo INFO: ${COMPONENT_NAME} is not running!
            echo "Retries left: $RETRIES"
            echo "sleeping $SLEEP_FOR secs"
            sleep $SLEEP_FOR
            RETRIES=$(( RETRIES-1 ))
        else
            echo ERROR: Max retries reached, ${COMPONENT_NAME} is still not running. Aborting the script now! 1>&2
            exit 1
        fi
    done

    output=$(kubectl get pods -n ${NAMESPACE} | grep ${COMPONENT_NAME})
    uptime=$(echo $output | awk {' print $5 '})
    echo "Application is up and running... \"${NAMESPACE}:${COMPONENT_NAME}\", uptime: \"$uptime\""
}

function checkService() {
    if [[ $(kubectl get svc -n ${NAMESPACE} | grep ${COMPONENT_NAME} | wc -l) -eq 0 ]]; then
        echo ERROR: service is not created. Aborting the script now! 1>&2
        exit 1
    fi

    echo "Service is in place for the app ${COMPONENT_NAME}"
}

function checkIngress(){
    if [[ $(kubectl get ing -n ${NAMESPACE} | grep ${COMPONENT_NAME} | wc -l) -eq 0 ]]; then
        echo ERROR: ingress is not created. Aborting the script now! 1>&2
        exit 1
    fi

    echo "Ingress is in place for the app ${COMPONENT_NAME}"
}

function checkNetworkPolicy() {
    if [[ $(kubectl get networkpolicy -n ${NAMESPACE} | grep "allow-all-${COMPONENT_NAME}" | wc -l) -eq 0 ]]; then
        echo ERROR: networkpolicy is not created. Aborting the script now! 1>&2
        exit 1
    fi

    echo "networkpolicy is in place for the app ${COMPONENT_NAME}"
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
    check_binary "awk" 1

    checkComponentStatus
    checkService
    checkIngress
}

# Make it rain
main "$@"
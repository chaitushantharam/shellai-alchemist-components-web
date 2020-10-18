#!/usr/bin/env bash

set -o errexit          # Exit on most errors (see the manual)
set -o errtrace         # Make sure any error trap is inherited
set -o nounset          # Disallow expansion of unset variables
set -o pipefail         # Use last non-zero exit code in a pipeline
#set -o xtrace          # Trace the execution of the script (debug)

COMPONENT_NAME=""
KSVC=""
KREVISION=""
TIMEOUT="60s"

# DESC: Usage help
# ARGS: None
# OUTS: None
function script_usage() {
    cat << EOF
Usage:
     -h|--help                  Displays this help
     -n|--namespace             [REQUIRED] kubernetes namespace to be used (e.g. platform, lithosenz)
     -d|--deploymentid          [REQUIRED] deploymentid of this deployment
     -c|--componentname         [REQUIRED] componentname of this deployment
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
            -n=*|--namespace=*)
                NAMESPACE="${param#*=}"
                ;;
            -d=*|--deploymentid=*)
                DEPLOYMENT_ID="${param#*=}"
                ;;
            -c=*|--componentname=*)
                COMPONENT_NAME="${param#*=}"
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

    if [ -z ${DEPLOYMENT_ID-} ] ; then
        script_usage
        script_exit "no deploymentid provided" 2
    fi

    if [ -z ${COMPONENT_NAME-} ] ; then
        script_usage
        script_exit "no componentname provided" 2
    fi

    KSVC="service.serving.knative.dev/$COMPONENT_NAME"
    KREVISION="revision.serving.knative.dev/${COMPONENT_NAME}-${DEPLOYMENT_ID}"
}

function check_new_version_is_ready(){
    TIMEOUT="200s"

    printf '\n[CONDITION CHECK] Revision: ContainerHealthy \n========================================================================\n' && \
      kubectl --namespace ${NAMESPACE} wait --for=condition=ContainerHealthy ${KREVISION}  --timeout=${TIMEOUT}
    printf '\n[CONDITION CHECK] Revision: Active condition \n========================================================================\n' && \
      kubectl --namespace ${NAMESPACE} wait --for=condition=Active ${KREVISION}  --timeout=${TIMEOUT}
    printf '\n[CONDITION CHECK] Revision: Ready condition \n========================================================================\n' && \
      kubectl --namespace ${NAMESPACE} wait --for=condition=Ready ${KREVISION}  --timeout=${TIMEOUT}

    printf '\n[CONDITION CHECK] Service: ConfigurationsReady condition \n========================================================================\n' && \
      kubectl --namespace ${NAMESPACE} wait --for=condition=ConfigurationsReady ${KSVC} --timeout=${TIMEOUT}
    printf '\n[CONDITION CHECK] Service: RoutesReady condition \n========================================================================\n' && \
      kubectl --namespace ${NAMESPACE} wait --for=condition=RoutesReady ${KSVC} --timeout=${TIMEOUT}
    printf '\n[CONDITION CHECK] Service: Ready condition \n========================================================================\n' && \
      kubectl --namespace ${NAMESPACE} wait --for=condition=Ready ${KSVC} --timeout=${TIMEOUT}

    revisionActive=$(kubectl --namespace ${NAMESPACE} get revisions --selector="serving.knative.dev/service=${COMPONENT_NAME}" --sort-by=.metadata.creationTimestamp | tail +2 | wc -l)
    printf '\n========================================================================\n'
    echo "Number of Revisions Active:$revisionActive"
    printf '========================================================================\n'

    kubectl --namespace ${NAMESPACE} get ${KSVC} | tail +2 | awk '{ print "Latest Created:"} { print "\t"$3 }  { print "Latest Ready:" } { print "\t"$4 }'

    revisions=($(kubectl --namespace ${NAMESPACE} get revision  --selector="serving.knative.dev/service=${COMPONENT_NAME}" --sort-by=.metadata.creationTimestamp | tail +2 | awk '{ print $1 }'))
    latestReady=$(kubectl --namespace ${NAMESPACE} get ${KSVC} | tail +2 | awk '{ print $4 }')

    if [ "${COMPONENT_NAME}-${DEPLOYMENT_ID}" == "$latestReady" ] ; then
      echo "expected version is running..."
    else
      echo "expected version is not running..."
      script_exit "Expected: ${DEPLOYMENT_ID}, \t Actual: ${./}" 2
    fi
}

function delete_unwanted_revisions(){
    for revision in "${revisions[@]}"
    do
       :
      if [ "$revision" != "${COMPONENT_NAME}-${DEPLOYMENT_ID}" ] ; then
          echo "ALERT!! unwanted revision found [$revision]"
          echo "deleting revision [$revision]"
          kubectl --namespace ${NAMESPACE} delete revision/"$revision"
      fi
    done
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
    check_binary "sort" 1
    check_binary "wc" 1
    check_binary "tail" 1

    check_new_version_is_ready

    delete_unwanted_revisions
}

# Make it rain
main "$@"

# vim: syntax=sh cc=80 tw=79 ts=4 sw=4 sts=4 et sr
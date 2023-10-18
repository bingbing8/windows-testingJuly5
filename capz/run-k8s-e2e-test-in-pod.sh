#!/bin/bash

set -o errexit
set -o nounset
set -o pipefail

SCRIPT_PATH=$(realpath "${BASH_SOURCE[0]}")
SCRIPT_ROOT=$(dirname "${SCRIPT_PATH}")
log() {
	local msg=$1
	echo "$(date -R): $msg"
}

ensure_envs() {    
    : "${ARTIFACTS:?Environment variable empty or not defined.}"
    : "${CI_VERSION:?Environment variable empty or not defined.}"
}

export SKIP_TEST="${SKIP_TEST:-"false"}"
ensure_envs
log "delete test-pod if exist"
kubectl delete pod test-pod --ignore-not-found=true
kubectl apply -f "${SCRIPT_ROOT}"/runtestfrommgmtcluster/run-e2e-test-sa.yaml
< "${SCRIPT_ROOT}"/runtestfrommgmtcluster/e2etest-pod.yaml envsubst | kubectl apply -f -
max_item=50
counter=0
log "wait tasks on pod to completed or error ..."
ret=1
while [ $ret -ne 0 ] && [ "$counter" -lt "$max_item" ]; do
    log "Check status again #$counter"
    counter=$((counter + 1))        
    #(( counter++ ))
    current_status=$(kubectl get pod test-pod --no-headers -o=custom-columns=:.status.phase)
    if [[ "${current_status,,}" == "failed" ]] || [[ "${current_status,,}" == "succeeded" ]]; then
        log "error occure in test-pod, exiting ..."
        counter=$max_item    
    fi
    ret=0
    kubectl wait --timeout 3m --for=condition=Ready pod/test-pod || ret=$?
done
if [ $ret == 0 ]; then
    echo "Tests are completed. Copying artifacts from test-pod:_artifacts to ${ARTIFACTS}"
    kubectl cp test-pod:_artifacts/ "${ARTIFACTS}/"
fi
kubectl logs test-pod -c e2e-test
kubectl logs test-pod -c e2e-test > "${ARTIFACTS}/e2e-test.log"
#kubectl delete pod test-pod
exitcode=$(< "${ARTIFACTS}/exit-code.txt")
exit $exitcode
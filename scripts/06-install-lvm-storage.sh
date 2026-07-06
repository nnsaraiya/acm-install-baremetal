#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")"
source ../lib/common.sh
load_env
export KUBECONFIG="${WORK_DIR}/kubeconfig/hub"
require_cmd oc
require_file "${KUBECONFIG}"

oc apply -f "${REPO_ROOT}/manifests/hub/lvms-namespace.yaml"
oc apply -f "${REPO_ROOT}/manifests/hub/lvms-operatorgroup.yaml"
oc apply -f "${REPO_ROOT}/manifests/hub/lvms-subscription.yaml"

wait_until 300 10 "lvms-operator CSV to succeed" \
  bash -c "oc get csv -n openshift-storage 2>/dev/null | grep -q 'lvms-operator.*Succeeded'"

oc apply -f "${REPO_ROOT}/manifests/hub/lvmcluster.yaml"

wait_until 300 10 "LVMCluster to be Ready" \
  bash -c "oc get lvmcluster lvmcluster -n openshift-storage -o jsonpath='{.status.state}' 2>/dev/null | grep -q Ready"

log "LVM storage ready; default StorageClass should now be lvms-vg1"
oc get storageclass

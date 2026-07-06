#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")"
source ../lib/common.sh
load_env
export KUBECONFIG="${WORK_DIR}/kubeconfig/hub"
require_cmd oc
require_file "${KUBECONFIG}"

oc apply -f "${REPO_ROOT}/manifests/hub/acm-namespace.yaml"
oc apply -f "${REPO_ROOT}/manifests/hub/acm-operatorgroup.yaml"
oc apply -f "${REPO_ROOT}/manifests/hub/acm-subscription.yaml"

wait_until 600 15 "advanced-cluster-management CSV to succeed" \
  bash -c "oc get csv -n open-cluster-management 2>/dev/null | grep advanced-cluster-management | grep -q Succeeded"

oc apply -f "${REPO_ROOT}/manifests/hub/multiclusterhub.yaml"

wait_until 900 15 "MultiClusterHub to be Running" \
  bash -c "oc get multiclusterhub multiclusterhub -n open-cluster-management -o jsonpath='{.status.phase}' 2>/dev/null | grep -q Running"

log "RHACM is installed and MultiClusterHub is Running"

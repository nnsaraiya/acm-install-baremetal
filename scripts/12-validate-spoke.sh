#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")"
source ../lib/common.sh
load_env
export KUBECONFIG="${WORK_DIR}/kubeconfig/hub"
require_cmd oc
require_file "${KUBECONFIG}"

log "waiting for BareMetalHost to reach 'provisioned' state"
wait_until 3600 30 "BareMetalHost ${SPOKE_HOSTNAME} provisioned" \
  bash -c "oc get bmh ${SPOKE_HOSTNAME} -n ${SPOKE_CLUSTER_NAME} -o jsonpath='{.status.provisioning.state}' 2>/dev/null | grep -q provisioned"

log "waiting for AgentClusterInstall to complete"
wait_until 3600 30 "AgentClusterInstall ${SPOKE_CLUSTER_NAME}-install completed" \
  bash -c "oc get agentclusterinstall ${SPOKE_CLUSTER_NAME}-install -n ${SPOKE_CLUSTER_NAME} -o jsonpath='{.status.conditions[?(@.type==\"Completed\")].status}' 2>/dev/null | grep -q True"

log "waiting for ManagedCluster to become available"
wait_until 900 15 "ManagedCluster ${SPOKE_CLUSTER_NAME} available" \
  bash -c "oc get managedcluster ${SPOKE_CLUSTER_NAME} -o jsonpath='{.status.conditions[?(@.type==\"ManagedClusterConditionAvailable\")].status}' 2>/dev/null | grep -q True"

oc get managedcluster "${SPOKE_CLUSTER_NAME}"
log "spoke cluster ${SPOKE_CLUSTER_NAME} is imported and Available in RHACM"

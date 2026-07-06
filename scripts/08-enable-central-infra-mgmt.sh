#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")"
source ../lib/common.sh
load_env
export KUBECONFIG="${WORK_DIR}/kubeconfig/hub"
require_cmd oc
require_file "${KUBECONFIG}"

# ACM installs MultiClusterEngine (MCE) as a dependency; the assisted-service
# component (central infrastructure management) lives there. Resource/
# namespace names below match ACM 2.11 defaults — confirm against
# `oc get multiclusterengine` if this errors on a different ACM version.
log "enabling the assisted-service component on MultiClusterEngine"
oc patch multiclusterengine multiclusterengine --type=merge -p \
  '{"spec":{"overrides":{"components":[{"name":"assisted-service","enabled":true}]}}}' \
  || warn "multiclusterengine patch failed or already enabled — verify manually: oc get multiclusterengine multiclusterengine -o yaml"

oc apply -f "${REPO_ROOT}/manifests/hub/provisioning.yaml"
oc apply -f "${REPO_ROOT}/manifests/hub/agentserviceconfig.yaml"

wait_until 600 15 "assisted-service deployment to be available" \
  bash -c "oc get deployment assisted-service -n multicluster-engine -o jsonpath='{.status.availableReplicas}' 2>/dev/null | grep -q '^[1-9]'"

log "central infrastructure management enabled; assisted-service is ready for InfraEnv/BareMetalHost CRs"

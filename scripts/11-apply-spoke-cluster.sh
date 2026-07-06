#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")"
source ../lib/common.sh
load_env
export KUBECONFIG="${WORK_DIR}/kubeconfig/hub"
require_cmd oc jq
require_file "${KUBECONFIG}"
require_file "${PULL_SECRET_PATH}"
require_file "${SSH_PUBLIC_KEY_PATH}"
require_file "${WORK_DIR}/generated/${SPOKE_HOSTNAME}.uuid"

export SPOKE_NAMESPACE="${SPOKE_CLUSTER_NAME}"
export SPOKE_VM_UUID
SPOKE_VM_UUID="$(cat "${WORK_DIR}/generated/${SPOKE_HOSTNAME}.uuid")"
export SSH_KEY
SSH_KEY="$(cat "${SSH_PUBLIC_KEY_PATH}")"
export PULL_SECRET_B64
PULL_SECRET_B64="$(jq -c . "${PULL_SECRET_PATH}" | base64 -w0)"
export SUSHY_USER_B64
SUSHY_USER_B64="$(printf '%s' "${SUSHY_USER}" | base64 -w0)"
export SUSHY_PASSWORD_B64
SUSHY_PASSWORD_B64="$(printf '%s' "${SUSHY_PASSWORD}" | base64 -w0)"

GEN_DIR="${WORK_DIR}/generated/spoke"
mkdir -p "${GEN_DIR}"

for tmpl in namespace pull-secret clusterimageset bmc-secret infraenv clusterdeployment agentclusterinstall baremetalhost managedcluster klusterletaddonconfig; do
  render_template "${REPO_ROOT}/manifests/spoke/${tmpl}.yaml.tmpl" "${GEN_DIR}/${tmpl}.yaml"
done

# Order matters: namespace and secrets first, then the Hive/assisted-service
# CRs that reference them, then BareMetalHost last since applying it is what
# triggers ACM to power on the VM via Redfish.
oc apply -f "${GEN_DIR}/namespace.yaml"
oc apply -f "${GEN_DIR}/pull-secret.yaml"
oc apply -f "${GEN_DIR}/bmc-secret.yaml"
oc apply -f "${GEN_DIR}/clusterimageset.yaml"
oc apply -f "${GEN_DIR}/infraenv.yaml"
oc apply -f "${GEN_DIR}/clusterdeployment.yaml"
oc apply -f "${GEN_DIR}/agentclusterinstall.yaml"
oc apply -f "${GEN_DIR}/managedcluster.yaml"
oc apply -f "${GEN_DIR}/klusterletaddonconfig.yaml"
oc apply -f "${GEN_DIR}/baremetalhost.yaml"

log "spoke cluster CRs applied — ACM will now power on ${SPOKE_HOSTNAME} via Redfish and begin discovery/install"
log "watch progress with: oc get bmh -n ${SPOKE_CLUSTER_NAME}"
log "                     oc get agentclusterinstall -n ${SPOKE_CLUSTER_NAME} ${SPOKE_CLUSTER_NAME}-install -o yaml"

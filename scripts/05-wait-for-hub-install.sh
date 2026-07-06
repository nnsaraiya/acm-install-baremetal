#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")"
source ../lib/common.sh
load_env

OC_INSTALL="${WORK_DIR}/bin/openshift-install"
require_file "${OC_INSTALL}"

log "waiting for hub bootstrap to complete (boots RHCOS, starts the control plane; typically 20-40 min)"
"${OC_INSTALL}" agent wait-for bootstrap-complete --dir "${HUB_INSTALL_DIR}" --log-level=info

log "waiting for hub install to complete"
"${OC_INSTALL}" agent wait-for install-complete --dir "${HUB_INSTALL_DIR}" --log-level=info

mkdir -p "${WORK_DIR}/kubeconfig"
cp "${HUB_INSTALL_DIR}/auth/kubeconfig" "${WORK_DIR}/kubeconfig/hub"
log "hub kubeconfig copied to ${WORK_DIR}/kubeconfig/hub"
log "use it with: export KUBECONFIG=${WORK_DIR}/kubeconfig/hub"

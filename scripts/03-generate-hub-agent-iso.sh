#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")"
source ../lib/common.sh
load_env
require_cmd jq envsubst
require_file "${PULL_SECRET_PATH}"
require_file "${SSH_PUBLIC_KEY_PATH}"

OC_INSTALL="${WORK_DIR}/bin/openshift-install"
require_file "${OC_INSTALL}"

if [[ -d "${HUB_INSTALL_DIR}" ]]; then
  warn "removing existing ${HUB_INSTALL_DIR} to regenerate install assets"
  rm -rf "${HUB_INSTALL_DIR}"
fi
mkdir -p "${HUB_INSTALL_DIR}"

export PULL_SECRET_JSON
PULL_SECRET_JSON="$(jq -c . "${PULL_SECRET_PATH}")"
export SSH_KEY
SSH_KEY="$(cat "${SSH_PUBLIC_KEY_PATH}")"

render_template "${REPO_ROOT}/manifests/hub/install-config.yaml.tmpl" "${HUB_INSTALL_DIR}/install-config.yaml"
render_template "${REPO_ROOT}/manifests/hub/agent-config.yaml.tmpl" "${HUB_INSTALL_DIR}/agent-config.yaml"

log "generating agent ISO for hub cluster (this can take several minutes)"
"${OC_INSTALL}" agent create image --dir "${HUB_INSTALL_DIR}" --log-level=info

log "agent ISO ready at ${HUB_INSTALL_DIR}/agent.x86_64.iso"

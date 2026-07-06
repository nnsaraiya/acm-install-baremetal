#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")"
source ../lib/common.sh
load_env
require_cmd curl tar

BIN_DIR="${WORK_DIR}/bin"
mkdir -p "${BIN_DIR}" "${WORK_DIR}/downloads"
MIRROR="https://mirror.openshift.com/pub/openshift-v4/x86_64/clients/ocp/${OCP_VERSION}"

for pkg in openshift-install-linux.tar.gz openshift-client-linux.tar.gz; do
  if [[ ! -f "${WORK_DIR}/downloads/${pkg}" ]]; then
    log "downloading ${pkg} (${OCP_VERSION})"
    curl -fL "${MIRROR}/${pkg}" -o "${WORK_DIR}/downloads/${pkg}"
  else
    log "${pkg} already downloaded"
  fi
  tar -xzf "${WORK_DIR}/downloads/${pkg}" -C "${BIN_DIR}"
done

chmod +x "${BIN_DIR}/openshift-install" "${BIN_DIR}/oc" "${BIN_DIR}/kubectl"
log "openshift-install and oc installed to ${BIN_DIR}"
log "add to your shell: export PATH=\"${BIN_DIR}:\${PATH}\""
"${BIN_DIR}/openshift-install" version

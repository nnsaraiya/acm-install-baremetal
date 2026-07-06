#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")"
source ../lib/common.sh
load_env
require_cmd virsh envsubst

NET_XML="${WORK_DIR}/generated/${LIBVIRT_NETWORK_NAME}-network.xml"
render_template "${REPO_ROOT}/manifests/libvirt/network.xml.tmpl" "$NET_XML"

if virsh net-info "${LIBVIRT_NETWORK_NAME}" >/dev/null 2>&1; then
  warn "network ${LIBVIRT_NETWORK_NAME} already exists, destroying/undefining to reapply"
  virsh net-destroy "${LIBVIRT_NETWORK_NAME}" >/dev/null 2>&1 || true
  virsh net-undefine "${LIBVIRT_NETWORK_NAME}" >/dev/null 2>&1 || true
fi

virsh net-define "$NET_XML"
virsh net-start "${LIBVIRT_NETWORK_NAME}"
virsh net-autostart "${LIBVIRT_NETWORK_NAME}"
log "libvirt network ${LIBVIRT_NETWORK_NAME} (${NETWORK_CIDR}) is up"

if virsh pool-info "${LIBVIRT_POOL_NAME}" >/dev/null 2>&1; then
  log "storage pool ${LIBVIRT_POOL_NAME} already exists"
else
  sudo mkdir -p "${LIBVIRT_POOL_PATH}"
  virsh pool-define-as "${LIBVIRT_POOL_NAME}" dir --target "${LIBVIRT_POOL_PATH}"
  virsh pool-build "${LIBVIRT_POOL_NAME}"
  virsh pool-start "${LIBVIRT_POOL_NAME}"
  virsh pool-autostart "${LIBVIRT_POOL_NAME}"
  log "storage pool ${LIBVIRT_POOL_NAME} created at ${LIBVIRT_POOL_PATH}"
fi

#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")"
source ../lib/common.sh
load_env
require_cmd virt-install virsh

if virsh dominfo "${SPOKE_HOSTNAME}" >/dev/null 2>&1; then
  warn "domain ${SPOKE_HOSTNAME} already exists, destroying/undefining first"
  virsh destroy "${SPOKE_HOSTNAME}" >/dev/null 2>&1 || true
  virsh undefine "${SPOKE_HOSTNAME}" --nvram --remove-all-storage >/dev/null 2>&1 || true
fi

# Create the VM (this allocates its disk and briefly boots it, which will
# just PXE-fail since nothing is listening yet), then power it straight back
# off. From here ACM owns its power state via the Redfish BMC — it will
# insert the discovery ISO as virtual media and power-cycle the VM once the
# BareMetalHost CR is applied in script 11.
virt-install \
  --name "${SPOKE_HOSTNAME}" \
  --vcpus "${SPOKE_VCPUS}" \
  --memory "${SPOKE_RAM_MB}" \
  --disk "size=${SPOKE_DISK_GB},pool=${LIBVIRT_POOL_NAME}" \
  --network "network=${LIBVIRT_NETWORK_NAME},mac=${SPOKE_MAC}" \
  --os-variant detect=on,require=off \
  --graphics none --console pty,target_type=serial \
  --boot network,hd,menu=on \
  --noautoconsole

virsh destroy "${SPOKE_HOSTNAME}"

SPOKE_UUID="$(virsh domuuid "${SPOKE_HOSTNAME}")"
echo "${SPOKE_UUID}" > "${WORK_DIR}/generated/${SPOKE_HOSTNAME}.uuid"
log "spoke VM ${SPOKE_HOSTNAME} defined (powered off), UUID=${SPOKE_UUID}"
log "its power state is now owned by ACM via the Redfish BMC — do not start it manually"

#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")"
source ../lib/common.sh
load_env
require_cmd virt-install virsh
require_file "${HUB_INSTALL_DIR}/agent.x86_64.iso"

if virsh dominfo "${HUB_HOSTNAME}" >/dev/null 2>&1; then
  warn "domain ${HUB_HOSTNAME} already exists, destroying/undefining first"
  virsh destroy "${HUB_HOSTNAME}" >/dev/null 2>&1 || true
  virsh undefine "${HUB_HOSTNAME}" --nvram --remove-all-storage >/dev/null 2>&1 || true
fi

# Disk order matters: first disk becomes /dev/vda (OS, pinned via
# rootDeviceHints in agent-config.yaml.tmpl), second becomes /dev/vdb
# (left empty for LVM Storage).
virt-install \
  --name "${HUB_HOSTNAME}" \
  --vcpus "${HUB_VCPUS}" \
  --memory "${HUB_RAM_MB}" \
  --disk "size=${HUB_OS_DISK_GB},pool=${LIBVIRT_POOL_NAME}" \
  --disk "size=${HUB_DATA_DISK_GB},pool=${LIBVIRT_POOL_NAME}" \
  --cdrom "${HUB_INSTALL_DIR}/agent.x86_64.iso" \
  --network "network=${LIBVIRT_NETWORK_NAME},mac=${HUB_MAC}" \
  --os-variant detect=on,require=off \
  --graphics none --console pty,target_type=serial \
  --boot menu=on,useserial=on \
  --noautoconsole

log "hub VM ${HUB_HOSTNAME} created and booting from the agent ISO"
log "console: virsh console ${HUB_HOSTNAME}"

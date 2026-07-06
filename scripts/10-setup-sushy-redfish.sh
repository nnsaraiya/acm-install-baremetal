#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")"
source ../lib/common.sh
load_env
require_cmd python3 pip3 virsh curl jq
require_file "${WORK_DIR}/generated/${SPOKE_HOSTNAME}.uuid"

pip3 install --user --quiet sushy-tools bcrypt

SUSHY_DIR="${WORK_DIR}/sushy"
mkdir -p "${SUSHY_DIR}"

python3 - "${SUSHY_USER}" "${SUSHY_PASSWORD}" "${SUSHY_DIR}/htpasswd" <<'PYEOF'
import sys, bcrypt
user, password, path = sys.argv[1], sys.argv[2], sys.argv[3]
hashed = bcrypt.hashpw(password.encode(), bcrypt.gensalt()).decode()
with open(path, "w") as f:
    f.write(f"{user}:{hashed}\n")
PYEOF

cat > "${SUSHY_DIR}/sushy-tools.conf" <<EOF
SUSHY_EMULATOR_LIBVIRT_URI = "qemu:///system"
SUSHY_EMULATOR_AUTH_FILE = "${SUSHY_DIR}/htpasswd"
SUSHY_EMULATOR_IGNORE_BOOT_DEVICE = False
EOF

SUSHY_BIN="$(python3 -m site --user-base)/bin/sushy-emulator"
require_file "${SUSHY_BIN}"

SERVICE_FILE="/etc/systemd/system/sushy-tools.service"
sudo tee "${SERVICE_FILE}" >/dev/null <<EOF
[Unit]
Description=Sushy Redfish BMC emulator for the ACM baremetal spoke
After=libvirtd.service network-online.target
Requires=libvirtd.service

[Service]
Environment=SUSHY_EMULATOR_CONFIG=${SUSHY_DIR}/sushy-tools.conf
ExecStart=${SUSHY_BIN} --port ${SUSHY_PORT}
Restart=on-failure
User=$(whoami)

[Install]
WantedBy=multi-user.target
EOF

sudo systemctl daemon-reload
sudo systemctl enable --now sushy-tools

wait_until 60 3 "sushy-tools Redfish endpoint to respond" \
  curl -sf -u "${SUSHY_USER}:${SUSHY_PASSWORD}" "http://${SUSHY_HOST}:${SUSHY_PORT}/redfish/v1/Systems/"

SPOKE_UUID="$(cat "${WORK_DIR}/generated/${SPOKE_HOSTNAME}.uuid")"
log "verifying spoke VM is visible via Redfish"
curl -sf -u "${SUSHY_USER}:${SUSHY_PASSWORD}" \
  "http://${SUSHY_HOST}:${SUSHY_PORT}/redfish/v1/Systems/${SPOKE_UUID}" | jq '.PowerState'

log "sushy-tools Redfish BMC emulator running on ${SUSHY_HOST}:${SUSHY_PORT}"

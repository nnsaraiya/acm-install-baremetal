#!/usr/bin/env bash
# Copy this file to config/env.sh and edit the values for your environment.
# config/env.sh is gitignored — it will end up holding local paths only,
# but keep it out of version control anyway since it's host-specific.

### Cluster naming / DNS ######################################################
export BASE_DOMAIN="baremetal.local"
export HUB_CLUSTER_NAME="hub"
export SPOKE_CLUSTER_NAME="spoke"

### Libvirt network (single flat network for both hub and spoke) #############
export LIBVIRT_NETWORK_NAME="acm-baremetal"
export NETWORK_CIDR="192.168.130.0/24"
export NETWORK_GATEWAY="192.168.130.1"
export NETWORK_PREFIX="24"
export NETWORK_DNS="192.168.130.1"
export DHCP_RANGE_START="192.168.130.100"
export DHCP_RANGE_END="192.168.130.200"

# Static reservations (outside the DHCP range above, mapped by MAC)
export HUB_IP="192.168.130.10"
export HUB_MAC="52:54:00:aa:bb:01"
export HUB_HOSTNAME="hub"
export HUB_NIC_NAME="enp1s0"

export SPOKE_IP="192.168.130.20"
export SPOKE_MAC="52:54:00:aa:bb:02"
export SPOKE_HOSTNAME="spoke"

### VM sizing ##################################################################
# Total with both VMs: 14 vCPU / 56Gi RAM / 300GB disk, leaving headroom on the
# 8-core/96GiB/4TB host for Fedora + libvirt + sushy-tools. See docs/resource-budget.md.

# Hub (SNO). Two disks: OS disk (vda) and a second empty disk (vdb) dedicated
# to LVM Storage, which backs ACM/assisted-service PVs. The agent-based
# installer is pinned to vda via rootDeviceHints so it never touches vdb.
export HUB_VCPUS=8
export HUB_RAM_MB=32768
export HUB_OS_DISK_GB=120
export HUB_DATA_DISK_GB=60

# Spoke (SNO, provisioned by ACM/assisted-service)
export SPOKE_VCPUS=6
export SPOKE_RAM_MB=24576
export SPOKE_DISK_GB=120

### Libvirt storage pool #######################################################
export LIBVIRT_POOL_NAME="acm-baremetal"
export LIBVIRT_POOL_PATH="/var/lib/libvirt/images/acm-baremetal"

### OpenShift install ##########################################################
# Verify this OCP version against the ACM channel pinned in
# manifests/hub/acm-subscription.yaml before running — RHACM's support matrix
# changes across releases.
export OCP_VERSION="4.16.15"
export OCP_RELEASE_IMAGE="quay.io/openshift-release-dev/ocp-release:4.16.15-x86_64"
export PULL_SECRET_PATH="${HOME}/.openshift/pull-secret.json"
export SSH_PUBLIC_KEY_PATH="${HOME}/.ssh/id_rsa.pub"

### Sushy-tools (Redfish BMC emulator for the spoke) ###########################
export SUSHY_PORT=8000
export SUSHY_USER="admin"
export SUSHY_PASSWORD="password"
# The hub VM reaches sushy-tools via the libvirt network's gateway address,
# since that's where the Fedora host itself sits on this bridge.
export SUSHY_HOST="${NETWORK_GATEWAY}"

### Working directories #########################################################
export WORK_DIR="${HOME}/acm-baremetal-work"
export HUB_INSTALL_DIR="${WORK_DIR}/hub"

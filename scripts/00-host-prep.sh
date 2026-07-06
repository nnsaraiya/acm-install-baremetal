#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")"
source ../lib/common.sh
load_env

log "checking CPU virtualization support"
if ! grep -Eq '(vmx|svm)' /proc/cpuinfo; then
  die "no hardware virtualization support detected (need vmx/svm in /proc/cpuinfo)"
fi

log "installing virtualization + tooling packages"
sudo dnf install -y \
  qemu-kvm libvirt libvirt-daemon-kvm virt-install virt-manager \
  libguestfs-tools bind-utils nmstate NetworkManager \
  python3-pip jq gzip tar curl gettext

log "enabling and starting libvirtd"
sudo systemctl enable --now libvirtd

if ! id -nG "$(whoami)" | grep -qw libvirt; then
  log "adding $(whoami) to the libvirt group (log out/in for this to take effect)"
  sudo usermod -aG libvirt "$(whoami)"
  warn "you must start a new login session before running the next scripts"
fi

[[ -e /dev/kvm ]] || die "/dev/kvm not present — check BIOS virtualization settings"

mkdir -p "${WORK_DIR}"
log "host prep complete"

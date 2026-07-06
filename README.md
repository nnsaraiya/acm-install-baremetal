# acm-install-baremetal

Stand up a bare-metal-style RHACM hub + one managed ("spoke") OpenShift
cluster on a single physical machine, using libvirt VMs and a Redfish BMC
emulator (sushy-tools) so the spoke goes through ACM's real bare-metal
provisioning flow instead of a generic cluster import.

See `docs/architecture.md` for the full design and `docs/resource-budget.md`
for the CPU/RAM/disk math.

## Prerequisites

- Fedora host with hardware virtualization enabled in BIOS.
- A Red Hat pull secret at `~/.openshift/pull-secret.json` (or wherever
  `PULL_SECRET_PATH` in `config/env.sh` points).
- An SSH public key at `~/.ssh/id_rsa.pub` (or wherever
  `SSH_PUBLIC_KEY_PATH` points).
- `sudo` access (package installs, libvirtd, the sushy-tools systemd unit).

## Setup

```sh
cp config/env.example.sh config/env.sh
$EDITOR config/env.sh   # adjust domain, network range, sizing, versions
```

## Run order

Each script is idempotent-ish (re-running redefines/replaces its own
resources) but they must run in order the first time:

| # | Script | What it does |
|---|---|---|
| 00 | `host-prep.sh` | Installs KVM/libvirt/virt-install/sushy-tools deps, enables libvirtd |
| 01 | `libvirt-networks.sh` | Creates the shared libvirt network + storage pool |
| 02 | `fetch-ocp-clients.sh` | Downloads `openshift-install`/`oc` pinned to `OCP_VERSION` |
| 03 | `generate-hub-agent-iso.sh` | Renders install-config/agent-config, builds the hub's agent ISO |
| 04 | `create-hub-vm.sh` | Creates the hub VM and boots it from the agent ISO |
| 05 | `wait-for-hub-install.sh` | Waits for hub bootstrap/install, pulls kubeconfig |
| 06 | `install-lvm-storage.sh` | Installs LVM Storage operator, backs PVs with the hub's second disk |
| 07 | `install-acm.sh` | Installs RHACM, creates `MultiClusterHub` |
| 08 | `enable-central-infra-mgmt.sh` | Enables assisted-service (central infrastructure management) |
| 09 | `create-spoke-vm-shell.sh` | Defines the spoke VM, powered off |
| 10 | `setup-sushy-redfish.sh` | Stands up the Redfish BMC emulator for the spoke |
| 11 | `apply-spoke-cluster.sh` | Applies `BareMetalHost`/`InfraEnv`/Hive CRs — ACM takes over from here |
| 12 | `validate-spoke.sh` | Waits for provisioning + import, confirms the spoke is `Available` |

Run them from the repo root, e.g.:

```sh
./scripts/00-host-prep.sh
./scripts/01-libvirt-networks.sh
./scripts/02-fetch-ocp-clients.sh
export PATH="${HOME}/acm-baremetal-work/bin:${PATH}"
./scripts/03-generate-hub-agent-iso.sh
./scripts/04-create-hub-vm.sh
./scripts/05-wait-for-hub-install.sh
export KUBECONFIG="${HOME}/acm-baremetal-work/kubeconfig/hub"
./scripts/06-install-lvm-storage.sh
./scripts/07-install-acm.sh
./scripts/08-enable-central-infra-mgmt.sh
./scripts/09-create-spoke-vm-shell.sh
./scripts/10-setup-sushy-redfish.sh
./scripts/11-apply-spoke-cluster.sh
./scripts/12-validate-spoke.sh
```

Steps 05, 11-12 are long-running (hub install can take 30-60 min; spoke
discovery+install similarly) — the scripts poll rather than block forever,
with generous but finite timeouts.

## Version sensitivity

`manifests/hub/acm-subscription.yaml` pins an ACM channel and
`config/env.sh` pins an OpenShift version — these need to be a supported
pairing. Check Red Hat's ACM support matrix
(https://access.redhat.com/articles/7057925) before running, and adjust the
`AgentServiceConfig`/`Provisioning`/`MultiClusterEngine` handling in
`scripts/08-enable-central-infra-mgmt.sh` if field names differ on the ACM
version you land on — those CRDs shift across releases.

## Cleanup

To tear down and start over:

```sh
virsh destroy spoke; virsh undefine spoke --nvram --remove-all-storage
virsh destroy hub;   virsh undefine hub   --nvram --remove-all-storage
virsh net-destroy acm-baremetal; virsh net-undefine acm-baremetal
sudo systemctl disable --now sushy-tools
rm -rf ~/acm-baremetal-work
```

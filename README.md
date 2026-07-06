# acm-install-baremetal

Stand up a bare-metal-style RHACM hub + one managed ("spoke") OpenShift
cluster on a single physical machine, using libvirt VMs and a Redfish BMC
emulator (sushy-tools) so the spoke goes through ACM's real bare-metal
provisioning flow instead of a generic cluster import.

See `docs/architecture.md` for the full design and `docs/resource-budget.md`
for the CPU/RAM/disk math.

There are no scripts here — **`RUNBOOK.md`** is the ordered list of steps:
plain shell commands for the parts that aren't Kubernetes resources (host
prep, libvirt VMs, ISO build, sushy-tools), and `oc apply -f` / `oc patch`
against the plain YAML files under `manifests/` for everything else.

## Prerequisites

- Fedora host with hardware virtualization enabled in BIOS.
- A Red Hat pull secret (default expected at `~/.openshift/pull-secret.json`
  in the runbook's commands — adjust the path there if yours lives
  elsewhere).
- An SSH public key (default `~/.ssh/id_rsa.pub`).
- `sudo` access (package installs, libvirtd, the sushy-tools systemd unit).

## Before you start

A few YAML fields can't be known ahead of time (the pull secret, your SSH
key, the spoke VM's libvirt UUID) and are left as `REPLACE_*` placeholders
in the manifests. `RUNBOOK.md` has a table of exactly which file/placeholder/
command goes with each. Fill them in as you reach the relevant step — don't
commit the filled-in versions back (they'll contain your pull secret).

## Version sensitivity

`manifests/hub/acm-subscription.yaml` pins an ACM channel and
`manifests/spoke/clusterimageset.yaml` pins an OpenShift release — these
need to be a supported pairing. Check Red Hat's ACM support matrix
(https://access.redhat.com/articles/7057925) before running, and adjust
`manifests/hub/mce-enable-assisted-service-patch.yaml` /
`manifests/hub/agentserviceconfig.yaml` / `manifests/hub/provisioning.yaml`
if field names differ on the ACM version you land on — those CRDs shift
across releases.

## Cleanup

```sh
virsh destroy spoke; virsh undefine spoke --nvram --remove-all-storage
virsh destroy hub;   virsh undefine hub   --nvram --remove-all-storage
virsh net-destroy acm-baremetal; virsh net-undefine acm-baremetal
sudo systemctl disable --now sushy-tools
rm -rf ~/acm-baremetal-work
```

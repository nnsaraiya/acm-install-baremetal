# Runbook

Ordered, copy-pasteable steps to stand up the hub + spoke. There are no
scripts — some steps are shell commands (host prep, libvirt, ISO build,
sushy-tools — none of that is a Kubernetes resource, so there's no YAML for
it), the rest are `oc apply -f` / `oc patch` against the YAML files in
`manifests/`.

All values below (domain `baremetal.local`, network `192.168.130.0/24`, VM
sizing, OpenShift version, etc.) are baked into the manifests as concrete
defaults — see `docs/architecture.md` and `docs/resource-budget.md`. If you
want different values, change them consistently in every file listed below
and in these commands.

A few fields genuinely can't be known ahead of time and are left as
`REPLACE_*` placeholders in the YAML — edit those files in place before
applying them:

| Placeholder | Found in | How to fill it in |
|---|---|---|
| `REPLACE_PULL_SECRET_JSON` | `manifests/hub/install-config.yaml` | `jq -c . ~/.openshift/pull-secret.json` |
| `REPLACE_SSH_PUBLIC_KEY` | `manifests/hub/install-config.yaml`, `manifests/spoke/infraenv.yaml`, `manifests/spoke/agentclusterinstall.yaml` | `cat ~/.ssh/id_rsa.pub` |
| `REPLACE_PULL_SECRET_B64` | `manifests/spoke/pull-secret.yaml` | `jq -c . ~/.openshift/pull-secret.json \| base64 -w0` |
| `REPLACE_SPOKE_VM_UUID` | `manifests/spoke/baremetalhost.yaml` | `virsh domuuid spoke` (only after step 9 below) |

Don't commit the files after you've pasted real secrets into them — keep
your edits local (`git status` will show them as modified; just don't `git
add`/`git commit` those changes upstream).

## 1. Host prep

```sh
grep -Eq '(vmx|svm)' /proc/cpuinfo || echo "no hardware virtualization support!"
sudo dnf install -y \
  qemu-kvm libvirt libvirt-daemon-kvm virt-install virt-manager \
  libguestfs-tools bind-utils nmstate NetworkManager \
  python3-pip jq gzip tar curl gettext
sudo systemctl enable --now libvirtd
sudo usermod -aG libvirt "$(whoami)"   # log out/in afterward for this to apply
[[ -e /dev/kvm ]] || echo "/dev/kvm missing — check BIOS virtualization settings"
```

## 2. Libvirt network + storage pool

```sh
virsh net-define manifests/libvirt/network.xml
virsh net-start acm-baremetal
virsh net-autostart acm-baremetal

sudo mkdir -p /var/lib/libvirt/images/acm-baremetal
virsh pool-define-as acm-baremetal dir --target /var/lib/libvirt/images/acm-baremetal
virsh pool-build acm-baremetal
virsh pool-start acm-baremetal
virsh pool-autostart acm-baremetal
```

## 3. Fetch openshift-install / oc

```sh
mkdir -p ~/acm-baremetal-work/bin ~/acm-baremetal-work/downloads
cd ~/acm-baremetal-work/downloads
curl -fLO https://mirror.openshift.com/pub/openshift-v4/x86_64/clients/ocp/4.16.15/openshift-install-linux.tar.gz
curl -fLO https://mirror.openshift.com/pub/openshift-v4/x86_64/clients/ocp/4.16.15/openshift-client-linux.tar.gz
tar -xzf openshift-install-linux.tar.gz -C ~/acm-baremetal-work/bin
tar -xzf openshift-client-linux.tar.gz -C ~/acm-baremetal-work/bin
export PATH="$HOME/acm-baremetal-work/bin:$PATH"
openshift-install version
```

## 4. Generate the hub's agent ISO

Edit `manifests/hub/install-config.yaml` to fill in `REPLACE_PULL_SECRET_JSON`
and `REPLACE_SSH_PUBLIC_KEY` first.

```sh
mkdir -p ~/acm-baremetal-work/hub
cp manifests/hub/install-config.yaml manifests/hub/agent-config.yaml ~/acm-baremetal-work/hub/
openshift-install agent create image --dir ~/acm-baremetal-work/hub --log-level=info
# produces ~/acm-baremetal-work/hub/agent.x86_64.iso
```

## 5. Create and boot the hub VM

```sh
virt-install \
  --name hub \
  --vcpus 8 \
  --memory 32768 \
  --disk size=120,pool=acm-baremetal \
  --disk size=60,pool=acm-baremetal \
  --cdrom ~/acm-baremetal-work/hub/agent.x86_64.iso \
  --network network=acm-baremetal,mac=52:54:00:aa:bb:01 \
  --os-variant detect=on,require=off \
  --graphics none --console pty,target_type=serial \
  --boot menu=on,useserial=on \
  --noautoconsole
# console: virsh console hub
```

Disk order matters: the first disk becomes `/dev/vda` (the OS disk, pinned
via `rootDeviceHints` in `agent-config.yaml`), the second becomes `/dev/vdb`
(left empty for LVM Storage in step 7).

## 6. Wait for the hub install, get its kubeconfig

```sh
openshift-install agent wait-for bootstrap-complete --dir ~/acm-baremetal-work/hub --log-level=info
openshift-install agent wait-for install-complete --dir ~/acm-baremetal-work/hub --log-level=info
mkdir -p ~/acm-baremetal-work/kubeconfig
cp ~/acm-baremetal-work/hub/auth/kubeconfig ~/acm-baremetal-work/kubeconfig/hub
export KUBECONFIG=~/acm-baremetal-work/kubeconfig/hub
```

This is long-running — bootstrap+install for an SNO typically takes 30-60
minutes.

## 7. LVM Storage (backs ACM/assisted-service PVs on the hub)

```sh
oc apply -f manifests/hub/lvms-namespace.yaml
oc apply -f manifests/hub/lvms-operatorgroup.yaml
oc apply -f manifests/hub/lvms-subscription.yaml
# wait for the CSV, then:
oc get csv -n openshift-storage | grep lvms-operator
oc apply -f manifests/hub/lvmcluster.yaml
# wait for it to report Ready:
oc get lvmcluster lvmcluster -n openshift-storage -o jsonpath='{.status.state}'
oc get storageclass   # expect lvms-vg1
```

## 8. Install RHACM

```sh
oc apply -f manifests/hub/acm-namespace.yaml
oc apply -f manifests/hub/acm-operatorgroup.yaml
oc apply -f manifests/hub/acm-subscription.yaml
# wait for the CSV:
oc get csv -n open-cluster-management | grep advanced-cluster-management
oc apply -f manifests/hub/multiclusterhub.yaml
# wait for it to report Running:
oc get multiclusterhub multiclusterhub -n open-cluster-management -o jsonpath='{.status.phase}'
```

## 9. Enable central infrastructure management (assisted-service)

Field names here (`AgentServiceConfig`, `Provisioning`, the
`MultiClusterEngine` component list) are version-sensitive across ACM/MCE
releases — check `oc get multiclusterengine multiclusterengine -o yaml` if
this doesn't behave as expected on your version.

```sh
oc patch multiclusterengine multiclusterengine --type=merge \
  --patch-file=manifests/hub/mce-enable-assisted-service-patch.yaml

oc apply -f manifests/hub/provisioning.yaml
oc apply -f manifests/hub/agentserviceconfig.yaml

# wait for it to become available:
oc get deployment assisted-service -n multicluster-engine -o jsonpath='{.status.availableReplicas}'
```

## 10. Create the spoke VM shell

```sh
virt-install \
  --name spoke \
  --vcpus 6 \
  --memory 24576 \
  --disk size=120,pool=acm-baremetal \
  --network network=acm-baremetal,mac=52:54:00:aa:bb:02 \
  --os-variant detect=on,require=off \
  --graphics none --console pty,target_type=serial \
  --boot network,hd,menu=on \
  --noautoconsole

virsh destroy spoke   # power it straight back off — ACM owns its power state from here
virsh domuuid spoke   # note this UUID, needed for REPLACE_SPOKE_VM_UUID below
```

## 11. Set up sushy-tools (the Redfish BMC emulator for the spoke)

```sh
pip3 install --user sushy-tools bcrypt

mkdir -p ~/acm-baremetal-work/sushy
python3 - "admin" "password" ~/acm-baremetal-work/sushy/htpasswd <<'PYEOF'
import sys, bcrypt
user, password, path = sys.argv[1], sys.argv[2], sys.argv[3]
hashed = bcrypt.hashpw(password.encode(), bcrypt.gensalt()).decode()
with open(path, "w") as f:
    f.write(f"{user}:{hashed}\n")
PYEOF

cat > ~/acm-baremetal-work/sushy/sushy-tools.conf <<'EOF'
SUSHY_EMULATOR_LIBVIRT_URI = "qemu:///system"
SUSHY_EMULATOR_AUTH_FILE = "SUSHY_DIR/htpasswd"
SUSHY_EMULATOR_IGNORE_BOOT_DEVICE = False
EOF
sed -i "s#SUSHY_DIR#$HOME/acm-baremetal-work/sushy#" ~/acm-baremetal-work/sushy/sushy-tools.conf

SUSHY_BIN="$(python3 -m site --user-base)/bin/sushy-emulator"
sudo tee /etc/systemd/system/sushy-tools.service >/dev/null <<EOF
[Unit]
Description=Sushy Redfish BMC emulator for the ACM baremetal spoke
After=libvirtd.service network-online.target
Requires=libvirtd.service

[Service]
Environment=SUSHY_EMULATOR_CONFIG=$HOME/acm-baremetal-work/sushy/sushy-tools.conf
ExecStart=$SUSHY_BIN --port 8000
Restart=on-failure
User=$(whoami)

[Install]
WantedBy=multi-user.target
EOF

sudo systemctl daemon-reload
sudo systemctl enable --now sushy-tools

curl -sf -u admin:password http://192.168.130.1:8000/redfish/v1/Systems/
curl -sf -u admin:password "http://192.168.130.1:8000/redfish/v1/Systems/$(virsh domuuid spoke)" | jq '.PowerState'
```

## 12. Apply the spoke cluster CRs

Edit these files first:
- `manifests/spoke/pull-secret.yaml` (`REPLACE_PULL_SECRET_B64`)
- `manifests/spoke/infraenv.yaml`, `manifests/spoke/agentclusterinstall.yaml` (`REPLACE_SSH_PUBLIC_KEY`)
- `manifests/spoke/baremetalhost.yaml` (`REPLACE_SPOKE_VM_UUID`, from step 10)

Apply in this order — `baremetalhost.yaml` is last since that's what
triggers ACM to power the spoke VM on via Redfish:

```sh
oc apply -f manifests/spoke/namespace.yaml
oc apply -f manifests/spoke/pull-secret.yaml
oc apply -f manifests/spoke/bmc-secret.yaml
oc apply -f manifests/spoke/clusterimageset.yaml
oc apply -f manifests/spoke/infraenv.yaml
oc apply -f manifests/spoke/clusterdeployment.yaml
oc apply -f manifests/spoke/agentclusterinstall.yaml
oc apply -f manifests/spoke/managedcluster.yaml
oc apply -f manifests/spoke/klusterletaddonconfig.yaml
oc apply -f manifests/spoke/baremetalhost.yaml
```

## 13. Validate

```sh
# BareMetalHost should reach "provisioned":
oc get bmh spoke -n spoke -o jsonpath='{.status.provisioning.state}'

# AgentClusterInstall should report Completed=True:
oc get agentclusterinstall spoke-install -n spoke -o jsonpath='{.status.conditions[?(@.type=="Completed")].status}'

# ManagedCluster should report Available=True:
oc get managedcluster spoke -o jsonpath='{.status.conditions[?(@.type=="ManagedClusterConditionAvailable")].status}'

oc get managedcluster spoke
```

Steps 6, 12, 13 are long-running — poll with the commands above rather than
expecting them to return instantly.

## Cleanup

```sh
virsh destroy spoke; virsh undefine spoke --nvram --remove-all-storage
virsh destroy hub;   virsh undefine hub   --nvram --remove-all-storage
virsh net-destroy acm-baremetal; virsh net-undefine acm-baremetal
sudo systemctl disable --now sushy-tools
rm -rf ~/acm-baremetal-work
```

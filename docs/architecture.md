# Architecture

One physical machine (8-core AMD Ryzen 9 PRO 8945HS, 96GiB RAM, 4TB, Fedora
44) hosts both clusters as KVM/libvirt VMs. Everything shares a single flat
libvirt network.

```
                         Fedora 44 host (libvirt / KVM)
  ┌──────────────────────────────────────────────────────────────────────┐
  │  libvirt network "acm-baremetal"  (192.168.130.0/24, NAT)            │
  │  gateway/dns/dhcp: 192.168.130.1  (the host itself)                  │
  │                                                                      │
  │   ┌───────────────────────┐        ┌───────────────────────┐        │
  │   │  hub VM (SNO)         │        │  spoke VM (SNO)       │        │
  │   │  192.168.130.10       │        │  192.168.130.20       │        │
  │   │  8 vCPU / 32Gi        │        │  6 vCPU / 24Gi        │        │
  │   │  vda: OS (120G)       │        │  disk: 120G           │        │
  │   │  vdb: LVM data (60G)  │        │                       │        │
  │   │                       │        │  powered off until    │        │
  │   │  OpenShift + RHACM    │───────▶│  ACM drives Redfish   │        │
  │   │  + assisted-service   │ Redfish│  power-on / vmedia    │        │
  │   └───────────────────────┘        └───────────────────────┘        │
  │             ▲                                                       │
  │             │ redfish-virtualmedia+http://192.168.130.1:8000/...    │
  │   ┌─────────┴─────────────┐                                         │
  │   │ sushy-tools (host)    │  Redfish emulator, backed by libvirt    │
  │   └───────────────────────┘                                        │
  └──────────────────────────────────────────────────────────────────────┘
```

## Why the hub is installed differently than the spoke

The hub can't provision itself through ACM's assisted-service, because that
service doesn't exist until RHACM is running *on* the hub — chicken and egg.
So the hub is bootstrapped standalone with the **Agent-based Installer**
(`openshift-install agent create image`), which needs nothing but a boot ISO
and no external services.

The spoke, by contrast, is provisioned through the real bare-metal flow RHACM
uses in production: a `BareMetalHost` CR pointing at a Redfish BMC, discovered
and installed by the `Infrastructure Operator` / assisted-service running on
the hub. Since there's no second physical machine, the "BMC" is **sushy-tools**
emulating Redfish (including virtual media) against the spoke's libvirt
domain — so ACM drives it exactly as it would drive a real iDRAC/iLO/XClarity
BMC: power on, insert the discovery ISO as virtual media, watch it register as
an Agent, kick off the install.

## Component list

- **libvirt**: VM/network/storage virtualization on the Fedora host.
- **Agent-based Installer**: standalone hub SNO install (no assisted-service
  dependency).
- **LVM Storage operator (LVMS)**: backs the hub's PVs (assisted-service DB/
  filesystem/image storage, and anything else on the hub that needs a
  StorageClass). Consumes the hub VM's second disk (`/dev/vdb`) only.
- **RHACM (advanced-cluster-management)**: installed via OLM, `MultiClusterHub`
  CR turns it on. Brings in MultiClusterEngine (MCE) as a dependency.
- **Central infrastructure management** (MCE's assisted-service +
  `metal3`/Ironic baremetal-operator): enabled via `Provisioning` +
  `AgentServiceConfig` CRs. This is what actually talks Redfish to BMCs.
- **sushy-tools**: Redfish/virtual-media emulator on the host, backed by the
  `libvirt` driver, standing in for a real BMC on the spoke's libvirt domain.
- **Hive** (`ClusterDeployment`, `AgentClusterInstall`) + assisted-service
  (`InfraEnv`) + metal3 (`BareMetalHost`): the standard ACM CR set that
  drives discovery → install → auto-import as a `ManagedCluster`.

## Caveats

CRD field names for `AgentServiceConfig`, `Provisioning`, and the
`MultiClusterEngine` component-enable patch are version-sensitive across ACM/
MCE releases. Cross-check `manifests/hub/acm-subscription.yaml`'s channel
against `manifests/spoke/clusterimageset.yaml`'s OpenShift release before
running, using Red Hat's support matrix
(https://access.redhat.com/articles/7057925).

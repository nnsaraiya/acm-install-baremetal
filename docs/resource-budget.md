# Resource budget

Host: AMD Ryzen 9 PRO 8945HS (8 cores / 16 threads), 96GiB RAM, 4TB disk.

| | vCPU | RAM | Disk |
|---|---|---|---|
| Hub VM (SNO) | 8 | 32Gi | 120G (OS) + 60G (LVM data) = 180G |
| Spoke VM (SNO) | 6 | 24Gi | 120G |
| **VM total** | **14** | **56Gi** | **300G** |
| Host + libvirt + sushy-tools overhead | (oversubscribed vs 8 physical cores) | ~40Gi headroom | ~3.7TB free |

Notes:

- 14 vCPUs against 8 physical cores is oversubscription, which is fine here —
  the hub and spoke are rarely both under heavy CPU load simultaneously, and
  this is a lab/test setup, not a latency-sensitive production system.
- 56Gi of the 96GiB is committed to VMs, leaving ~40Gi for the Fedora host,
  libvirt, and sushy-tools — comfortable headroom.
- 300GB of 4TB is committed to VM disks; there's no storage pressure here.
- The hub's second disk (60G, `/dev/vdb`) exists solely so LVM Storage has a
  device to consume without touching the OS disk — see
  `manifests/hub/lvmcluster.yaml`.
- All sizes are just flags on the `virt-install` commands in `RUNBOOK.md`
  (steps 5 and 10, `--vcpus`/`--memory`/`--disk`) — edit them there if you
  want different values.

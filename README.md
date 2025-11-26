# Edge 3.4 Deployment Scenario

This repository contains all scripts and resources needed to deploy a 2-site Edge infrastructure with 10 VMs (5 VMs per site), each running single-node Kubernetes clusters with site-specific workloads via Fleet GitOps.

## Structure

```
Edge-3.4/
├── README.md                    # This file
├── scenario/                    # Deployment scripts and configuration
│   ├── README.md                # Scenario documentation
│   ├── DEPLOYMENT-GUIDE.md      # Complete deployment guide
│   ├── 1-cleanup-vms.sh         # Step 1: Clean previous deployment
│   ├── 2-create-registration-endpoints.sh  # Step 2: Create registration endpoints
│   ├── 3-build-isos-2-sites.sh  # Step 3: Build ISOs
│   ├── 4-create-rancher-resources.sh  # Step 4: Create Rancher resources
│   ├── 5-create-fleet-resources.sh   # Step 5: Create Fleet resources
│   ├── 6-create-vms-2-sites.sh  # Step 6: Create and start VMs
│   ├── 7-apply-machineinventory-labels.sh  # Step 7: Apply labels
│   ├── 8-label-clusters.sh      # Step 8: Label Fleet clusters
│   ├── vm-mac-addresses-site-a.txt  # MAC addresses for Site A VMs
│   ├── vm-mac-addresses-site-b.txt  # MAC addresses for Site B VMs
│   └── yaml/                    # YAML configuration files
│       ├── site-a-registration.yaml
│       ├── site-b-registration.yaml
│       ├── vms-config-2-sites.csv
│       ├── clustergroup-site-a.yaml
│       ├── clustergroup-site-b.yaml
│       ├── gitrepo-site-a.yaml
│       └── gitrepo-site-b.yaml
├── ztp-scale-nodes/             # Zero Touch Provisioning scripts
│   └── ztp-precreate.sh        # Pre-create Rancher resources
└── fleet/                       # Fleet GitOps workloads
    ├── demo-workload-site-a/    # Workload for Site A clusters
    └── demo-workload-site-b/    # Workload for Site B clusters
```

## Quick Start

See `scenario/DEPLOYMENT-GUIDE.md` for complete instructions.

### Deployment Sequence

1. **Clean previous deployment** (build-srv)
   ```bash
   cd scenario
   ./1-cleanup-vms.sh
   ```

2. **Create registration endpoints** (rancher)
   ```bash
   export KUBECONFIG=/etc/rancher/rke2/rke2.yaml
   ./2-create-registration-endpoints.sh
   ```

3. **Build ISOs** (build-srv)
   ```bash
   ./3-build-isos-2-sites.sh
   ```

4. **Create Rancher resources** (rancher)
   ```bash
   export KUBECONFIG=/etc/rancher/rke2/rke2.yaml
   ./4-create-rancher-resources.sh
   ```

5. **Create Fleet resources** (rancher)
   ```bash
   export KUBECONFIG=/etc/rancher/rke2/rke2.yaml
   ./5-create-fleet-resources.sh
   ```

6. **Create and start VMs** (build-srv)
   ```bash
   ./6-create-vms-2-sites.sh --parallel
   ```

7. **Apply labels to MachineInventories** (rancher - OPTIONAL)
   ```bash
   export KUBECONFIG=/etc/rancher/rke2/rke2.yaml
   ./7-apply-machineinventory-labels.sh
   ```

8. **Label Fleet clusters** (rancher - CRITICAL)
   ```bash
   export KUBECONFIG=/etc/rancher/rke2/rke2.yaml
   ./8-label-clusters.sh
   ```

## Prerequisites

- Rancher Management Server running
- EIB environment configured
- libvirt/KVM installed
- Network bridge br0 configured
- kubectl configured with Rancher kubeconfig
- jq installed (for Step 4)

## Server Requirements

Steps are split between two servers:
- **build-srv**: Steps 1, 3, 6 (VM creation and ISO building)
- **rancher**: Steps 2, 4, 5, 7, 8 (Rancher resource management)

## Notes

- Step 4 requires `ztp-precreate.sh` from `ztp-scale-nodes/` directory
- Step 7 is optional if MachineRegistrations include `machineInventoryLabels`
- Step 8 is critical and must be run after clusters are Ready (~25 minutes after Step 6)

## Total Deployment Time

~35-40 minutes from VM creation (Step 6) to workloads running.


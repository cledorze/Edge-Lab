# Deployment Scenario - 2 Sites with 10 VMs

This directory contains all scripts and resources needed to deploy 10 VMs across 2 sites, each running single-node Kubernetes clusters with site-specific workloads via Fleet GitOps.

## Structure

```
scenario/
├── README.md                           # This file
├── DEPLOYMENT-GUIDE.md                 # Complete deployment guide
├── 1-cleanup-vms.sh                    # Step 1: Clean previous deployment
├── 2-create-registration-endpoints.sh  # Step 2: Create registration endpoints
├── 3-build-isos-2-sites.sh             # Step 3: Build ISOs
├── 4-create-rancher-resources.sh       # Step 4: Create Rancher resources
├── 5-create-fleet-resources.sh         # Step 5: Create Fleet resources
├── 6-create-vms-2-sites.sh             # Step 6: Create and start VMs
├── 7-apply-machineinventory-labels.sh  # Step 7: Apply labels to MachineInventories
├── 8-label-clusters.sh                 # Step 8: Label Fleet clusters
└── yaml/                                # YAML configuration files
    ├── site-a-registration.yaml         # MachineRegistration for Site A
    ├── site-b-registration.yaml         # MachineRegistration for Site B
    ├── vms-config-2-sites.csv           # VM configuration
    ├── clustergroup-site-a.yaml        # Fleet ClusterGroup for Site A
    ├── clustergroup-site-b.yaml        # Fleet ClusterGroup for Site B
    ├── gitrepo-site-a.yaml             # Fleet GitRepo for Site A
    └── gitrepo-site-b.yaml             # Fleet GitRepo for Site B
```

## Quick Start

See `DEPLOYMENT-GUIDE.md` for complete instructions.

### Quick Deployment Sequence

```bash
# Step 1: Clean previous deployment (build-srv)
./1-cleanup-vms.sh

# Step 2: Create registration endpoints (rancher)
export KUBECONFIG=/etc/rancher/rke2/rke2.yaml
./2-create-registration-endpoints.sh

# Step 3: Build ISOs (build-srv)
./3-build-isos-2-sites.sh

# Step 4: Create Rancher resources (rancher)
export KUBECONFIG=/etc/rancher/rke2/rke2.yaml
./4-create-rancher-resources.sh

# Step 5: Create Fleet resources (rancher)
export KUBECONFIG=/etc/rancher/rke2/rke2.yaml
./5-create-fleet-resources.sh

# Step 6: Create and start VMs (build-srv)
./6-create-vms-2-sites.sh --parallel

# Step 7: Apply labels to MachineInventories (rancher - OPTIONAL)
# Wait ~10 minutes for VMs to register
export KUBECONFIG=/etc/rancher/rke2/rke2.yaml
./7-apply-machineinventory-labels.sh

# Step 8: Label Fleet clusters (rancher - CRITICAL)
# Wait ~25 minutes for clusters to be Ready
./8-label-clusters.sh
```

## Scripts

All scripts are numbered according to their step in the deployment process:

- **1-cleanup-vms.sh**: Removes all VMs, ISOs, and Rancher/Fleet resources
- **2-create-registration-endpoints.sh**: Creates MachineRegistrations and downloads Elemental config files (REQUIRED before Step 3)
- **3-build-isos-2-sites.sh**: Builds ISOs with Elemental configuration for both sites (REQUIRES config files from Step 2)
- **4-create-rancher-resources.sh**: Creates MachineInventorySelectorTemplates and Clusters (requires ztp-precreate.sh)
- **5-create-fleet-resources.sh**: Creates Fleet ClusterGroups and GitRepos
- **6-create-vms-2-sites.sh**: Creates and starts all 10 VMs
- **7-apply-machineinventory-labels.sh**: Applies labels to MachineInventories (optional if machineInventoryLabels configured)
- **8-label-clusters.sh**: Labels Fleet clusters (critical step)

## YAML Files

All YAML configuration files are in the `yaml/` subdirectory:

- **MachineRegistrations**: `site-a-registration.yaml`, `site-b-registration.yaml`
- **VM Configuration**: `vms-config-2-sites.csv`
- **Fleet Resources**: `clustergroup-site-a.yaml`, `clustergroup-site-b.yaml`, `gitrepo-site-a.yaml`, `gitrepo-site-b.yaml`

## Prerequisites

- Rancher Management Server running
- EIB environment configured
- libvirt/KVM installed
- Network bridge br0 configured (10.19.10.11/24) with physical interface connected
- Git repository accessible from Rancher
- kubectl configured with Rancher kubeconfig
- jq installed (for Step 4)

## Server Requirements

Steps are split between two servers:
- **build-srv (uterrie)**: Steps 1, 3, 6 (VM creation and ISO building)
- **rancher**: Steps 2, 4, 5, 7, 8 (Rancher resource management)

## Notes

- Step 4 requires `ztp-precreate.sh` from `../ztp-scale-nodes/` directory
- Step 7 is optional if MachineRegistrations include `machineInventoryLabels` with `hostname: ${Runtime/Hostname}`
- Step 8 is critical and must be run after clusters are Ready (~25 minutes after Step 6)

## Total Deployment Time

~35-40 minutes from VM creation (Step 6) to workloads running.


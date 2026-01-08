# Deployment Guide - 2 Sites with 10 VMs

Deploy 10 VMs across 2 sites, each running single-node Kubernetes clusters with site-specific workloads via Fleet GitOps.

## Architecture

- **Site A**: 5 VMs → 5 single-node K3s clusters → `demo-workload-site-a` workload
- **Site B**: 5 VMs → 5 single-node K3s clusters → `demo-workload-site-b` workload

## Prerequisites

- Rancher Management Server running
- EIB environment configured
- libvirt/KVM installed
- Network bridge br0 configured (10.19.10.11/24) with physical interface connected
- Git repository accessible from Rancher
- Kubectl configured with Rancher kubeconfig

## VM Configuration

The deployment uses the following configuration defined in `vms-config-2-sites.csv`:

| Site | VM Name | Hostname | Labels |
|------|---------|----------|--------|
| A | site-a-vm-01 | node1-sitea | site-id=site-a, test-group=2-sites-5-vms |
| A | site-a-vm-02 | node2-sitea | site-id=site-a, test-group=2-sites-5-vms |
| A | site-a-vm-03 | node3-sitea | site-id=site-a, test-group=2-sites-5-vms |
| A | site-a-vm-04 | node4-sitea | site-id=site-a, test-group=2-sites-5-vms |
| A | site-a-vm-05 | node5-sitea | site-id=site-a, test-group=2-sites-5-vms |
| B | site-b-vm-01 | node1-siteb | site-id=site-b, test-group=2-sites-5-vms |
| B | site-b-vm-02 | node2-siteb | site-id=site-b, test-group=2-sites-5-vms |
| B | site-b-vm-03 | node3-siteb | site-id=site-b, test-group=2-sites-5-vms |
| B | site-b-vm-04 | node4-siteb | site-id=site-b, test-group=2-sites-5-vms |
| B | site-b-vm-05 | node5-siteb | site-id=site-b, test-group=2-sites-5-vms |

**Common configuration:** Namespace `fleet-default`, K3s `v1.33.5+k3s1`, single-node (1 CP, 0 workers), no VIP.

## Deployment Steps

***** Important *****: Steps are split between two servers:
- **build-srv (uterrie)**: VM creation and ISO building
- **rancher**: Rancher resource management

---

### Step 1: Clean Previous Deployment (build-srv)

```bash
cd /home/tofix/LAB/EIB-demo/scale-out-eib-elemental/test-10-VMs
./cleanup-vms.sh
```

Removes all VMs, ISOs, and Rancher/Fleet resources.

---

### Step 2: Create Registration Endpoints (rancher)

***** Important *****: This step must be done **on the Rancher server** before building ISOs.

**Prerequisites**: Before building ISOs (Step 3), you must have the Elemental configuration files:
- `generated/elemental/elemental_config-site-a.yaml` (REQUIRED for Site A ISO build)
- `generated/elemental/elemental_config-site-b.yaml` (REQUIRED for Site B ISO build)

***** Why these files are needed *****: These configuration files contain:
- Registration endpoint URLs (unique per site)
- CA certificates for secure registration
- Installation and reset configuration

These are **embedded in the ISOs during build** (Step 3), so VMs can automatically register with Rancher when they boot.

**If these files don't exist:**

**Option 1: Create Registration Endpoints (recommended - automated):**
```bash
cd /home/tofix/LAB/EIB-demo/scale-out-eib-elemental/test-10-VMs/scenario
export KUBECONFIG=/etc/rancher/rke2/rke2.yaml
./2-create-registration-endpoints.sh
```

This script will:
1. Apply MachineRegistrations for site-a and site-b
2. Wait for registration URLs to be generated
3. Automatically download `elemental_config.yaml` from each endpoint
4. Save them as `generated/elemental/elemental_config-site-a.yaml` and `generated/elemental/elemental_config-site-b.yaml`

**If automatic download fails**, the script provides instructions to download manually from Rancher UI.

**Alternative: Apply MachineRegistrations only (manual download required):**
```bash
cd /home/tofix/LAB/EIB-demo/scale-out-eib-elemental/test-10-VMs/scenario
export KUBECONFIG=/etc/rancher/rke2/rke2.yaml
kubectl apply -f yaml/site-a-registration.yaml yaml/site-b-registration.yaml
```

Then download `elemental_config.yaml` from each endpoint manually and save as:
- `generated/elemental/elemental_config-site-a.yaml`
- `generated/elemental/elemental_config-site-b.yaml`

**Option 2: Create manually in Rancher UI:**
1. Create Registration Endpoints in Rancher UI (Elemental → Registration Endpoints) **with `machineInventoryLabels` configured**:
   - For `site-a-registration`: 
     ```yaml
     machineInventoryLabels:
       site-id: site-a
       test-group: 2-sites-5-vms
       hostname: ${Runtime/Hostname}
     ```
   - For `site-b-registration`:
     ```yaml
     machineInventoryLabels:
       site-id: site-b
       test-group: 2-sites-5-vms
       hostname: ${Runtime/Hostname}
     ```
2. Download `elemental_config.yaml` from each endpoint
3. Save them as `generated/elemental/elemental_config-site-a.yaml` and `generated/elemental/elemental_config-site-b.yaml`

***** Note *****: MachineRegistration YAML files are available in `scenario/yaml/` directory.

***** Important *****: If MachineRegistrations include `machineInventoryLabels` with `hostname: ${Runtime/Hostname}`, Step 6 is **not needed** as all labels (`site-id`, `test-group`, `hostname`) are applied automatically during VM registration. The `hostname` label will use the OS hostname set by `60-set-hostname.sh`.

---

### Step 3: Build ISOs (build-srv)

**On build-srv (uterrie):**

After the registration endpoints are created and config files are downloaded, build the ISOs.

***** Prerequisites *****: This step **REQUIRES** the following files (created in Step 2):
- `generated/elemental/elemental_config-site-a.yaml` (REQUIRED for Site A ISO)
- `generated/elemental/elemental_config-site-b.yaml` (REQUIRED for Site B ISO)

These files contain the registration endpoints and CA certificates that are embedded in the ISOs during build.

**Action:**
```bash
cd /home/tofix/LAB/EIB-demo/scale-out-eib-elemental/test-10-VMs/scenario
./3-build-isos-2-sites.sh
```

**What the script does:**
1. Verifies both config files exist (exits with error if missing)
2. Builds ISO for Site A using `elemental_config-site-a.yaml`
3. Builds ISO for Site B using `elemental_config-site-b.yaml`
4. Outputs ISOs to `output/vm-rancher-fleet-scale-site-a.iso` and `output/vm-rancher-fleet-scale-site-b.iso`

***** Duration *****: ~10 minutes. Builds ISOs with hostname mapping script for both sites.

**If config files are missing:**
The script will exit with an error message. Run Step 2 first:
```bash
export KUBECONFIG=/etc/rancher/rke2/rke2.yaml
./2-create-registration-endpoints.sh
```

---

### Step 4: Create Rancher Resources (rancher)

**On Rancher server:**

Create MachineInventorySelectorTemplates and Clusters BEFORE VMs boot so Rancher knows how to provision them.

**Prerequisites:**
```bash
# Install jq if not present
zypper in jq

# Set kubeconfig
export KUBECONFIG=/etc/rancher/rke2/rke2.yaml
```

**Action:**
```bash
cd /home/tofix/LAB/EIB-demo/scale-out-eib-elemental/test-10-VMs/scenario
export KUBECONFIG=/etc/rancher/rke2/rke2.yaml
./4-create-rancher-resources.sh
```

**Note**: This script uses `ztp-precreate.sh` from `../ztp-scale-nodes/` directory. Make sure it exists before running.

**What gets created:**
- 10 `MachineInventorySelectorTemplate` resources (one per VM)
- 10 `Cluster` resources (one per VM)

**Verification:**
```bash
# Check MachineInventorySelectorTemplates
kubectl get machineinventoryselectortemplate -n fleet-default -l test-group=2-sites-5-vms
# Should show 10 once VM created

# Check Clusters
kubectl get cluster -n fleet-default -l test-group=2-sites-5-vms
# Should show 10
```

***** Why *****: These resources must exist BEFORE VMs boot. When VMs register, Rancher will match MachineInventories to these SelectorTemplates and provision clusters.

---

### Step 5: Create Fleet Resources (rancher)

**On Rancher server:**

Create Fleet ClusterGroups and GitRepos so Fleet knows which clusters belong to which site and can deploy the correct workloads.

```bash
cd /home/tofix/LAB/EIB-demo/scale-out-eib-elemental/test-10-VMs/scenario
export KUBECONFIG=/etc/rancher/rke2/rke2.yaml
./5-create-fleet-resources.sh
```

**What gets created:**
- `clustergroup-site-a`: Selects clusters with `site-id` matching site-a-vm-01 to site-a-vm-05
- `clustergroup-site-b`: Selects clusters with `site-id` matching site-b-vm-01 to site-b-vm-05
- `gitrepo-site-a`: Deploys `demo-workload-site-a` to Site A clusters
- `gitrepo-site-b`: Deploys `demo-workload-site-b` to Site B clusters

**Verification:**
```bash
# Check ClusterGroups (should be 2)
kubectl get clustergroup -n fleet-default | grep site-

# Check GitRepos (should be 2)
kubectl get gitrepo -n fleet-default | grep site-
```

**Why**: Fleet needs to know which clusters belong to which site to deploy the correct workloads. ClusterGroups select clusters by labels, and GitRepos deploy workloads to matching ClusterGroups.

**Important**: After VMs boot and clusters are provisioned, you must label the Fleet clusters using `label-clusters.sh` (see Step 7).

---

### Step 6: Create and Start VMs (build-srv)

**On build-srv (uterrie):**

Create and boot the VMs so they can register with Rancher.

```bash
cd /home/tofix/LAB/EIB-demo/scale-out-eib-elemental/test-10-VMs/scenario

# Create all 10 VMs (parallel mode for faster creation)
./6-create-vms-2-sites.sh --parallel
```

**What happens:**
1. VMs are created with libvirt using `virt-install`
2. Each VM gets the appropriate ISO attached (site-a or site-b)
3. VMs boot and run the hostname script during combustion
4. NetworkManager starts and requests DHCP from external server via br0
5. VMs get IP addresses from external DHCP server (10.19.10.0/24 network)
6. VMs register with Rancher using the registration endpoint

**Verification:**
```bash
# Check VMs are running
virsh --connect qemu:///system list | grep site-
# Should show 10 VMs running

# Check VM IPs (may take 2-5 minutes)
for vm in site-a-vm-01 site-a-vm-02 site-b-vm-01; do 
    echo "$vm:"; 
    virsh --connect qemu:///system domifaddr "$vm" 2>/dev/null || echo "  No IP yet"; 
done
```

---

### Step 7: Apply Labels to MachineInventories (rancher - OPTIONAL)

**On Rancher server:**

***** When to run *****: After VMs have registered (MachineInventories exist) - typically ~5-10 minutes after Step 6.

***** Note *****: If MachineRegistrations include `machineInventoryLabels` with `hostname: ${Runtime/Hostname}` (recommended), this step is **not needed** as all labels (`site-id`, `test-group`, `hostname`) are applied automatically during registration. The `hostname` label will use the OS hostname set by `60-set-hostname.sh` (e.g., `node1-sitea`, `node2-sitea`, etc.).

***** Why this step may be needed *****: If Registration Endpoints don't have `machineInventoryLabels` configured with the `hostname` template variable, MachineInventories will be created without the `hostname` label. The SelectorTemplates require specific labels (`hostname`, `site-id`, `test-group`) to match MachineInventories to Clusters.

**Action:**
```bash
export KUBECONFIG=/etc/rancher/rke2/rke2.yaml

cd /home/tofix/LAB/EIB-demo/scale-out-eib-elemental/test-10-VMs/scenario

# Apply labels to all MachineInventories
./7-apply-machineinventory-labels.sh
```

**What the script does:**
1. Gets all MachineInventory IPs
2. Maps them to VMs (by order)
3. Applies the correct labels:
   - `hostname`: node1-sitea, node2-sitea, etc.
   - `site-id`: site-a-vm-01, site-a-vm-02, etc.
   - `test-group`: 2-sites-5-vms

**Verification:**
```bash
# Check labels are applied
kubectl get machineinventory -n fleet-default -o custom-columns=NAME:.metadata.name,HOSTNAME:.metadata.labels.hostname,SITE-ID:.metadata.labels.site-id
# Should show all MachineInventories with labels

# Check MachineInventorySelectors are created automatically
kubectl get machineinventoryselector -n fleet-default | grep site-
# Should show 10 MachineInventorySelectors
```

**Expected Output**: All MachineInventories should have `hostname`, `site-id`, and `test-group` labels.

---

### Step 8: Label Fleet Clusters (rancher - CRITICAL)

**On Rancher server:**

***** When to run *****: After clusters are Ready (~25 minutes after Step 6).

Ensure Fleet clusters have the correct labels so ClusterGroups can select them.

***** Why this step is needed *****: Fleet uses its own cluster resources (`clusters.fleet.cattle.io`) separate from provisioning clusters. ClusterGroups select based on Fleet cluster labels, not provisioning cluster labels.

**Action:**
```bash
export KUBECONFIG=/etc/rancher/rke2/rke2.yaml

cd /home/tofix/LAB/EIB-demo/scale-out-eib-elemental/test-10-VMs/scenario

# Label Fleet clusters
./8-label-clusters.sh
```

**What the script does:**
1. Labels Fleet clusters (`clusters.fleet.cattle.io`) with `site-id` and `test-group`
2. Also labels provisioning clusters for consistency
3. Verifies ClusterGroup cluster counts

**Verification:**
```bash
# Check Fleet cluster labels
kubectl get clusters.fleet.cattle.io -n fleet-default -o custom-columns=NAME:.metadata.name,SITE-ID:.metadata.labels.site-id,TEST-GROUP:.metadata.labels.test-group | grep site-

# Check ClusterGroup status
kubectl get clustergroup demo-workload-site-a -n fleet-default -o jsonpath='{.status.clusterCount}'
# Should show: 5
kubectl get clustergroup demo-workload-site-b -n fleet-default -o jsonpath='{.status.clusterCount}'
# Should show: 5
```

**Expected Output**: ClusterGroups should show 5 clusters each, and workloads should start deploying.

---

### Step 9: Monitor Deployment Progress

**Timeline** (from Step 6 - VM creation):
- 0-2 min: VMs booting (hostnames set by 60-set-hostname.sh)
- 2-5 min: VMs get IPs from external DHCP
- 5-10 min: VMs register with Rancher (MachineInventories appear with labels if `machineInventoryLabels` configured)
- **~10 min: Step 7 - Apply labels to MachineInventories (rancher - OPTIONAL if machineInventoryLabels configured)**
- 12-15 min: MachineInventorySelectors created automatically
- 15-25 min: Clusters provision (K3s installation)
- **~25 min: Step 8 - Label Fleet clusters (rancher - CRITICAL)**
- 27-30 min: Workloads deploy via Fleet
- 30-35 min: Pods scheduled and running

**Monitoring commands:**

```bash
export KUBECONFIG=/etc/rancher/rke2/rke2.yaml

# Check MachineInventories
kubectl get machineinventory -n fleet-default -o wide

# Check Clusters status
kubectl get cluster -n fleet-default -l test-group=2-sites-5-vms

# Check Fleet clusters
kubectl get clusters.fleet.cattle.io -n fleet-default -l test-group=2-sites-5-vms

# Check ClusterGroups
kubectl get clustergroup -n fleet-default | grep site-

# Check GitRepos
kubectl get gitrepo -n fleet-default | grep site-

# Check workloads
kubectl get deployment -n demo-workload-site-a
kubectl get deployment -n demo-workload-site-b

# Check pods
kubectl get pods -n demo-workload-site-a
kubectl get pods -n demo-workload-site-b
```

---

## Troubleshooting

### VMs Not Getting IP Addresses

***** Problem *****: VMs are running but have no IP addresses.

***** Solution *****: Verify br0 bridge configuration:
```bash
# Check br0 has IP
ip addr show br0 | grep "inet 10.19.10.11/24"

# Check physical interface is connected to br0
ip link show enp19s0f3u2c2 | grep "master br0"

# If not configured, run:
cd /home/tofix/LAB/EIB-demo/scale-out-eib-elemental/test-10-VMs
sudo ./configure-bridge.sh
# Note: configure-bridge.sh is in the parent directory, not in scenario/
```

### Clusters Stuck in 'Updating' State

***** Problem *****: Clusters show "Waiting for viable init node" in Rancher UI.

***** Cause *****: MachineInventories are not labeled, preventing SelectorTemplates from matching them.

***** Solution *****: 
1. **If MachineRegistrations have `machineInventoryLabels`**: Labels should be applied automatically. Verify with `kubectl get machineinventory -n fleet-default --show-labels`
2. **If labels are missing**: Run Step 7 (`7-apply-machineinventory-labels.sh`) to apply labels manually, or update MachineRegistrations to include `machineInventoryLabels` in their spec.

### Workloads Not Deploying

***** Problem *****: ClusterGroups show 0 clusters or GitRepos show errors.

***** Causes and Solutions *****:
1. **Fleet clusters not labeled**: Run Step 8 (`8-label-clusters.sh`)
2. **Wrong Git branch**: Verify GitRepos use `branch: master` (not `main`)
3. **MetalLB not installed**: Remove MetalLB paths from GitRepos if not installed

**Verification:**
```bash
# Check Fleet cluster labels
kubectl get clusters.fleet.cattle.io -n fleet-default -o custom-columns=NAME:.metadata.name,SITE-ID:.metadata.labels.site-id

# Check ClusterGroup cluster counts
kubectl get clustergroup demo-workload-site-a -n fleet-default -o jsonpath='{.status.clusterCount}'
kubectl get clustergroup demo-workload-site-b -n fleet-default -o jsonpath='{.status.clusterCount}'
```

### Pods Stuck in Pending State

***** Problem *****: Pods are created but remain in Pending state.

***** Possible causes *****:
1. **Node resources insufficient**: Check node resources with `kubectl describe node`
2. **Image pull issues**: Check pod events with `kubectl describe pod`
3. **Network issues**: Verify pod can reach image registry

***** Solution *****: Check pod events:
```bash
kubectl describe pod <pod-name> -n demo-workload-site-a
```

---

## Quick Reference

**Complete deployment sequence:**

```bash
# Step 1: Clean previous deployment (build-srv)
cd /home/tofix/LAB/EIB-demo/scale-out-eib-elemental/test-10-VMs/scenario
./1-cleanup-vms.sh

# Step 2: Create registration endpoints (rancher)
export KUBECONFIG=/etc/rancher/rke2/rke2.yaml
cd /home/tofix/LAB/EIB-demo/scale-out-eib-elemental/test-10-VMs/scenario
./2-create-registration-endpoints.sh

# Step 3: Build ISOs (build-srv)
cd /home/tofix/LAB/EIB-demo/scale-out-eib-elemental/test-10-VMs/scenario
./3-build-isos-2-sites.sh

# Step 4: Create Rancher resources (rancher)
export KUBECONFIG=/etc/rancher/rke2/rke2.yaml
cd /home/tofix/LAB/EIB-demo/scale-out-eib-elemental/test-10-VMs/scenario
./4-create-rancher-resources.sh

# Step 5: Create Fleet resources (rancher)
export KUBECONFIG=/etc/rancher/rke2/rke2.yaml
cd /home/tofix/LAB/EIB-demo/scale-out-eib-elemental/test-10-VMs/scenario
./5-create-fleet-resources.sh

# Step 6: Create and start VMs (build-srv)
cd /home/tofix/LAB/EIB-demo/scale-out-eib-elemental/test-10-VMs/scenario
./6-create-vms-2-sites.sh --parallel

# Step 7: Apply labels to MachineInventories (rancher - OPTIONAL if machineInventoryLabels configured)
# Wait ~10 minutes for VMs to register
# (If MachineRegistrations have machineInventoryLabels, labels are applied automatically)
# Otherwise, run:
export KUBECONFIG=/etc/rancher/rke2/rke2.yaml
cd /home/tofix/LAB/EIB-demo/scale-out-eib-elemental/test-10-VMs/scenario
./7-apply-machineinventory-labels.sh

# Step 8: Label Fleet clusters (rancher - CRITICAL)
# Wait ~25 minutes for clusters to be Ready, then:
./8-label-clusters.sh
```

**Key files in scenario/ directory:**
- `1-cleanup-vms.sh`: Cleanup script
- `2-create-registration-endpoints.sh`: Create registration endpoints and download config files
- `3-build-isos-2-sites.sh`: ISO building script
- `6-create-vms-2-sites.sh`: VM creation script
- `7-apply-machineinventory-labels.sh`: Label MachineInventories (optional if machineInventoryLabels configured)
- `8-label-clusters.sh`: Label Fleet clusters

**Key files in scenario/yaml/ directory:**
- `vms-config-2-sites.csv`: VM configuration
- `site-a-registration.yaml`, `site-b-registration.yaml`: MachineRegistration definitions
- `clustergroup-site-a.yaml`, `clustergroup-site-b.yaml`: Fleet ClusterGroups
- `gitrepo-site-a.yaml`, `gitrepo-site-b.yaml`: Fleet GitRepos

**Other directories (in parent directory):**
- `generated/elemental/`: Elemental configuration files (elemental_config-site-a.yaml, elemental_config-site-b.yaml)
- `generated/manifests-2-sites/`: Generated Rancher manifests
- `output/`: EIB build ISOs

---

## Summary

This deployment creates 10 single-node K3s clusters across 2 sites, each running a site-specific workload. The process involves:

1. **Preparing infrastructure**: Clean previous deployment
2. **Creating registration endpoints**: Apply MachineRegistrations and download Elemental config files (on Rancher server)
3. **Building ISOs**: Build ISOs with Elemental configuration (on build-srv)
4. **Creating Rancher resources**: MachineInventorySelectorTemplates and Clusters (before VMs boot)
5. **Creating Fleet resources**: ClusterGroups and GitRepos (before VMs boot)
6. **Creating VMs**: Boot VMs and let them register with Rancher
7. **Labeling resources**: Apply labels to MachineInventories (optional if machineInventoryLabels configured) and Fleet clusters (critical)
8. **Monitoring**: Wait for clusters to provision and workloads to deploy

**Total deployment time**: ~35-40 minutes from VM creation to workloads running.


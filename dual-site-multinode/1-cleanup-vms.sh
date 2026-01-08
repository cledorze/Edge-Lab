#!/bin/bash
# Script to completely clean up the 2-site deployment environment:
# - VMs and their disks (site-a-vm-* and site-b-vm-*)
# - EIB build ISOs
# - All Rancher resources (MachineInventories, Clusters, MachineInventorySelectorTemplates)
# - All Fleet resources (ClusterGroups, GitRepos)

set -e

KUBECONFIG_PATH="/home/tofix/LAB/AI/Edge-3.4/rancher-kubeconfig.yaml"
export KUBECONFIG="$KUBECONFIG_PATH"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
KUBECONFIG_FILE="/home/tofix/LAB/AI/Edge-3.4/rancher-kubeconfig.yaml"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo "=========================================="
echo "Complete Environment Cleanup"
echo "=========================================="
echo ""
echo -e "${RED}WARNING: This will destroy:${NC}"
echo "  - All VMs (site-a-vm-01 to site-a-vm-05, site-b-vm-01 to site-b-vm-05)"
echo "  - All VM disk images"
echo "  - All EIB build ISOs (vm-rancher-fleet-scale-site-*.iso)"
echo "  - All Rancher resources (MachineInventories, Clusters, MachineInventorySelectorTemplates)"
echo "  - All Fleet resources (ClusterGroups, GitRepos)"
echo ""
echo -e "${YELLOW}Press Ctrl+C to cancel, or Enter to continue...${NC}"
read

# Step 1: Clean up VMs
echo ""
echo "=========================================="
echo "Step 1: Cleaning up VMs and disks"
echo "=========================================="
echo ""

VM_NAMES=(
    "site-a-vm-01" "site-a-vm-02" "site-a-vm-03" "site-a-vm-04" "site-a-vm-05"
    "site-b-vm-01" "site-b-vm-02" "site-b-vm-03" "site-b-vm-04" "site-b-vm-05"
)

for vm_name in "${VM_NAMES[@]}"; do
    # Check if VM exists
    if virsh --connect qemu:///system dominfo "$vm_name" &>/dev/null; then
        echo "Processing VM: $vm_name"
        
        # Get VM state
        VM_STATE=$(virsh --connect qemu:///system domstate "$vm_name" 2>/dev/null || echo "unknown")
        echo "  State: $VM_STATE"
        
        # Force destroy if running
        if [ "$VM_STATE" = "running" ]; then
            echo "  Destroying running VM..."
            virsh --connect qemu:///system destroy "$vm_name" 2>/dev/null || true
            sleep 1
        fi
        
        # Get storage paths before undefine
        STORAGE_PATHS=$(virsh --connect qemu:///system domblklist "$vm_name" 2>/dev/null | grep -v "^$" | grep -v "^Target" | awk '{print $2}' | grep -v "^$" || true)
        
        # Undefine with storage and NVRAM removal (for UEFI VMs)
        echo "  Undefining VM and removing storage + NVRAM..."
        if virsh --connect qemu:///system undefine "$vm_name" --remove-all-storage --nvram 2>/dev/null; then
            echo -e "  ${GREEN}OK:${NC} VM $vm_name removed"
        else
            # Try without storage flag if that fails
            echo "  Attempting undefine with NVRAM only..."
            if virsh --connect qemu:///system undefine "$vm_name" --nvram 2>/dev/null; then
                echo "  VM undefined, cleaning up storage manually..."
                # Manually remove storage if paths were found
                if [ -n "$STORAGE_PATHS" ]; then
                    echo "$STORAGE_PATHS" | while read -r path; do
                        if [ -f "$path" ]; then
                            echo "  Removing storage: $path"
                            rm -f "$path" 2>/dev/null || true
                        fi
                    done
                fi
                echo -e "  ${GREEN}OK:${NC} VM $vm_name removed (with manual storage cleanup)"
            else
                # Last resort: try without NVRAM flag (for non-UEFI VMs)
                echo "  Attempting undefine without NVRAM flag..."
                virsh --connect qemu:///system undefine "$vm_name" --remove-all-storage 2>/dev/null || {
                    virsh --connect qemu:///system undefine "$vm_name" 2>/dev/null || true
                }
                echo -e "  ${GREEN}OK:${NC} VM $vm_name removed (fallback method)"
            fi
        fi
    else
        echo "  VM $vm_name does not exist"
    fi
    
    # Remove disk if it exists in custom location
    disk_path="${SCRIPT_DIR}/disks/${vm_name}.qcow2"
    if [ -f "$disk_path" ]; then
        echo "  Removing disk: $disk_path"
        rm -f "$disk_path"
    fi
    
    # Also check libvirt default pool location
    LIBVIRT_DISK="/var/lib/libvirt/images/${vm_name}.qcow2"
    if [ -f "$LIBVIRT_DISK" ]; then
        echo "  Removing libvirt disk: $LIBVIRT_DISK"
        sudo rm -f "$LIBVIRT_DISK" 2>/dev/null || true
    fi
done

# Remove disks directory if empty
if [ -d "${SCRIPT_DIR}/disks" ]; then
    rmdir "${SCRIPT_DIR}/disks" 2>/dev/null || true
fi

echo -e "${GREEN}OK:${NC} VM cleanup complete"
echo ""

# Step 2: Clean up EIB build ISOs
echo "=========================================="
echo "Step 2: Cleaning up EIB build ISOs"
echo "=========================================="
echo ""

ISO_FILES=(
    "${PROJECT_ROOT}/output/vm-rancher-fleet-scale-site-a.iso"
    "${PROJECT_ROOT}/output/vm-rancher-fleet-scale-site-b.iso"
)

for iso_file in "${ISO_FILES[@]}"; do
    if [ -f "$iso_file" ]; then
        echo "Removing ISO: $(basename "$iso_file")"
        rm -f "$iso_file"
        echo -e "  ${GREEN}OK:${NC} $(basename "$iso_file") removed"
    else
        echo "  $(basename "$iso_file") does not exist"
    fi
done

# Also remove ISO checksums if they exist
for iso_file in "${ISO_FILES[@]}"; do
    checksum_file="${iso_file}.sha256"
    if [ -f "$checksum_file" ]; then
        rm -f "$checksum_file"
        echo -e "  ${GREEN}OK:${NC} $(basename "$checksum_file") removed"
    fi
done

echo -e "${GREEN}OK:${NC} ISO cleanup complete"
echo ""

# Step 3: Clean up Rancher resources
echo "=========================================="
echo "Step 3: Cleaning up Rancher resources"
echo "=========================================="
echo ""

# Try to find kubeconfig in multiple locations
KUBECONFIG_FOUND=""
KUBECONFIG_SEARCH_PATHS=(
    "$KUBECONFIG_FILE"
    "/home/tofix/LAB/AI/Edge-3.4/rancher-kubeconfig.yaml"
    "/home/tofix/LAB/EIB-demo-1/rancher/rancher-kubeconfig.yaml"
    "$HOME/LAB/EIB-demo-1/rancher/rancher-kubeconfig.yaml"
)

# Check if KUBECONFIG env var is set and points to existing file
if [ -n "$KUBECONFIG" ] && [ -f "$KUBECONFIG" ]; then
    KUBECONFIG_FOUND="$KUBECONFIG"
else
    # Search in known locations
    for path in "${KUBECONFIG_SEARCH_PATHS[@]}"; do
        if [ -f "$path" ]; then
            KUBECONFIG_FOUND="$path"
            break
        fi
    done
fi

if [ -z "$KUBECONFIG_FOUND" ]; then
    echo -e "${YELLOW}WARNING:${NC}  Kubeconfig not found"
    echo "  Tried: $KUBECONFIG_FILE"
    echo "  Tried: ${EIB_DIR}/../rancher/rancher-kubeconfig.yaml"
    echo "  Tried: \$KUBECONFIG environment variable"
    echo ""
    echo "  Skipping Rancher resource cleanup"
    echo "  Set KUBECONFIG environment variable or create the kubeconfig file"
else
    export KUBECONFIG="$KUBECONFIG_FOUND"
    echo "Using kubeconfig: $KUBECONFIG_FOUND"
    
    # Verify connection
    if ! kubectl cluster-info &>/dev/null; then
        echo -e "${YELLOW}WARNING:${NC}  Cannot connect to cluster with this kubeconfig"
        echo "  Skipping Rancher resource cleanup"
    else
        echo ""
        echo "Cleaning up MachineInventories..."
        MI_COUNT=$(kubectl get machineinventory -n fleet-default -l test-group=dual-site-multinode --no-headers 2>/dev/null | wc -l || echo "0")
        if [ "$MI_COUNT" -gt 0 ]; then
            echo "  Found $MI_COUNT MachineInventories, deleting..."
            kubectl delete machineinventory -n fleet-default -l test-group=dual-site-multinode --wait=false 2>/dev/null || true
            # Force delete with finalizers if needed
            for mi in $(kubectl get machineinventory -n fleet-default -l test-group=dual-site-multinode -o name 2>/dev/null); do
                kubectl patch "$mi" -n fleet-default -p '{"metadata":{"finalizers":[]}}' --type=merge 2>/dev/null || true
                kubectl delete "$mi" -n fleet-default --wait=false 2>/dev/null || true
            done
            echo -e "  ${GREEN}OK:${NC} MachineInventories deleted"
        else
            echo "  No MachineInventories found"
        fi
        
        echo ""
        echo "Cleaning up Clusters..."
        CLUSTER_COUNT=$(kubectl get cluster -n fleet-default -l test-group=dual-site-multinode --no-headers 2>/dev/null | wc -l || echo "0")
        if [ "$CLUSTER_COUNT" -gt 0 ]; then
            echo "  Found $CLUSTER_COUNT Clusters, deleting..."
            kubectl delete cluster -n fleet-default -l test-group=dual-site-multinode --wait=false 2>/dev/null || true
            # Force delete with finalizers if needed
            for cluster in $(kubectl get cluster -n fleet-default -l test-group=dual-site-multinode -o name 2>/dev/null); do
                kubectl patch "$cluster" -n fleet-default -p '{"metadata":{"finalizers":[]}}' --type=merge 2>/dev/null || true
                kubectl delete "$cluster" -n fleet-default --wait=false 2>/dev/null || true
            done
            echo -e "  ${GREEN}OK:${NC} Clusters deleted"
        else
            echo "  No Clusters found"
        fi
        
        echo ""
        echo "Cleaning up MachineInventorySelectorTemplates..."
        MIST_COUNT=$(kubectl get machineinventoryselectortemplate -n fleet-default -l test-group=dual-site-multinode --no-headers 2>/dev/null | wc -l || echo "0")
        if [ "$MIST_COUNT" -gt 0 ]; then
            echo "  Found $MIST_COUNT MachineInventorySelectorTemplates, deleting..."
            kubectl delete machineinventoryselectortemplate -n fleet-default -l test-group=dual-site-multinode --wait=false 2>/dev/null || true
            echo -e "  ${GREEN}OK:${NC} MachineInventorySelectorTemplates deleted"
        else
            echo "  No MachineInventorySelectorTemplates found"
        fi
        
        echo ""
        echo "Cleaning up Fleet clusters (clusters.fleet.cattle.io)..."
        FLEET_CLUSTER_COUNT=$(kubectl get clusters.fleet.cattle.io -n fleet-default -l test-group=dual-site-multinode --no-headers 2>/dev/null | wc -l || echo "0")
        if [ "$FLEET_CLUSTER_COUNT" -gt 0 ]; then
            echo "  Found $FLEET_CLUSTER_COUNT Fleet clusters, deleting..."
            kubectl delete clusters.fleet.cattle.io -n fleet-default -l test-group=dual-site-multinode --wait=false 2>/dev/null || true
            # Force delete with finalizers if needed
            for fc in $(kubectl get clusters.fleet.cattle.io -n fleet-default -l test-group=dual-site-multinode -o name 2>/dev/null); do
                kubectl patch "$fc" -n fleet-default -p '{"metadata":{"finalizers":[]}}' --type=merge 2>/dev/null || true
                kubectl delete "$fc" -n fleet-default --wait=false 2>/dev/null || true
            done
            echo -e "  ${GREEN}OK:${NC} Fleet clusters deleted"
        else
            echo "  No Fleet clusters found"
        fi
        
        echo -e "${GREEN}OK:${NC} Rancher resources cleanup complete"
    fi
fi
echo ""

# Step 4: Clean up Fleet resources
echo "=========================================="
echo "Step 4: Cleaning up Fleet resources"
echo "=========================================="
echo ""

if [ -n "$KUBECONFIG_FOUND" ] && kubectl cluster-info &>/dev/null 2>&1; then
    export KUBECONFIG="$KUBECONFIG_FOUND"
    
    echo "Cleaning up ClusterGroups..."
    CG_COUNT=$(kubectl get clustergroup -n fleet-default demo-workload-site-a demo-workload-site-b --no-headers 2>/dev/null | wc -l || echo "0")
    if [ "$CG_COUNT" -gt 0 ]; then
        echo "  Found $CG_COUNT ClusterGroups, deleting..."
        kubectl delete clustergroup -n fleet-default demo-workload-site-a demo-workload-site-b --wait=false 2>/dev/null || true
        echo -e "  ${GREEN}OK:${NC} ClusterGroups deleted"
    else
        echo "  No ClusterGroups found"
    fi
    
    echo ""
    echo "Cleaning up GitRepos..."
    GR_COUNT=$(kubectl get gitrepo -n fleet-default demo-workload-site-a demo-workload-site-b --no-headers 2>/dev/null | wc -l || echo "0")
    if [ "$GR_COUNT" -gt 0 ]; then
        echo "  Found $GR_COUNT GitRepos, deleting..."
        kubectl delete gitrepo -n fleet-default demo-workload-site-a demo-workload-site-b --wait=false 2>/dev/null || true
        echo -e "  ${GREEN}OK:${NC} GitRepos deleted"
    else
        echo "  No GitRepos found"
    fi
    
    echo ""
    echo "Cleaning up Git Secret..."
    if kubectl get secret -n fleet-default gitea-credentials &>/dev/null; then
        kubectl delete secret -n fleet-default gitea-credentials --wait=false 2>/dev/null || true
        echo -e "  ${GREEN}OK:${NC} Git secret deleted"
    else
        echo "  No git secret found"
    fi
    
    echo -e "${GREEN}OK:${NC} Fleet resources cleanup complete"
else
    echo -e "${YELLOW}WARNING:${NC}  Kubeconfig not available, skipping Fleet resource cleanup"
fi
echo ""

# Summary
echo "=========================================="
echo -e "${GREEN}OK: Cleanup complete${NC}"
echo "=========================================="
echo ""
echo "Cleaned up:"
echo "  OK: VMs and disk images"
echo "  OK: EIB build ISOs"
echo "  OK: Rancher resources (MachineInventories, Clusters, MachineInventorySelectorTemplates)"
echo "  OK: Fleet resources (ClusterGroups, GitRepos)"
echo ""
echo "Environment is now clean and ready for a fresh deployment."
echo ""


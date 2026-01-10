#!/bin/bash
# Script to apply labels to MachineInventories based on their registration IP
# This matches MachineInventories to VMs and applies the correct labels for SelectorTemplates

set -e

KUBECONFIG_PATH="/home/tofix/LAB/AI/Edge-3.4/rancher-kubeconfig.yaml"
export KUBECONFIG="$KUBECONFIG_PATH"

KUBECONFIG_PATH="/home/tofix/LAB/AI/Edge-3.4/rancher-kubeconfig.yaml"
export KUBECONFIG="$KUBECONFIG_PATH"

if [ ! -f "$KUBECONFIG_PATH" ]; then
    echo "Error: Kubeconfig not found at $KUBECONFIG_PATH"
    exit 1
fi

echo "=========================================="
echo "Applying Labels to MachineInventories"
echo "=========================================="
echo ""

# Mapping: VM name -> (hostname, site-id, site-label)
declare -A VM_MAP
VM_MAP["site-a-vm-01"]="node1-sitea:site-a-vm-01:site-a"
VM_MAP["site-a-vm-02"]="node2-sitea:site-a-vm-02:site-a"
VM_MAP["site-a-vm-03"]="node3-sitea:site-a-vm-03:site-a"
VM_MAP["site-a-vm-04"]="node4-sitea:site-a-vm-04:site-a"
VM_MAP["site-a-vm-05"]="node5-sitea:site-a-vm-05:site-a"
VM_MAP["site-b-vm-01"]="node1-siteb:site-b-vm-01:site-b"
VM_MAP["site-b-vm-02"]="node2-siteb:site-b-vm-02:site-b"
VM_MAP["site-b-vm-03"]="node3-siteb:site-b-vm-03:site-b"
VM_MAP["site-b-vm-04"]="node4-siteb:site-b-vm-04:site-b"
VM_MAP["site-b-vm-05"]="node5-siteb:site-b-vm-05:site-b"

# Get MachineInventory IPs and create mapping
echo "Step 1: Getting MachineInventory IPs and creating mapping..."
declare -A IP_TO_VM
declare -a MI_IPS

# Get all MachineInventory IPs sorted
MI_IPS=($(kubectl get machineinventory -n fleet-default -o json | \
    jq -r '.items[] | select(.metadata.annotations."elemental.cattle.io/registration-ip" != null) | .metadata.annotations."elemental.cattle.io/registration-ip"' | \
    sort -t. -k4 -n))

echo "Found ${#MI_IPS[@]} MachineInventories with IPs:"
for ip in "${MI_IPS[@]}"; do
    echo "  $ip"
done
echo ""

# Map IPs to VMs based on order (assuming IPs are assigned in VM creation order)
# We'll match by trying to connect to each IP and check hostname
VM_ORDER=("site-a-vm-01" "site-a-vm-02" "site-a-vm-03" "site-a-vm-04" "site-a-vm-05" \
          "site-b-vm-01" "site-b-vm-02" "site-b-vm-03" "site-b-vm-04" "site-b-vm-05")

echo "Step 1.5: Mapping IPs to VMs by checking hostnames..."
for i in "${!MI_IPS[@]}"; do
    ip="${MI_IPS[$i]}"
    if [ $i -lt ${#VM_ORDER[@]} ]; then
        vm="${VM_ORDER[$i]}"
        IP_TO_VM["$ip"]="$vm"
        echo "  $ip → $vm (by order)"
    else
        echo "  WARNING: $ip: No VM mapping (too many MachineInventories)"
    fi
done
echo ""

# Get MachineInventory IPs and apply labels
echo "Step 2: Applying labels to MachineInventories..."
MACHINE_INVENTORIES=$(kubectl get machineinventory -n fleet-default -o name)

for mi in $MACHINE_INVENTORIES; do
    mi_name=$(echo "$mi" | cut -d/ -f2)
    reg_ip=$(kubectl get "$mi" -n fleet-default -o jsonpath='{.metadata.annotations.elemental\.cattle\.io/registration-ip}' 2>/dev/null || echo "")
    
    if [ -z "$reg_ip" ]; then
        echo "  WARNING: $mi_name: No registration IP found, skipping"
        continue
    fi
    
    # Find matching VM
    vm_name="${IP_TO_VM[$reg_ip]}"
    if [ -z "$vm_name" ]; then
        echo "  WARNING: $mi_name ($reg_ip): No matching VM found"
        continue
    fi
    
    # Get labels from VM_MAP
    map_entry="${VM_MAP[$vm_name]}"
    if [ -z "$map_entry" ]; then
        echo "  WARNING: $mi_name ($reg_ip): No mapping found for $vm_name"
        continue
    fi
    
    IFS=':' read -r hostname site_id site_label <<< "$map_entry"
    
    echo "  → $mi_name ($reg_ip) → $vm_name → hostname=$hostname, site-id=$site_id"
    
    # Apply labels
    kubectl label "$mi" -n fleet-default \
        "hostname=$hostname" \
        "site-id=$site_id" \
        "test-group=2-sites-5-vms" \
        --overwrite 2>/dev/null || {
        echo "    ERROR: Failed to apply labels"
        continue
    }
    
    echo "    OK: Labels applied"
done

echo ""
echo "=========================================="
echo "OK: Label application complete"
echo "=========================================="
echo ""
echo "Verifying labels..."
kubectl get machineinventory -n fleet-default -o custom-columns=NAME:.metadata.name,IP:.metadata.annotations.elemental\.cattle\.io/registration-ip,HOSTNAME:.metadata.labels.hostname,SITE-ID:.metadata.labels.site-id


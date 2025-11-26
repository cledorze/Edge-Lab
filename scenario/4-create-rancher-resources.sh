#!/bin/bash
# Create Rancher Resources (MachineInventorySelectorTemplates and Clusters)
# Step 4 of DEPLOYMENT-GUIDE.md
#
# This script generates and applies Rancher manifests using ztp-precreate.sh
# It creates MachineInventorySelectorTemplates and Clusters BEFORE VMs boot
# so Rancher knows how to provision them.
#
# Usage: ./4-create-rancher-resources.sh

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
YAML_DIR="$SCRIPT_DIR/yaml"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
ZTP_SCRIPT="$PROJECT_ROOT/ztp-scale-nodes/ztp-precreate.sh"

echo "=========================================="
echo "Create Rancher Resources"
echo "Step 4 of DEPLOYMENT-GUIDE.md"
echo "=========================================="
echo ""

# Check prerequisites
if ! command -v kubectl &> /dev/null; then
    echo "ERROR: kubectl is not available"
    echo "   Configure KUBECONFIG: export KUBECONFIG=/etc/rancher/rke2/rke2.yaml"
    exit 1
fi

if ! command -v jq &> /dev/null; then
    echo "WARNING:  jq is not installed. Installing..."
    if command -v zypper &> /dev/null; then
        sudo zypper in -y jq
    else
        echo "ERROR: Please install jq manually"
        exit 1
    fi
fi

# Check cluster connection
if ! kubectl cluster-info &> /dev/null; then
    echo "ERROR: Cannot connect to Kubernetes cluster"
    echo "   Configure KUBECONFIG: export KUBECONFIG=/etc/rancher/rke2/rke2.yaml"
    exit 1
fi

# Check that ztp-precreate.sh exists
if [ ! -f "$ZTP_SCRIPT" ]; then
    echo "ERROR: ztp-precreate.sh not found at $ZTP_SCRIPT"
    echo "   Expected location: ztp-scale-nodes/ztp-precreate.sh"
    exit 1
fi

# Check that vms-config-2-sites.csv exists
if [ ! -f "$YAML_DIR/vms-config-2-sites.csv" ]; then
    echo "ERROR: vms-config-2-sites.csv not found in $YAML_DIR"
    exit 1
fi

echo "=== Generating and applying manifests ==="
echo ""

# Generate and apply manifests (MachineInventorySelectorTemplates + Clusters)
"$ZTP_SCRIPT" \
    --batch "$YAML_DIR/vms-config-2-sites.csv" \
    --output-dir "$PROJECT_ROOT/manifests-2-sites"

echo ""
echo "=== Verification ==="
echo ""

# Check MachineInventorySelectorTemplates
echo "MachineInventorySelectorTemplates:"
kubectl get machineinventoryselectortemplate -n fleet-default -l test-group=2-sites-5-vms || echo "  None found yet (will be created when VMs register)"

echo ""
echo "Clusters:"
kubectl get cluster -n fleet-default -l test-group=2-sites-5-vms || echo "  None found yet"

echo ""
echo "=========================================="
echo "OK: Rancher resources created"
echo "=========================================="
echo ""
echo "Note: These resources must exist BEFORE VMs boot."
echo "When VMs register, Rancher will match MachineInventories to these"
echo "SelectorTemplates and provision clusters."


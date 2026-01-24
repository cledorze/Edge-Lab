#!/bin/bash
# Create Rancher Resources (MachineInventorySelectorTemplates and Clusters)
# Step 4 of DEPLOYMENT-GUIDE.md
#
# This script generates and applies Rancher manifests using ztp-precreate.sh
# It creates MachineInventorySelectorTemplates and Clusters BEFORE VMs boot
# so Rancher knows how to provision them.
# It also creates Fleet resources (ClusterGroups and GitRepos) that reference
# the fleet folder from this git repository.
#
# Usage: ./4-create-rancher-resources.sh

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
YAML_DIR="$SCRIPT_DIR/yaml"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Resolve kubeconfig without hardcoded paths.
KUBECONFIG_PATH=""
if [ -n "${KUBECONFIG:-}" ] && [ -f "$KUBECONFIG" ]; then
    KUBECONFIG_PATH="$KUBECONFIG"
else
    for candidate in \
        "${PROJECT_ROOT}/rancher-kubeconfig.yaml" \
        "${PROJECT_ROOT}/../rancher-kubeconfig.yaml" \
        "/etc/rancher/rke2/rke2.yaml"; do
        if [ -f "$candidate" ]; then
            KUBECONFIG_PATH="$candidate"
            break
        fi
    done
fi

if [ -n "$KUBECONFIG_PATH" ]; then
    export KUBECONFIG="$KUBECONFIG_PATH"
fi

ZTP_SCRIPT="$PROJECT_ROOT/ztp-scale-nodes/ztp-precreate.sh"
FLEET_DIR=""
for candidate in "$PROJECT_ROOT/fleet" "$PROJECT_ROOT/../fleet"; do
    if [ -d "$candidate" ]; then
        FLEET_DIR="$candidate"
        break
    fi
done

echo "=========================================="
echo "Create Rancher Resources"
echo "Step 4 of DEPLOYMENT-GUIDE.md"
echo "=========================================="
echo ""

# Check prerequisites
if ! command -v kubectl &> /dev/null; then
    echo "ERROR: kubectl is not available"
    echo "   Configure KUBECONFIG (e.g., export KUBECONFIG=/etc/rancher/rke2/rke2.yaml)"
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
    echo "   Configure KUBECONFIG (e.g., export KUBECONFIG=/etc/rancher/rke2/rke2.yaml)"
    exit 1
fi

# Check required CRDs exist (Elemental + Fleet)
REQUIRED_CRDS=(
    "machineinventoryselectortemplates.elemental.cattle.io"
    "clusters.provisioning.cattle.io"
    "clustergroups.fleet.cattle.io"
    "gitrepos.fleet.cattle.io"
)

missing_crds=()
for crd in "${REQUIRED_CRDS[@]}"; do
    if ! kubectl get crd "$crd" &> /dev/null; then
        missing_crds+=("$crd")
    fi
done

if [ ${#missing_crds[@]} -gt 0 ]; then
    echo "ERROR: Required CRDs are missing: ${missing_crds[*]}"
    echo "   You are likely NOT connected to the Rancher management cluster."
    echo "   Set KUBECONFIG to the Rancher server kubeconfig and retry."
    echo "   Example: export KUBECONFIG=/etc/rancher/rke2/rke2.yaml"
    exit 1
fi

# Check that ztp-precreate.sh exists
if [ ! -f "$ZTP_SCRIPT" ]; then
    for candidate in "$PROJECT_ROOT/../ztp-scale-nodes/ztp-precreate.sh"; do
        if [ -f "$candidate" ]; then
            ZTP_SCRIPT="$candidate"
            break
        fi
    done
fi

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

# Check that fleet directory exists
if [ -z "$FLEET_DIR" ] || [ ! -d "$FLEET_DIR" ]; then
    echo "ERROR: fleet directory not found at $FLEET_DIR"
    echo "   Expected location: fleet/"
    exit 1
fi

# Check that fleet subdirectories exist
if [ ! -d "$FLEET_DIR/demo-workload-site-a" ]; then
    echo "ERROR: fleet/demo-workload-site-a not found"
    exit 1
fi

if [ ! -d "$FLEET_DIR/demo-workload-site-b" ]; then
    echo "ERROR: fleet/demo-workload-site-b not found"
    exit 1
fi

# Verify Fleet YAML files exist
REQUIRED_FLEET_FILES=(
    "$YAML_DIR/clustergroup-site-a.yaml"
    "$YAML_DIR/clustergroup-site-b.yaml"
    "$YAML_DIR/gitrepo-site-a.yaml"
    "$YAML_DIR/gitrepo-site-b.yaml"
)

for file in "${REQUIRED_FLEET_FILES[@]}"; do
    if [ ! -f "$file" ]; then
        echo "ERROR: Required Fleet file not found: $file"
        exit 1
    fi
done

echo "=== Generating and applying manifests ==="
echo ""

# Generate and apply manifests (MachineInventorySelectorTemplates + Clusters)
"$ZTP_SCRIPT" \
    --batch "$YAML_DIR/vms-config-2-sites.csv" \
    --output-dir "$PROJECT_ROOT/generated/manifests-2-sites"

echo ""
echo "=== Creating Fleet Resources ==="
echo ""

echo "Applying clustergroup-site-a..."
kubectl apply -f "$YAML_DIR/clustergroup-site-a.yaml"
echo "OK: clustergroup-site-a created"

echo ""
echo "Applying clustergroup-site-b..."
kubectl apply -f "$YAML_DIR/clustergroup-site-b.yaml"
echo "OK: clustergroup-site-b created"

echo ""
echo "Applying gitrepo-site-a..."
kubectl apply -f "$YAML_DIR/gitrepo-site-a.yaml"
echo "OK: gitrepo-site-a created (references fleet/demo-workload-site-a)"

echo ""
echo "Applying gitrepo-site-b..."
kubectl apply -f "$YAML_DIR/gitrepo-site-b.yaml"
echo "OK: gitrepo-site-b created (references fleet/demo-workload-site-b)"

echo ""
echo "=== Verification ==="
echo ""

# Check MachineInventorySelectorTemplates
echo "MachineInventorySelectorTemplates:"
kubectl get machineinventoryselectortemplate -n fleet-default -l test-group=dual-site-multinode || echo "  None found yet (will be created when VMs register)"

echo ""
echo "Clusters:"
kubectl get cluster -n fleet-default -l test-group=dual-site-multinode || echo "  None found yet"

echo ""
echo "ClusterGroups:"
kubectl get clustergroup -n fleet-default | grep site- || echo "  None found"

echo ""
echo "GitRepos:"
kubectl get gitrepo -n fleet-default | grep site- || echo "  None found"

echo ""
echo "=========================================="
echo "OK: Rancher and Fleet resources created"
echo "=========================================="
echo ""
echo "What was created:"
echo "  - MachineInventorySelectorTemplates and Clusters (Rancher resources)"
echo "  - clustergroup-site-a: Selects clusters with site-id matching site-a-vm-01 to site-a-vm-05"
echo "  - clustergroup-site-b: Selects clusters with site-id matching site-b-vm-01 to site-b-vm-05"
echo "  - gitrepo-site-a: Deploys fleet/demo-workload-site-a to Site A clusters"
echo "  - gitrepo-site-b: Deploys fleet/demo-workload-site-b to Site B clusters"
echo ""
echo "Note: Rancher resources must exist BEFORE VMs boot."
echo "When VMs register, Rancher will match MachineInventories to these"
echo "SelectorTemplates and provision clusters."
echo ""
echo "Important: After VMs boot and clusters are provisioned, you must"
echo "label the Fleet clusters using 8-label-clusters.sh (see Step 8)."


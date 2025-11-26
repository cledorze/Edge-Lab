#!/bin/bash
# Create Fleet Resources (ClusterGroups and GitRepos)
# Step 5 of DEPLOYMENT-GUIDE.md
#
# This script creates Fleet ClusterGroups and GitRepos so Fleet knows which
# clusters belong to which site and can deploy the correct workloads.
#
# Usage: ./5-create-fleet-resources.sh

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
YAML_DIR="$SCRIPT_DIR/yaml"

echo "=========================================="
echo "Create Fleet Resources"
echo "Step 5 of DEPLOYMENT-GUIDE.md"
echo "=========================================="
echo ""

# Check prerequisites
if ! command -v kubectl &> /dev/null; then
    echo "ERROR: kubectl is not available"
    echo "   Configure KUBECONFIG: export KUBECONFIG=/etc/rancher/rke2/rke2.yaml"
    exit 1
fi

# Check cluster connection
if ! kubectl cluster-info &> /dev/null; then
    echo "ERROR: Cannot connect to Kubernetes cluster"
    echo "   Configure KUBECONFIG: export KUBECONFIG=/etc/rancher/rke2/rke2.yaml"
    exit 1
fi

# Verify YAML files exist
REQUIRED_FILES=(
    "$YAML_DIR/clustergroup-site-a.yaml"
    "$YAML_DIR/clustergroup-site-b.yaml"
    "$YAML_DIR/git-secret.yaml"
    "$YAML_DIR/gitrepo-site-a.yaml"
    "$YAML_DIR/gitrepo-site-b.yaml"
)

for file in "${REQUIRED_FILES[@]}"; do
    if [ ! -f "$file" ]; then
        echo "ERROR: Required file not found: $file"
        exit 1
    fi
done

echo "=== Applying ClusterGroups ==="
echo ""

echo "Applying clustergroup-site-a..."
kubectl apply -f "$YAML_DIR/clustergroup-site-a.yaml"
echo "OK: clustergroup-site-a created"

echo ""
echo "Applying clustergroup-site-b..."
kubectl apply -f "$YAML_DIR/clustergroup-site-b.yaml"
echo "OK: clustergroup-site-b created"

echo ""
echo "=== Creating Git Secret ==="
echo ""

echo "Creating git secret for Gitea authentication..."
kubectl apply -f "$YAML_DIR/git-secret.yaml"
echo "OK: git secret created"

echo ""
echo "=== Applying GitRepos ==="
echo ""

echo "Applying gitrepo-site-a..."
kubectl apply -f "$YAML_DIR/gitrepo-site-a.yaml"
echo "OK: gitrepo-site-a created"

echo ""
echo "Applying gitrepo-site-b..."
kubectl apply -f "$YAML_DIR/gitrepo-site-b.yaml"
echo "OK: gitrepo-site-b created"

echo ""
echo "=== Verification ==="
echo ""

echo "ClusterGroups:"
kubectl get clustergroup -n fleet-default | grep site- || echo "  None found"

echo ""
echo "GitRepos:"
kubectl get gitrepo -n fleet-default | grep site- || echo "  None found"

echo ""
echo "=========================================="
echo "OK: Fleet resources created"
echo "=========================================="
echo ""
echo "What was created:"
echo "  - clustergroup-site-a: Selects clusters with site-id matching site-a-vm-01 to site-a-vm-05"
echo "  - clustergroup-site-b: Selects clusters with site-id matching site-b-vm-01 to site-b-vm-05"
echo "  - gitrepo-site-a: Deploys demo-workload-site-a to Site A clusters"
echo "  - gitrepo-site-b: Deploys demo-workload-site-b to Site B clusters"
echo ""
echo "Important: After VMs boot and clusters are provisioned, you must"
echo "label the Fleet clusters using 8-label-clusters.sh (see Step 8)."


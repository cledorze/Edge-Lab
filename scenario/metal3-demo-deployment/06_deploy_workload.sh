#!/bin/bash
# Script to deploy the RKE2 workload cluster on the virtual bare metal hosts

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export KUBECONFIG="${SCRIPT_DIR}/metal3-mgmt.kubeconfig"

# Get working_dir from extra_vars.yml or environment
WORKING_DIR=$(grep "working_dir:" "${SCRIPT_DIR}/extra_vars.yml" | cut -d'"' -f2 | sed "s|{{ lookup('env', 'HOME') }}|$HOME|")
MANIFESTS_DIR="${WORKING_DIR}/example-manifests"

# Colors
GREEN='\033[0;32m'
NC='\033[0m'

log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }

echo "=========================================="
echo "Step 6: Deploying Workload Cluster (RKE2)"
echo "=========================================="
echo ""

if [ ! -d "$MANIFESTS_DIR" ]; then
    echo "ERROR: Manifests directory not found: $MANIFESTS_DIR"
    exit 1
fi

# 1. Deploy control plane
log_info "Deploying RKE2 Control Plane..."
kubectl apply -f "${MANIFESTS_DIR}/rke2-control-plane.yaml"

# 2. Deploy agent
log_info "Deploying RKE2 Agent (Worker)..."
kubectl apply -f "${MANIFESTS_DIR}/rke2-agent.yaml"

echo ""
log_info "Workload cluster deployment initiated."
echo "Monitor progress with:"
echo "  clusterctl describe cluster sample-cluster"
echo "  kubectl get bmh"
echo ""
echo "=========================================="
log_info "DONE: Workload cluster manifests applied"
echo "=========================================="

#!/bin/bash
# Script to apply the BareMetalHost manifests to the management cluster

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export KUBECONFIG="${SCRIPT_DIR}/metal3-mgmt.kubeconfig"

# Get working_dir from extra_vars.yml or environment
WORKING_DIR=$(grep "working_dir:" "${SCRIPT_DIR}/extra_vars.yml" | cut -d'"' -f2 | sed "s|{{ lookup('env', 'HOME') }}|$HOME|")
BMH_DIR="${WORKING_DIR}/baremetalhosts"

# Colors
GREEN='\033[0;32m'
NC='\033[0m'

log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }

echo "=========================================="
echo "Step 5: Applying BareMetalHost Manifests"
echo "=========================================="
echo ""

if [ ! -d "$BMH_DIR" ]; then
    echo "ERROR: BareMetalHost directory not found: $BMH_DIR"
    echo "Did you run 04_launch_mgmt_cluster.sh?"
    exit 1
fi

log_info "Applying manifests from $BMH_DIR..."
kubectl apply -f "$BMH_DIR"

echo ""
log_info "BareMetalHosts registered. Monitoring status..."
echo "Waiting for hosts to become 'available' (this will take several minutes)..."
echo ""
watch -n 5 "kubectl get bmh"

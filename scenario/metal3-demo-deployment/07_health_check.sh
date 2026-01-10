#!/bin/bash
# Script to check and fix common issues with the Metal3 demo deployment

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export KUBECONFIG="${SCRIPT_DIR}/metal3-mgmt.kubeconfig"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log_ok() { echo -e "${GREEN}[OK]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_err() { echo -e "${RED}[ERROR]${NC} $1"; }

echo "=========================================="
echo "Metal3 Demo - Health Check"
echo "=========================================="
echo ""

# 1. Check sushy-tools
echo "--- Checking sushy-tools (Virtual BMC) ---"
if sudo podman ps | grep -q sushy-tools; then
    if curl -sk https://192.168.125.1:8000/redfish/v1/ > /dev/null 2>&1; then
        log_ok "sushy-tools is running and responding"
    else
        log_warn "sushy-tools container running but not responding - restarting..."
        sudo podman restart sushy-tools
        sleep 3
        if curl -sk https://192.168.125.1:8000/redfish/v1/ > /dev/null 2>&1; then
            log_ok "sushy-tools restarted successfully"
        else
            log_err "sushy-tools still not responding after restart"
        fi
    fi
else
    log_err "sushy-tools container not running!"
    echo "  Run: sudo podman start sushy-tools"
fi
echo ""

# 2. Check image-cache
echo "--- Checking image-cache (OS Images Server) ---"
if sudo podman ps | grep -q image-cache; then
    if curl -sk https://192.168.125.1:8443/ > /dev/null 2>&1; then
        log_ok "image-cache is running and responding"
    else
        log_warn "image-cache container running but not responding"
    fi
else
    log_warn "image-cache container not running"
    echo "  Starting image-cache..."

    WORKING_DIR=$(grep "working_dir:" "${SCRIPT_DIR}/extra_vars.yml" | cut -d'"' -f2 | sed "s|{{ lookup('env', 'HOME') }}|\$HOME|")
    WORKING_DIR=$(eval echo "$WORKING_DIR")

    if [ -d "$WORKING_DIR/image-cache" ] && [ -d "$WORKING_DIR/image-cache-conf" ]; then
        sudo podman run -d --name image-cache \
          -v "$WORKING_DIR/image-cache:/usr/local/apache2/htdocs:Z" \
          -v "$WORKING_DIR/image-cache-conf/httpd.conf:/usr/local/apache2/conf/httpd.conf:Z" \
          -v "$WORKING_DIR/image-cache-conf/server.key:/usr/local/apache2/conf/server.key:Z" \
          -v "$WORKING_DIR/image-cache-conf/server.crt:/usr/local/apache2/conf/server.crt:Z" \
          -p 8080:80 -p 8443:443 \
          docker.io/library/httpd:2.4 2>/dev/null && log_ok "image-cache started" || log_err "Failed to start image-cache"
    else
        log_err "Image cache directories not found at $WORKING_DIR"
    fi
fi
echo ""

# 3. Check management cluster
echo "--- Checking Management Cluster ---"
if [ -f "$KUBECONFIG" ]; then
    if kubectl get nodes > /dev/null 2>&1; then
        log_ok "Management cluster is accessible"
        kubectl get nodes
    else
        log_err "Cannot connect to management cluster"
    fi
else
    log_err "Kubeconfig not found: $KUBECONFIG"
fi
echo ""

# 4. Check Metal3 pods
echo "--- Checking Metal3 Pods ---"
if kubectl get pods -n metal3-system > /dev/null 2>&1; then
    IRONIC_READY=$(kubectl get deployment -n metal3-system metal3-metal3-ironic -o jsonpath='{.status.readyReplicas}' 2>/dev/null || echo "0")
    BMO_READY=$(kubectl get deployment -n metal3-system baremetal-operator-controller-manager -o jsonpath='{.status.readyReplicas}' 2>/dev/null || echo "0")

    if [ "$IRONIC_READY" == "1" ]; then
        log_ok "Ironic is ready"
    else
        log_err "Ironic is not ready"
    fi

    if [ "$BMO_READY" == "1" ]; then
        log_ok "BMO Controller is ready"
    else
        log_err "BMO Controller is not ready"
    fi
fi
echo ""

# 5. Check BMH status
echo "--- Checking BareMetalHosts ---"
kubectl get bmh -A 2>/dev/null || log_err "Cannot get BMH status"
echo ""

# 6. Check for errors
echo "--- Checking for Errors ---"
BMH_ERRORS=$(kubectl get bmh -A -o jsonpath='{range .items[*]}{.metadata.name}: {.status.errorMessage}{"\n"}{end}' 2>/dev/null | grep -v ": $" || true)
if [ -n "$BMH_ERRORS" ]; then
    log_warn "BMH errors detected:"
    echo "$BMH_ERRORS"
else
    log_ok "No BMH errors"
fi
echo ""

# 7. Check VMs
echo "--- Checking VMs ---"
sudo virsh list --all 2>/dev/null | grep -E "management|control|worker" || log_warn "No VMs found"
echo ""

# 8. Check workload cluster (if exists)
echo "--- Checking Workload Cluster ---"
if kubectl get cluster sample-cluster > /dev/null 2>&1; then
    CLUSTER_READY=$(kubectl get cluster sample-cluster -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null)
    if [ "$CLUSTER_READY" == "True" ]; then
        log_ok "Workload cluster 'sample-cluster' is ready"

        # Get workload cluster kubeconfig and check nodes
        WORKLOAD_KUBECONFIG="/tmp/sample-cluster.kubeconfig"
        clusterctl get kubeconfig sample-cluster > "$WORKLOAD_KUBECONFIG" 2>/dev/null
        echo "Workload cluster nodes:"
        KUBECONFIG="$WORKLOAD_KUBECONFIG" kubectl get nodes 2>/dev/null || log_warn "Cannot get workload cluster nodes"
    else
        log_warn "Workload cluster 'sample-cluster' is not ready"
        clusterctl describe cluster sample-cluster 2>/dev/null
    fi
else
    log_warn "No workload cluster found"
fi

echo ""
echo "=========================================="
echo "Health check complete"
echo "=========================================="

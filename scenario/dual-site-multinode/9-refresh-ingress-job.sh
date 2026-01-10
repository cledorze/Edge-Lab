#!/bin/bash
# Script to force refresh of update-ingress-hostname job
# This deletes the failed job and forces Fleet to redeploy it

set -e

KUBECONFIG_PATH="/home/tofix/LAB/AI/Edge-3.4/rancher-kubeconfig.yaml"
export KUBECONFIG="$KUBECONFIG_PATH"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "=========================================="
echo "Force Refresh update-ingress-hostname Job"
echo "=========================================="
echo ""

# Check prerequisites
if ! command -v kubectl &> /dev/null; then
    echo "ERROR: kubectl is not available"
    echo "   Configure KUBECONFIG: export KUBECONFIG=/home/tofix/LAB/AI/Edge-3.4/rancher-kubeconfig.yaml"
    exit 1
fi

# Check cluster connection
if ! kubectl cluster-info &> /dev/null; then
    echo "ERROR: Cannot connect to Kubernetes cluster"
    echo "   Configure KUBECONFIG: export KUBECONFIG=/home/tofix/LAB/AI/Edge-3.4/rancher-kubeconfig.yaml"
    exit 1
fi

echo "=== Method 1: Delete Job and let Fleet recreate it ==="
echo ""

# Delete jobs in all clusters (they will be recreated by Fleet)
NAMESPACES=("demo-workload-site-a" "demo-workload-site-b")

for namespace in "${NAMESPACES[@]}"; do
    echo "Checking namespace: $namespace"
    
    if kubectl get job update-ingress-hostname -n "$namespace" &>/dev/null; then
        echo "  Found job in $namespace, deleting..."
        kubectl delete job update-ingress-hostname -n "$namespace" --wait=false 2>/dev/null || true
        echo "  OK: Job deleted in $namespace"
    else
        echo "  No job found in $namespace"
    fi
done

echo ""
echo "=== Method 2: Force GitRepo resync ==="
echo ""

# Force Fleet to resync GitRepos by adding/updating an annotation
echo "Forcing GitRepo resync..."
kubectl annotate gitrepo demo-workload-site-a -n fleet-default \
    fleet.cattle.io/force-update="$(date +%s)" \
    --overwrite 2>/dev/null && echo "  OK: GitRepo site-a resync triggered" || echo "  WARNING: Could not trigger resync for site-a"

kubectl annotate gitrepo demo-workload-site-b -n fleet-default \
    fleet.cattle.io/force-update="$(date +%s)" \
    --overwrite 2>/dev/null && echo "  OK: GitRepo site-b resync triggered" || echo "  WARNING: Could not trigger resync for site-b"

echo ""
echo "=========================================="
echo "OK: Refresh triggered"
echo "=========================================="
echo ""
echo "The jobs will be recreated by Fleet automatically."
echo "Monitor with:"
echo "  kubectl get job -n demo-workload-site-a update-ingress-hostname -w"
echo "  kubectl get job -n demo-workload-site-b update-ingress-hostname -w"
echo ""
echo "Or check logs:"
echo "  kubectl logs -n demo-workload-site-a -l app=update-ingress-hostname --tail=50"


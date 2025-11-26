#!/bin/bash
# Script to label clusters with site-id and test-group labels
# This ensures ClusterGroups can select the correct clusters
# Dynamically retrieves clusters from the cluster instead of using hardcoded lists

set -e

KUBECONFIG_PATH="/etc/rancher/rke2/rke2.yaml"
export KUBECONFIG="$KUBECONFIG_PATH"

if [ ! -f "$KUBECONFIG_PATH" ]; then
    echo "Error: Kubeconfig not found at $KUBECONFIG_PATH"
    exit 1
fi

echo "=========================================="
echo "Labeling Clusters for Fleet ClusterGroups"
echo "=========================================="
echo ""

# Step 1: Get all Fleet clusters dynamically
echo "Step 1: Retrieving Fleet clusters (fleet.cattle.io) from cluster..."
FLEET_CLUSTERS=$(kubectl get clusters.fleet.cattle.io -n fleet-default -o jsonpath='{.items[*].metadata.name}' 2>/dev/null || echo "")

if [ -z "$FLEET_CLUSTERS" ]; then
    echo "  WARNING: No Fleet clusters found"
else
    # Count clusters by converting to array
    read -ra CLUSTER_ARRAY <<< "$FLEET_CLUSTERS"
    cluster_count=${#CLUSTER_ARRAY[@]}
    echo "Found $cluster_count Fleet cluster(s):"
    for cluster in $FLEET_CLUSTERS; do
        echo "  - $cluster"
    done
    echo ""
    
    echo "Labeling Fleet clusters..."
    for cluster in $FLEET_CLUSTERS; do
        # site-id is the cluster name itself
        kubectl label clusters.fleet.cattle.io "$cluster" -n fleet-default \
            "site-id=$cluster" \
            "test-group=2-sites-5-vms" \
            --overwrite 2>/dev/null || {
            echo "  WARNING: Failed to label Fleet cluster $cluster"
            continue
        }
        echo "  OK: Fleet cluster $cluster labeled with site-id=$cluster, test-group=2-sites-5-vms"
    done
fi

echo ""
# Step 2: Get all provisioning clusters dynamically
echo "Step 2: Retrieving provisioning clusters (provisioning.cattle.io) from cluster..."
PROVISIONING_CLUSTERS=$(kubectl get cluster.provisioning.cattle.io -n fleet-default -o jsonpath='{.items[*].metadata.name}' 2>/dev/null || echo "")

if [ -z "$PROVISIONING_CLUSTERS" ]; then
    echo "  WARNING: No provisioning clusters found (may not exist yet)"
else
    # Count clusters
    read -ra PROV_CLUSTER_ARRAY <<< "$PROVISIONING_CLUSTERS"
    prov_cluster_count=${#PROV_CLUSTER_ARRAY[@]}
    echo "Found $prov_cluster_count provisioning cluster(s):"
    for cluster in $PROVISIONING_CLUSTERS; do
        echo "  - $cluster"
    done
    echo ""
    
    echo "Labeling provisioning clusters..."
    for cluster in $PROVISIONING_CLUSTERS; do
        kubectl label cluster.provisioning.cattle.io "$cluster" -n fleet-default \
            "site-id=$cluster" \
            "test-group=2-sites-5-vms" \
            --overwrite 2>/dev/null || {
            echo "  WARNING: Failed to label provisioning cluster $cluster"
            continue
        }
        echo "  OK: Provisioning cluster $cluster labeled with site-id=$cluster, test-group=2-sites-5-vms"
    done
fi

echo ""
# Step 3: Also check for CAPI clusters (cluster.x-k8s.io)
echo "Step 3: Retrieving CAPI clusters (cluster.x-k8s.io) from cluster..."
CAPI_CLUSTERS=$(kubectl get cluster.cluster.x-k8s.io -n fleet-default -o jsonpath='{.items[*].metadata.name}' 2>/dev/null || echo "")

if [ -z "$CAPI_CLUSTERS" ]; then
    echo "  WARNING: No CAPI clusters found (may not exist yet)"
else
    # Count clusters
    read -ra CAPI_CLUSTER_ARRAY <<< "$CAPI_CLUSTERS"
    capi_cluster_count=${#CAPI_CLUSTER_ARRAY[@]}
    echo "Found $capi_cluster_count CAPI cluster(s):"
    for cluster in $CAPI_CLUSTERS; do
        echo "  - $cluster"
    done
    echo ""
    
    echo "Labeling CAPI clusters..."
    for cluster in $CAPI_CLUSTERS; do
        kubectl label cluster.cluster.x-k8s.io "$cluster" -n fleet-default \
            "site-id=$cluster" \
            "test-group=2-sites-5-vms" \
            --overwrite 2>/dev/null || {
            echo "  WARNING: Failed to label CAPI cluster $cluster"
            continue
        }
        echo "  OK: CAPI cluster $cluster labeled with site-id=$cluster, test-group=2-sites-5-vms"
    done
fi

echo ""
echo "=========================================="
echo "OK: Cluster labeling complete"
echo "=========================================="
echo ""
echo "Verifying Fleet cluster labels..."
kubectl get clusters.fleet.cattle.io -n fleet-default -o custom-columns=NAME:.metadata.name,SITE-ID:.metadata.labels.site-id,TEST-GROUP:.metadata.labels.test-group | grep -E "NAME|site-"

echo ""
echo "Checking ClusterGroup status..."
echo "Site A ClusterGroup:"
kubectl get clustergroup demo-workload-site-a -n fleet-default -o jsonpath='{.status.clusterCount}' 2>/dev/null && echo " clusters" || echo "0 clusters (may not exist)"
echo "Site B ClusterGroup:"
kubectl get clustergroup demo-workload-site-b -n fleet-default -o jsonpath='{.status.clusterCount}' 2>/dev/null && echo " clusters" || echo "0 clusters (may not exist)"
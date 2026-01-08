#!/bin/bash
# Script to label clusters with site-id and test-group labels
# This ensures ClusterGroups can select the correct clusters
# Dynamically retrieves clusters from the cluster instead of using hardcoded lists

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
        # Try to get labels from corresponding provisioning cluster first
        PROV_LABELS=$(kubectl get cluster.provisioning.cattle.io "$cluster" -n fleet-default -o jsonpath='{.metadata.labels}' 2>/dev/null || echo "")
        
        if [ -n "$PROV_LABELS" ] && [ "$PROV_LABELS" != "null" ] && [ "$PROV_LABELS" != "{}" ]; then
            # Extract site-id and test-group from provisioning cluster labels
            SITE_ID=$(kubectl get cluster.provisioning.cattle.io "$cluster" -n fleet-default -o jsonpath='{.metadata.labels.site-id}' 2>/dev/null || echo "")
            TEST_GROUP=$(kubectl get cluster.provisioning.cattle.io "$cluster" -n fleet-default -o jsonpath='{.metadata.labels.test-group}' 2>/dev/null || echo "")
            
            if [ -n "$SITE_ID" ] && [ -n "$TEST_GROUP" ]; then
                echo "  Found labels from provisioning cluster: site-id=$SITE_ID, test-group=$TEST_GROUP"
                kubectl label clusters.fleet.cattle.io "$cluster" -n fleet-default \
                    "site-id=$SITE_ID" \
                    "test-group=$TEST_GROUP" \
                    --overwrite 2>/dev/null || {
                    echo "  WARNING: Failed to label Fleet cluster $cluster"
                    continue
                }
                echo "  OK: Fleet cluster $cluster labeled with site-id=$SITE_ID, test-group=$TEST_GROUP (copied from provisioning cluster)"
                continue
            fi
        fi
        
        # Fallback: Determine site-id from cluster name (site-a-vm-01 → site-a, site-b-vm-01 → site-b)
        if [[ "$cluster" =~ ^site-a- ]]; then
            site_id="site-a"
        elif [[ "$cluster" =~ ^site-b- ]]; then
            site_id="site-b"
        else
            echo "  WARNING: Cannot determine site-id for cluster $cluster, skipping"
            continue
        fi
        
        kubectl label clusters.fleet.cattle.io "$cluster" -n fleet-default \
            "site-id=$site_id" \
            "test-group=dual-site-multinode" \
            --overwrite 2>/dev/null || {
            echo "  WARNING: Failed to label Fleet cluster $cluster"
            continue
        }
        echo "  OK: Fleet cluster $cluster labeled with site-id=$site_id, test-group=dual-site-multinode (fallback method)"
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
        # Determine site-id from cluster name (site-a-vm-01 → site-a, site-b-vm-01 → site-b)
        if [[ "$cluster" =~ ^site-a- ]]; then
            site_id="site-a"
        elif [[ "$cluster" =~ ^site-b- ]]; then
            site_id="site-b"
        else
            echo "  WARNING: Cannot determine site-id for cluster $cluster, skipping"
            continue
        fi
        
        kubectl label cluster.provisioning.cattle.io "$cluster" -n fleet-default \
            "site-id=$site_id" \
            "test-group=dual-site-multinode" \
            --overwrite 2>/dev/null || {
            echo "  WARNING: Failed to label provisioning cluster $cluster"
            continue
        }
        echo "  OK: Provisioning cluster $cluster labeled with site-id=$site_id, test-group=dual-site-multinode"
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
        # Determine site-id from cluster name (site-a-vm-01 → site-a, site-b-vm-01 → site-b)
        if [[ "$cluster" =~ ^site-a- ]]; then
            site_id="site-a"
        elif [[ "$cluster" =~ ^site-b- ]]; then
            site_id="site-b"
        else
            echo "  WARNING: Cannot determine site-id for cluster $cluster, skipping"
            continue
        fi
        
        kubectl label cluster.cluster.x-k8s.io "$cluster" -n fleet-default \
            "site-id=$site_id" \
            "test-group=dual-site-multinode" \
            --overwrite 2>/dev/null || {
            echo "  WARNING: Failed to label CAPI cluster $cluster"
            continue
        }
        echo "  OK: CAPI cluster $cluster labeled with site-id=$site_id, test-group=dual-site-multinode"
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
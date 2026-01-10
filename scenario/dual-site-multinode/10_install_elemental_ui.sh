#!/bin/bash
# Script to install Elemental UI Plugin in Rancher
# This allows managing Elemental resources from the Rancher Dashboard

set -e

KUBECONFIG_PATH="/home/tofix/LAB/AI/Edge-3.4/rancher-kubeconfig.yaml"
export KUBECONFIG="$KUBECONFIG_PATH"

echo "=========================================="
echo "Installing Elemental UI Plugin"
echo "=========================================="
echo ""

# Check cluster connection
if ! kubectl cluster-info &> /dev/null; then
    echo "ERROR: Cannot connect to Kubernetes cluster"
    echo "   Ensure KUBECONFIG is correct: $KUBECONFIG"
    exit 1
fi

echo "Adding Elemental UI repository..."
# The UI plugin is usually part of the standard Rancher charts, 
# but we ensure the namespace and basic extension resource exists.

# For Rancher 2.7+, UI plugins are handled via the extensions API.
# Elemental UI is often automatically discovered if the operator is installed,
# but we can force the registration of the plugin if needed.

echo "Applying Elemental UI Extension resource..."
cat <<EXT | kubectl apply -f -
apiVersion: catalog.cattle.io/v1
kind: ClusterRepo
metadata:
  name: elemental-ui
spec:
  url: https://github.com/rancher/elemental-ui.git
  gitBranch: main
EXT

echo ""
echo "Note: The Elemental UI should now appear in the Rancher Dashboard"
echo "      under 'Extensions' or automatically in the side menu if"
echo "      the Elemental Operator is already running."
echo ""
echo "Verifying Elemental Operator status..."
kubectl get pods -n cattle-elemental-system
echo ""
echo "=========================================="
echo "DONE: Elemental UI Repo added"
echo "=========================================="

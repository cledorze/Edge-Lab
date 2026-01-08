#!/bin/bash
# Script to stop Site B workload by scaling replicas to 0 via GitOps

set -e

KUBECONFIG_PATH="/home/tofix/LAB/AI/Edge-3.4/rancher-kubeconfig.yaml"
export KUBECONFIG="$KUBECONFIG_PATH"

REPO_ROOT="/home/tofix/LAB/AI/Edge-3.4"
DEPLOYMENT_FILE="${REPO_ROOT}/fleet/demo-workload-site-b/deployment.yaml"

echo "=========================================="
echo "Stopping Site B Workload (GitOps)"
echo "=========================================="

if [ ! -f "$DEPLOYMENT_FILE" ]; then
    echo "ERROR: Deployment file not found: $DEPLOYMENT_FILE"
    exit 1
fi

echo "Scaling replicas to 0 in $DEPLOYMENT_FILE..."
sed -i 's/replicas: [0-9]*/replicas: 0/' "$DEPLOYMENT_FILE"

echo "Committing and pushing changes to Gitea..."
cd "$REPO_ROOT"
# Set git config just in case
git config user.email "dallas@cledorze.lan"
git config user.name "dallas"

git add "$DEPLOYMENT_FILE"
git commit -m "Stop Site B workload (scale to 0)"
git push origin main

echo "Forcing Fleet reconciliation for demo-workload-site-b..."
kubectl annotate gitrepo -n fleet-default demo-workload-site-b fleet.cattle.io/force-update=$(date +%s) --overwrite

echo ""
echo "=========================================="
echo "DONE: Site B workload stopped"
echo "=========================================="

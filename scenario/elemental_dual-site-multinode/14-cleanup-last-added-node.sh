#!/bin/bash
# Cleanup the last node added by 12-add-node.sh
# - Decreases the machine pool quantity (worker/control-plane)
# - Deletes the VM and disk
# - Removes generated ISO/config artifacts
#
# Usage: ./14-cleanup-last-added-node.sh

set -euo pipefail

KUBECONFIG_PATH="/home/tofix/LAB/AI/Edge-3.4/rancher-kubeconfig.yaml"
export KUBECONFIG="$KUBECONFIG_PATH"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCENARIO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
ELEMENTAL_DIR="$SCENARIO_ROOT/generated/elemental"
OUTPUT_DIR="$SCENARIO_ROOT/output"

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1" >&2; }

if ! command -v jq &>/dev/null; then
    log_error "jq is required (sudo zypper in -y jq)"
    exit 1
fi

latest_config=$(ls -t "${ELEMENTAL_DIR}"/elemental_config-site-*-*-*.yaml 2>/dev/null | head -1 || true)
if [ -z "$latest_config" ]; then
    log_error "No generated elemental_config-site-*-*-*.yaml found in ${ELEMENTAL_DIR}"
    exit 1
fi

base=$(basename "$latest_config")
# Format: elemental_config-site-a-worker-YYYYMMDDHHMMSS.yaml
IFS='-' read -r _ _ site_id role scale_id_ext <<< "$base"
scale_id="${scale_id_ext%.yaml}"

if [ -z "$site_id" ] || [ -z "$role" ] || [ -z "$scale_id" ]; then
    log_error "Unable to parse site/role/scale-id from $base"
    exit 1
fi

site="site-${site_id}"
cluster_name="${site}-cluster"
pool_name="workers"
if [ "$role" = "control-plane" ]; then
    pool_name="control-plane"
fi

log_info "Latest node artifacts:"
log_info "  Site: ${site}"
log_info "  Role: ${role}"
log_info "  Scale ID: ${scale_id}"

log_info "Decreasing machine pool quantity (${pool_name}) on ${cluster_name}..."
pool_index=$(kubectl -n fleet-default get clusters.provisioning.cattle.io "${cluster_name}" -o json | jq -r --arg name "$pool_name" '.spec.rkeConfig.machinePools | to_entries[] | select(.value.name==$name) | .key')
if [ -z "$pool_index" ] || [ "$pool_index" = "null" ]; then
    log_error "Machine pool ${pool_name} not found in ${cluster_name}"
    exit 1
fi
current_qty=$(kubectl -n fleet-default get clusters.provisioning.cattle.io "${cluster_name}" -o json | jq -r --arg name "$pool_name" '.spec.rkeConfig.machinePools[] | select(.name==$name) | .quantity')
if [ -z "$current_qty" ] || [ "$current_qty" -le 0 ]; then
    log_warn "Pool quantity already 0, skipping decrement"
else
    new_qty=$((current_qty - 1))
    kubectl -n fleet-default patch clusters.provisioning.cattle.io "${cluster_name}" --type='json' -p="[
      {\"op\":\"replace\",\"path\":\"/spec/rkeConfig/machinePools/${pool_index}/quantity\",\"value\":${new_qty}}
    ]"
    log_info "Pool quantity: ${current_qty} -> ${new_qty}"
fi

vm_name="${site}-${role}-${scale_id}"
log_info "Removing VM: ${vm_name}"
sudo virsh --connect qemu:///system destroy "${vm_name}" >/dev/null 2>&1 || true
sudo virsh --connect qemu:///system undefine "${vm_name}" --remove-all-storage >/dev/null 2>&1 || true
sudo rm -f "/var/lib/libvirt/images/${vm_name}.qcow2"

iso_path="${OUTPUT_DIR}/vm-rancher-fleet-scale-${site}-${role}-${scale_id}.iso"
if [ -f "$iso_path" ]; then
    rm -f "$iso_path"
    log_info "Removed ISO: $iso_path"
fi

rm -f "$latest_config"
log_info "Removed config: $latest_config"

# Best-effort cleanup for older runs (if they exist)
kubectl -n fleet-default delete machineinventoryselectortemplate "${cluster_name}-${role}-selector-${scale_id}" --ignore-not-found
kubectl -n fleet-default delete machineregistration "${site}-${role}-reg-${scale_id}" --ignore-not-found

log_info "Cleanup complete."

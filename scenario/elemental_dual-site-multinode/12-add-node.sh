#!/bin/bash
# Add a new node VM to Site A or Site B with role-based selector (worker/control-plane)
# This script:
#   1) Creates a role-specific MachineRegistration (adds labels)
#   2) Downloads Elemental config from the new registration endpoint
#   3) Builds a site-specific ISO for the new node
#   4) Creates a MachineInventorySelectorTemplate + machinePool in the cluster
#   5) Creates the VM with the new ISO
#
# Usage: ./12-add-node.sh

set -euo pipefail

KUBECONFIG_PATH="/home/tofix/LAB/AI/Edge-3.4/rancher-kubeconfig.yaml"
export KUBECONFIG="$KUBECONFIG_PATH"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCENARIO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
PROJECT_ROOT="$(cd "$SCENARIO_ROOT/.." && pwd)"
YAML_DIR="$SCRIPT_DIR/yaml"
ELEMENTAL_DIR="$SCENARIO_ROOT/generated/elemental"
OUTPUT_DIR="$SCENARIO_ROOT/output"

EIB_DIR=""
for candidate in "${SCENARIO_ROOT}/EIB" "${PROJECT_ROOT}/EIB"; do
    if [ -d "$candidate" ]; then
        EIB_DIR="$(readlink -f "$candidate")"
        break
    fi
done
EIB_BUILD_SCRIPT="${EIB_DIR}/build-eib-image.sh"

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

log_info() { echo -e "${GREEN}[INFO]${NC} $1" >&2; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1" >&2; }
log_error() { echo -e "${RED}[ERROR]${NC} $1" >&2; }

prompt_choice() {
    local prompt="$1"
    local default="$2"
    read -r -p "$prompt" choice
    echo "${choice:-$default}"
}

check_prerequisites() {
    if ! command -v kubectl &>/dev/null; then
        log_error "kubectl is not available"
        exit 1
    fi

    if ! command -v curl &>/dev/null; then
        log_error "curl is not available"
        exit 1
    fi

    if ! command -v virt-install &>/dev/null; then
        log_error "virt-install is not installed"
        exit 1
    fi

    if ! command -v swtpm &>/dev/null; then
        log_error "swtpm is not installed (required for TPM emulation)"
        log_info "Install with: sudo zypper in -y swtpm"
        exit 1
    fi

    if [ -z "$EIB_DIR" ] || [ ! -d "$EIB_DIR" ]; then
        log_error "EIB directory not found (expected ${SCENARIO_ROOT}/EIB or ${PROJECT_ROOT}/EIB)"
        exit 1
    fi

    if [ ! -f "$EIB_BUILD_SCRIPT" ]; then
        log_error "EIB build script not found at $EIB_BUILD_SCRIPT"
        exit 1
    fi

    if ! kubectl cluster-info &>/dev/null; then
        log_error "Cannot connect to Rancher management cluster"
        log_info "Ensure KUBECONFIG is set to Rancher management kubeconfig"
        exit 1
    fi
}

wait_for_registration_url() {
    local reg_name="$1"
    local max_wait=90
    local waited=0
    local url=""

    log_info "Waiting for registration URL ($reg_name)..."
    while [ $waited -lt $max_wait ]; do
        url=$(kubectl get machineregistration "$reg_name" -n fleet-default -o jsonpath='{.status.registrationURL}' 2>/dev/null || echo "")
        if [ -n "$url" ]; then
            echo "$url"
            return 0
        fi
        sleep 2
        waited=$((waited + 2))
    done

    log_error "Registration URL not available after ${max_wait}s for $reg_name"
    exit 1
}

download_config() {
    local url="$1"
    local target_file="$2"
    local attempts=5
    local attempt=1

    rm -f "$target_file"
    while [ $attempt -le $attempts ]; do
        if curl -s -f -k -H "Accept: application/yaml" -o "$target_file.tmp" "$url" 2>/dev/null; then
            local file_size
            file_size=$(stat -f%z "$target_file.tmp" 2>/dev/null || stat -c%s "$target_file.tmp" 2>/dev/null || echo "0")
            if [ "$file_size" -gt 50 ]; then
                mv "$target_file.tmp" "$target_file"
                return 0
            fi
        fi
        rm -f "$target_file.tmp"
        sleep 3
        attempt=$((attempt + 1))
    done

    log_error "Failed to download elemental config from $url"
    exit 1
}

add_install_and_reset() {
    local config_file="$1"
    if ! grep -q "install:" "$config_file"; then
        log_info "Adding install/reset sections to $config_file"
        local reg_line
        reg_line=$(grep -n "registration:" "$config_file" | head -1 | cut -d: -f1)
        if [ -n "$reg_line" ]; then
            tail -n +$reg_line "$config_file" > "${config_file}.reg.tmp"
        else
            cat "$config_file" > "${config_file}.reg.tmp"
        fi

        cat > "${config_file}.tmp" << 'EOF'
elemental:
    install:
        device: ""  # Auto-detected: first disk matching selector
        device-selector:
            - key: Name
              operator: In
              values:
                  - /dev/sda
                  - /dev/vda
                  - /dev/nvme0
            - key: Size
              operator: Gt
              values:
                  - 20Gi
        reboot: true
        snapshotter:
            type: btrfs
EOF
        cat "${config_file}.reg.tmp" >> "${config_file}.tmp"
        rm -f "${config_file}.reg.tmp"

        if ! grep -q "reset:" "${config_file}.tmp"; then
            cat >> "${config_file}.tmp" << 'EOF'
    reset:
        reboot: true
        reset-oem: true
        reset-persistent: true
EOF
        fi
        mv "${config_file}.tmp" "$config_file"
    fi
}

build_iso() {
    local config_file="$1"
    local iso_out="$2"
    local eib_elemental_dir="${EIB_DIR}/elemental"
    local temp_dir
    temp_dir=$(mktemp -d)
    local backup_dir="${temp_dir}/eib_elemental_backup"
    local min_gb=5

    cleanup_container_storage() {
        local avail_kb
        avail_kb=$(df -Pk /var/tmp | awk 'NR==2 {print $4}')
        if [ -n "$avail_kb" ] && [ $((avail_kb / 1024 / 1024)) -lt "$min_gb" ]; then
            log_warn "Low space on /var/tmp, cleaning container image temp storage..."
            rm -rf /var/tmp/container_images_storage* 2>/dev/null || true
        fi
    }

    mkdir -p "$OUTPUT_DIR"
    mkdir -p "$eib_elemental_dir"
    mkdir -p "$backup_dir"

    # Backup existing EIB elemental files
    find "$eib_elemental_dir" -maxdepth 1 -type f ! -name ".gitkeep" -exec mv {} "$backup_dir/" \; 2>/dev/null || true

    cp "$config_file" "${eib_elemental_dir}/elemental_config.yaml"

    cleanup_container_storage
    (cd "$EIB_DIR" && "$EIB_BUILD_SCRIPT")

    local iso_built=""
    if [ -f "${EIB_DIR}/output/vm-rancher-fleet-scale.iso" ]; then
        iso_built="${EIB_DIR}/output/vm-rancher-fleet-scale.iso"
    elif [ -f "${EIB_DIR}/vm-rancher-fleet-scale.iso" ]; then
        iso_built="${EIB_DIR}/vm-rancher-fleet-scale.iso"
    elif [ -f "${OUTPUT_DIR}/vm-rancher-fleet-scale.iso" ]; then
        iso_built="${OUTPUT_DIR}/vm-rancher-fleet-scale.iso"
    fi

    if [ -z "$iso_built" ]; then
        log_error "ISO build failed (vm-rancher-fleet-scale.iso not found)"
        exit 1
    fi

    mv "$iso_built" "$iso_out"
    log_info "ISO created: $iso_out"

    # Restore EIB elemental directory
    if [ -n "$(ls -A "$backup_dir" 2>/dev/null)" ]; then
        mv "$backup_dir"/* "$eib_elemental_dir/" 2>/dev/null || true
    fi
    rm -rf "$temp_dir"
}

create_vm() {
    local vm_name="$1"
    local iso_path="$2"
    local disk_path="/var/lib/libvirt/images/${vm_name}.qcow2"
    local disk_size="25G"
    local memory="8192"
    local vcpus="2"
    local bridge="br0"

    if virsh --connect qemu:///system dominfo "$vm_name" &>/dev/null; then
        log_warn "VM $vm_name already exists, skipping"
        return 0
    fi

    if ! virsh --connect qemu:///system pool-info "libvirt-vms" &>/dev/null; then
        log_error "Libvirt pool 'libvirt-vms' not found"
        exit 1
    fi

    if [ ! -f "$disk_path" ]; then
        if ! qemu-img create -f qcow2 "$disk_path" "$disk_size" >/dev/null 2>&1; then
            log_warn "qemu-img failed without sudo, retrying with sudo..."
            sudo qemu-img create -f qcow2 "$disk_path" "$disk_size" >/dev/null
        fi
    fi

    local mac
    mac=$(printf '52:54:00:%02x:%02x:%02x' $((RANDOM%256)) $((RANDOM%256)) $((RANDOM%256)))
    log_info "Using MAC: $mac"

    local net_args=("--network" "bridge=${bridge},model=virtio,mac=${mac}")
    if ! ip link show "$bridge" &>/dev/null 2>&1; then
        net_args=("--network" "network=default,model=virtio,mac=${mac}")
    fi

    virt-install \
        --connect qemu:///system \
        --name "$vm_name" \
        --memory "$memory" \
        --vcpus "$vcpus" \
        --disk path="$disk_path",format=qcow2,bus=virtio \
        "${net_args[@]}" \
        --cdrom "$iso_path" \
        --boot cdrom,hd \
        --tpm backend.type=emulator,backend.version=2.0,model=tpm-crb \
        --graphics vnc,listen=0.0.0.0 \
        --console pty,target_type=serial \
        --noautoconsole \
        --osinfo detect=on,name=linux2024 \
        --wait -1
}

check_prerequisites

echo "=========================================="
echo "Add New Node (Multinode)"
echo "=========================================="
echo ""

site_choice=$(prompt_choice "Select site [A/B] (default: A): " "A")
role_choice=$(prompt_choice "Select role [worker/control-plane] (default: worker): " "worker")

site_choice=$(echo "$site_choice" | tr '[:upper:]' '[:lower:]')
role_choice=$(echo "$role_choice" | tr '[:upper:]' '[:lower:]')

if [ "$site_choice" != "a" ] && [ "$site_choice" != "b" ]; then
    log_error "Invalid site: $site_choice (use A or B)"
    exit 1
fi

if [ "$role_choice" != "worker" ] && [ "$role_choice" != "control-plane" ]; then
    log_error "Invalid role: $role_choice (use worker or control-plane)"
    exit 1
fi

site_id="site-${site_choice}"
cluster_name="site-${site_choice}-cluster"
base_reg_file="${YAML_DIR}/site-${site_choice}-registration.yaml"
scale_id=$(date +"%Y%m%d%H%M%S")

reg_name="${site_id}-${role_choice}-reg-${scale_id}"
selector_name="${cluster_name}-${role_choice}-selector-${scale_id}"
pool_name="scale-${role_choice}-${scale_id}"

log_info "Site: ${site_id} | Role: ${role_choice} | Scale ID: ${scale_id}"

if [ ! -f "$base_reg_file" ]; then
    log_error "Base registration file not found: $base_reg_file"
    exit 1
fi

tmp_reg=$(mktemp)
sed "s/name: site-${site_choice}-registration/name: ${reg_name}/" "$base_reg_file" | \
    awk -v role="$role_choice" -v scale="$scale_id" '
        /machineInventoryLabels:/ {
            print;
            print "    node-role: " role;
            print "    scale-id: \"" scale "\"";
            next
        }
        {print}
    ' > "$tmp_reg"

log_info "Creating MachineRegistration: $reg_name"
kubectl apply -f "$tmp_reg"
rm -f "$tmp_reg"

reg_url=$(wait_for_registration_url "$reg_name")
log_info "Registration URL: $reg_url"

mkdir -p "$ELEMENTAL_DIR"
config_out="${ELEMENTAL_DIR}/elemental_config-${site_id}-${role_choice}-${scale_id}.yaml"
download_config "$reg_url" "$config_out"
add_install_and_reset "$config_out"

iso_out="${OUTPUT_DIR}/vm-rancher-fleet-scale-${site_id}-${role_choice}-${scale_id}.iso"
build_iso "$config_out" "$iso_out"

log_info "Creating MachineInventorySelectorTemplate: $selector_name"
cat << EOF | kubectl apply -f -
apiVersion: elemental.cattle.io/v1beta1
kind: MachineInventorySelectorTemplate
metadata:
  name: ${selector_name}
  namespace: fleet-default
spec:
  template:
    spec:
      selector:
        matchLabels:
          site-id: ${site_id}
          node-role: ${role_choice}
          scale-id: "${scale_id}"
EOF

log_info "Patching provisioning cluster ${cluster_name} with new machinePool ${pool_name}"
kubectl patch clusters.provisioning.cattle.io "${cluster_name}" -n fleet-default --type='json' -p="[
  {
    \"op\": \"add\",
    \"path\": \"/spec/rkeConfig/machinePools/-\",
    \"value\": {
      \"name\": \"${pool_name}\",
      \"quantity\": 1,
      \"etcdRole\": $( [ "$role_choice" = "control-plane" ] && echo "true" || echo "false" ),
      \"controlPlaneRole\": $( [ "$role_choice" = "control-plane" ] && echo "true" || echo "false" ),
      \"workerRole\": $( [ "$role_choice" = "worker" ] && echo "true" || echo "false" ),
      \"machineConfigRef\": {
        \"kind\": \"MachineInventorySelectorTemplate\",
        \"name\": \"${selector_name}\",
        \"apiVersion\": \"elemental.cattle.io/v1beta1\"
      }
    }
  }
]"

vm_name="${site_id}-${role_choice}-${scale_id}"
log_info "Creating VM: $vm_name"
create_vm "$vm_name" "$iso_out"

log_info "OK: New node VM created"
log_info "Next steps:"
log_info "  - Wait for MachineInventory registration"
log_info "  - Verify node joins cluster: kubectl get nodes -n ${cluster_name}"

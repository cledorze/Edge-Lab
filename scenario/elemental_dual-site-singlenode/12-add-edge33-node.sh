#!/bin/bash
# Add a new SUSE Edge 3.3 standalone node (SL Micro 6.0) and onboard it to Rancher.
# This script creates a single-node k3s cluster using EIB 3.3.
# Adds SUC labels for OS/K8s upgrades testing.
#
# Usage:
#   export EIB_33_DIR=/path/to/EIB-3.3
#   ./12-add-edge33-node.sh
#   ./12-add-edge33-node.sh --wait-install

set -euo pipefail

KUBECONFIG_PATH="/home/tofix/LAB/AI/Edge-3.4/rancher-kubeconfig.yaml"
export KUBECONFIG="$KUBECONFIG_PATH"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCENARIO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
PROJECT_ROOT="$(cd "$SCENARIO_ROOT/.." && pwd)"
YAML_DIR="$SCRIPT_DIR/yaml"
ELEMENTAL_DIR="$SCENARIO_ROOT/generated/elemental"
OUTPUT_DIR="$SCENARIO_ROOT/output"
ZTP_SCRIPT="$SCENARIO_ROOT/ztp-scale-nodes/ztp-precreate.sh"

EIB_33_DIR="${EIB_33_DIR:-}"
EIB_BUILD_SCRIPT=""
if [ -n "$EIB_33_DIR" ] && [ -d "$EIB_33_DIR" ]; then
    EIB_BUILD_SCRIPT="${EIB_33_DIR}/build-eib-image.sh"
fi

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

log_info() { echo -e "${GREEN}[INFO]${NC} $1" >&2; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1" >&2; }
log_error() { echo -e "${RED}[ERROR]${NC} $1" >&2; }

STEP_NUM=0

step_pause() {
    local title="$1"
    local cmd="$2"
    STEP_NUM=$((STEP_NUM + 1))
    echo ""
    echo "Step ${STEP_NUM}: ${title}"
    echo "$(printf "=%.0s" $(seq 1 $((7 + ${#STEP_NUM} + 2 + ${#title}))))"
    echo "Command: ${cmd}"
    read -r -p "Press Enter to continue..." _
}

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

    if ! command -v jq &>/dev/null; then
        log_error "jq is not available"
        log_info "Install with: sudo zypper in -y jq"
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

    if [ -z "$EIB_33_DIR" ] || [ ! -d "$EIB_33_DIR" ]; then
        log_error "EIB_33_DIR not set or invalid."
        log_info "Set it to the Edge 3.3 EIB directory:"
        log_info "  export EIB_33_DIR=/path/to/EIB-3.3"
        exit 1
    fi

    if [ ! -f "$EIB_BUILD_SCRIPT" ]; then
        log_error "EIB build script not found at $EIB_BUILD_SCRIPT"
        exit 1
    fi

    if [ ! -f "$ZTP_SCRIPT" ]; then
        log_error "ZTP script not found at $ZTP_SCRIPT"
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
    local eib_elemental_dir="${EIB_33_DIR}/elemental"
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
    (cd "$EIB_33_DIR" && "$EIB_BUILD_SCRIPT")

    local iso_built=""
    if [ -f "${EIB_33_DIR}/output/vm-rancher-fleet-scale.iso" ]; then
        iso_built="${EIB_33_DIR}/output/vm-rancher-fleet-scale.iso"
    elif [ -f "${EIB_33_DIR}/vm-rancher-fleet-scale.iso" ]; then
        iso_built="${EIB_33_DIR}/vm-rancher-fleet-scale.iso"
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
    local wait_seconds="${3:-0}"
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
        --wait "$wait_seconds"
}

WAIT_SECONDS=0
if [ "${1:-}" = "--wait-install" ]; then
    WAIT_SECONDS=-1
fi

check_prerequisites

echo "=========================================="
echo "Add Edge 3.3 Standalone Node (SUC Ready)"
echo "=========================================="
echo ""

site_choice=$(prompt_choice "Select site [A/B] (default: A): " "A")
site_choice=$(echo "$site_choice" | tr '[:upper:]' '[:lower:]')

if [ "$site_choice" != "a" ] && [ "$site_choice" != "b" ]; then
    log_error "Invalid site: $site_choice (use A or B)"
    exit 1
fi

site_id="site-${site_choice}"
scale_id=$(date +"%Y%m%d%H%M%S")
cluster_name="${site_id}-edge33-${scale_id}"
reg_name="${cluster_name}-registration"

log_info "Site: ${site_id} | Cluster: ${cluster_name} | Scale ID: ${scale_id}"

# Create MachineRegistration with SUC labels
step_pause "Create MachineRegistration with SUC labels" "kubectl apply -f (generated registration)"

base_reg_file="${YAML_DIR}/site-${site_choice}-registration.yaml"
if [ ! -f "$base_reg_file" ]; then
    log_error "Base registration file not found: $base_reg_file"
    exit 1
fi

tmp_reg=$(mktemp)
cat > "$tmp_reg" << EOF
apiVersion: elemental.cattle.io/v1beta1
kind: MachineRegistration
metadata:
  name: ${reg_name}
  namespace: fleet-default
spec:
  machineInventoryLabels:
    site-id: ${site_id}
    test-group: 2-sites-5-vms
    hostname: \${Runtime/Hostname}
    edge-version: "3.3"
    suc-group: edge33
    cluster-name: ${cluster_name}
  config:
    cloud-config:
      users:
        - name: root
          passwd: linux
          ssh_authorized_keys:
            - ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIGDKrMEscmfI/N4oGtSjQ6r/MtjvFVDKI58/RMQJw3um cledorze@home
            - ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABgQC5cke7RYaET4MGBNVMfa0joBPyIslSNZAgrOz4zbRRJlnuuWYaoD7AcIpN+INZykllLjRXsDtggYjLEed5BvrNEo87CBZrgwjd3KQ9Qp1awKPyXeIG80VROO+KTI4JoS9uC5pRxENEo/yWjpGMaHSeZoSDGKfLjnJbxru4pJhKYFlDjEd/eFZ6Ho4ZSV1CMHRM9Tn5/3jPKd3do5qDYl/UhoG/M0Pw222iGu6/DAtGpfVPrLv1Kp3gOTTcw1qcYWept3CPgr9Q60rCyGmpCJ+E5+kqExG/EdgfRFjKeneNYdqqnFKKOAV6cwLcCvMYbQ5GVwmsnX6pAyvS8bWYOui/lbM/LbZ1hiMDjmOSFg5cFTWz1C1Zlg1m+UhCFkIK5aAm5i5TNwwus2OH8Lo5rwSydCNtsKlxk2FX1oKhqaCiCi+FK9d+1TMCw/Swr5TvFTXONeR2JveQfET6R0cOrl+2zdqEsLWdRfwStAL+h4L/OiDO+Q99t3QndKRjsFYBZAs= tofix@osxie.local
        - name: tofix
          passwd: linux
          ssh_authorized_keys:
            - ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABgQC5cke7RYaET4MGBNVMfa0joBPyIslSNZAgrOz4zbRRJlnuuWYaoD7AcIpN+INZykllLjRXsDtggYjLEed5BvrNEo87CBZrgwjd3KQ9Qp1awKPyXeIG80VROO+KTI4JoS9uC5pRxENEo/yWjpGMaHSeZoSDGKfLjnJbxru4pJhKYFlDjEd/eFZ6Ho4ZSV1CMHRM9Tn5/3jPKd3do5qDYl/UhoG/M0Pw222iGu6/DAtGpfVPrLv1Kp3gOTTcw1qcYWept3CPgr9Q60rCyGmpCJ+E5+kqExG/EdgfRFjKeneNYdqqnFKKOAV6cwLcCvMYbQ5GVwmsnX6pAyvS8bWYOui/lbM/LbZ1hiMDjmOSFg5cFTWz1C1Zlg1m+UhCFkIK5aAm5i5TNwwus2OH8Lo5rwSydCNtsKlxk2FX1oKhqaCiCi+FK9d+1TMCw/Swr5TvFTXONeR2JveQfET6R0cOrl+2zdqEsLWdRfwStAL+h4L/OiDO+Q99t3QndKRjsFYBZAs= tofix@osxie.local
        - name: cledorze
          passwd: linux
          ssh_authorized_keys:
            - ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIGDKrMEscmfI/N4oGtSjQ6r/MtjvFVDKI58/RMQJw3um cledorze@home
    elemental:
      install:
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
              - 25Gi
        reboot: true
        snapshotter:
          type: btrfs
      reset:
        reboot: true
        reset-oem: true
        reset-persistent: true
EOF

log_info "Creating MachineRegistration: $reg_name"
kubectl apply -f "$tmp_reg"
rm -f "$tmp_reg"

# Wait for registration URL
step_pause "Wait for registration URL" "kubectl get machineregistration $reg_name -n fleet-default -o jsonpath='{.status.registrationURL}'"
reg_url=$(wait_for_registration_url "$reg_name")
log_info "Registration URL: $reg_url"

# Download elemental config
mkdir -p "$ELEMENTAL_DIR"
config_out="${ELEMENTAL_DIR}/elemental_config-${cluster_name}.yaml"
step_pause "Download Elemental config" "curl -k -H \"Accept: application/yaml\" $reg_url -o $config_out"
download_config "$reg_url" "$config_out"
add_install_and_reset "$config_out"

# Build ISO with EIB 3.3
iso_out="${OUTPUT_DIR}/vm-rancher-edge33-${cluster_name}.iso"
step_pause "Build ISO with EIB 3.3" "$EIB_BUILD_SCRIPT"
build_iso "$config_out" "$iso_out"

# Create Rancher cluster resources using ztp-precreate.sh
step_pause "Create cluster resources" "$ZTP_SCRIPT --single-node ..."

tmp_csv=$(mktemp)
cat > "$tmp_csv" << EOF
site-name,namespace,distro,k8s-version,cp-nodes,worker-nodes,single-node,vip,labels
${cluster_name},fleet-default,k3s,v1.31.6+k3s1,1,0,true,,site-id=${site_id},test-group=2-sites-5-vms,edge-version=3.3,suc-group=edge33,hostname=${cluster_name}
EOF

log_info "Creating cluster resources for: $cluster_name"
"$ZTP_SCRIPT" \
    --batch "$tmp_csv" \
    --output-dir "$SCENARIO_ROOT/generated/manifests-edge33"

rm -f "$tmp_csv"

# Create VM
vm_name="${cluster_name}"
step_pause "Create VM" "virt-install --name $vm_name --cdrom $iso_out ..."
log_info "Creating VM: $vm_name"
create_vm "$vm_name" "$iso_out" "$WAIT_SECONDS"

echo ""
echo "=========================================="
log_info "OK: Edge 3.3 standalone node created"
echo "=========================================="
echo ""
log_info "Cluster name: $cluster_name"
log_info "SUC labels applied:"
log_info "  - edge-version=3.3"
log_info "  - suc-group=edge33"
echo ""
log_info "Next steps:"
log_info "  1. Wait for MachineInventory registration"
log_info "  2. Verify cluster: kubectl get clusters.provisioning.cattle.io -n fleet-default | grep ${cluster_name}"
log_info "  3. Apply SUC plans targeting label suc-group=edge33"
echo ""
log_info "To wait for install completion (blocking):"
log_info "  $0 --wait-install"

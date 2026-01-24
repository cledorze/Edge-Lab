#!/bin/bash
# Script to create 10 VMs for 2 sites (5 VMs each) with libvirt/KVM
# Site A: 5 VMs (site-a-vm-01 to site-a-vm-05) using vm-rancher-fleet-scale-site-a.iso
# Site B: 5 VMs (site-b-vm-01 to site-b-vm-05) using vm-rancher-fleet-scale-site-b.iso
# Each VM: 20GB disk, 8GB RAM, 1 vCPU
#
# Usage: ./create-vms-2-sites.sh [--parallel|--sequential|--help]
#   --parallel, -p    Create VMs in parallel (faster)
#   --sequential, -s  Create VMs sequentially (default, safer)
#   --help, -h        Show help message

set -e

KUBECONFIG_PATH="/home/tofix/LAB/AI/Edge-3.4/rancher-kubeconfig.yaml"
export KUBECONFIG="$KUBECONFIG_PATH"

KUBECONFIG_PATH="/home/tofix/LAB/AI/Edge-3.4/rancher-kubeconfig.yaml"
export KUBECONFIG="$KUBECONFIG_PATH"

# Parse command line arguments FIRST
PARALLEL_MODE=false
if [ "$1" = "--parallel" ] || [ "$1" = "-p" ]; then
    PARALLEL_MODE=true
elif [ "$1" = "--sequential" ] || [ "$1" = "-s" ]; then
    PARALLEL_MODE=false
elif [ "$1" = "--help" ] || [ "$1" = "-h" ]; then
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  --parallel, -p    Create VMs in parallel (faster, but may overload system)"
    echo "  --sequential, -s  Create VMs sequentially (default, safer)"
    echo "  --help, -h        Show this help message"
    echo ""
    echo "This script creates:"
    echo "  - Site A: 5 VMs (site-a-vm-01 to site-a-vm-05) with ISO site-a"
    echo "  - Site B: 5 VMs (site-b-vm-01 to site-b-vm-05) with ISO site-b"
    exit 0
elif [ -z "$1" ]; then
    echo "=========================================="
    echo "VM Creation Mode Selection (2 Sites)"
    echo "=========================================="
    echo ""
    echo "Choose execution mode:"
    echo "  1) Sequential (default, safer) - Creates VMs one at a time"
    echo "  2) Parallel (faster) - Creates all VMs simultaneously"
    echo ""
    read -p "Enter your choice [1-2] (default: 1): " choice
    choice=${choice:-1}
    
    case "$choice" in
        1) PARALLEL_MODE=false ;;
        2) PARALLEL_MODE=true ;;
        *) PARALLEL_MODE=false ;;
    esac
    echo ""
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ISO_SITE_A="${SCRIPT_DIR}/../output/vm-rancher-fleet-scale-site-a.iso"
ISO_SITE_B="${SCRIPT_DIR}/../output/vm-rancher-fleet-scale-site-b.iso"
DISK_SIZE="25G"
MEMORY="8192"  # 8GB in MB
VCPUS="2"
# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# Wait until all VMs are running.
wait_for_vms_running() {
    local vm_names=(
        site-a-vm-01 site-a-vm-02 site-a-vm-03 site-a-vm-04 site-a-vm-05
        site-b-vm-01 site-b-vm-02 site-b-vm-03 site-b-vm-04 site-b-vm-05
    )
    local total=${#vm_names[@]}
    local timeout_sec=900
    local start_ts
    start_ts=$(date +%s)

    log_info "Waiting for ${total} VMs to be running..."
    while true; do
        local running_count=0
        for vm in "${vm_names[@]}"; do
            if virsh --connect qemu:///system domstate "$vm" 2>/dev/null | grep -qi "running"; then
                running_count=$((running_count + 1))
            fi
        done

        echo "  Running: ${running_count}/${total}"
        if [ "$running_count" -eq "$total" ]; then
            log_info "All VMs are running."
            return 0
        fi

        local now_ts
        now_ts=$(date +%s)
        if [ $((now_ts - start_ts)) -ge "$timeout_sec" ]; then
            log_warn "Timeout waiting for VMs to be running after ${timeout_sec}s."
            return 1
        fi
        sleep 10
    done
}

# Use bridged networking
BRIDGE="br0"
if ! ip link show "$BRIDGE" &>/dev/null 2>&1; then
    log_warn "Bridge $BRIDGE not found, using network: default"
    NETWORK="default"
else
    NETWORK=""
    log_info "Using bridged network: $BRIDGE"
fi

# Check prerequisites
check_prerequisites() {
    log_info "Checking prerequisites..."
    
    if ! command -v virt-install &> /dev/null; then
        log_error "virt-install is not installed"
        exit 1
    fi

    if ! command -v swtpm &> /dev/null; then
        log_error "swtpm is not installed (required for TPM emulation)"
        log_info "Install with: sudo zypper in -y swtpm"
        exit 1
    fi
    
    if ! systemctl is-active --quiet libvirtd; then
        log_warn "libvirtd is not running, attempting to start..."
        sudo systemctl start libvirtd
    fi
    
    if [ ! -f "$ISO_SITE_A" ]; then
        log_error "ISO file not found: $ISO_SITE_A"
        log_info "Build ISOs using the automated script:"
        log_info "  cd scenario && ./3-build-isos-2-sites.sh"
        log_info "This script automatically handles copying the appropriate elemental config files."
        exit 1
    fi
    
    if [ ! -f "$ISO_SITE_B" ]; then
        log_error "ISO file not found: $ISO_SITE_B"
        log_info "Build ISOs using the automated script:"
        log_info "  cd scenario && ./3-build-isos-2-sites.sh"
        log_info "This script automatically handles copying the appropriate elemental config files."
        exit 1
    fi
    
    log_info "Prerequisites OK"
}

# Create VM for a specific site
create_vm() {
    local vm_name=$1
    local iso_path=$2
    local mac_file=$3
    local disk_path="/var/lib/libvirt/images/${vm_name}.qcow2"
    local LIBVIRT_POOL="libvirt-vms"
    
    log_info "Creating VM: $vm_name"
    
    # Check libvirt pool
    if ! virsh --connect qemu:///system pool-info "$LIBVIRT_POOL" &>/dev/null; then
        log_error "Libvirt pool '$LIBVIRT_POOL' not found"
        exit 1
    fi
    
    if ! virsh --connect qemu:///system pool-info "$LIBVIRT_POOL" | grep -q "State:.*running"; then
        virsh --connect qemu:///system pool-start "$LIBVIRT_POOL" || log_error "Failed to start pool"
    fi
    
    # Create disk
    if [ ! -f "$disk_path" ]; then
        log_info "  Creating disk: $disk_path ($DISK_SIZE)"
        virsh --connect qemu:///system vol-create-as "$LIBVIRT_POOL" "${vm_name}.qcow2" "$DISK_SIZE" --format qcow2 2>/dev/null || {
            qemu-img create -f qcow2 "$disk_path" "$DISK_SIZE"
        }
    fi
    
    # Check if VM exists
    if virsh --connect qemu:///system dominfo "$vm_name" &>/dev/null; then
        log_warn "  VM $vm_name already exists (skipping)"
        return 0
    fi
    
    # Get MAC address
    VM_MAC=""
    if [ -f "$mac_file" ]; then
        VM_MAC=$(grep "^${vm_name}:" "$mac_file" | cut -d' ' -f2)
    fi
    
    if [ -z "$VM_MAC" ]; then
        log_error "MAC address not found for $vm_name in $mac_file"
        exit 1
    fi
    
    log_info "  Using MAC: $VM_MAC"
    
    # Create VM
    OVMF_CODE="/usr/share/qemu/ovmf-x86_64-code.bin"
    virt-install \
        --connect qemu:///system \
        --name "$vm_name" \
        --memory "$MEMORY" \
        --vcpus "$VCPUS" \
        --disk path="$disk_path",format=qcow2,bus=virtio \
        --network bridge="$BRIDGE",model=virtio,mac="$VM_MAC" \
        --cdrom "$iso_path" \
        --boot cdrom,hd \
        --tpm backend.type=emulator,backend.version=2.0,model=tpm-crb \
        --graphics vnc,listen=0.0.0.0 \
        --console pty,target_type=serial \
        --noautoconsole \
        --osinfo detect=on,name=linux2024 \
        --boot loader="$OVMF_CODE",loader_type=pflash,loader_ro=yes \
        --wait -1 2>&1 || \
    virt-install \
        --connect qemu:///system \
        --name "$vm_name" \
        --memory "$MEMORY" \
        --vcpus "$VCPUS" \
        --disk path="$disk_path",format=qcow2,bus=virtio \
        --network bridge="$BRIDGE",model=virtio,mac="$VM_MAC" \
        --cdrom "$iso_path" \
        --boot cdrom,hd \
        --tpm backend.type=emulator,backend.version=2.0,model=tpm-crb \
        --graphics vnc,listen=0.0.0.0 \
        --console pty,target_type=serial \
        --noautoconsole \
        --osinfo detect=on,name=linux2024 \
        --wait -1
    
    log_info "  OK: VM $vm_name created"
}

# Main execution
main() {
    echo "=========================================="
    echo "Creating 10 VMs for 2 Sites (5 VMs each)"
    echo "=========================================="
    echo ""
    
    check_prerequisites
    
    echo "VM Configuration:"
    echo "  - Site A: 5 VMs (site-a-vm-01 to site-a-vm-05)"
    echo "  - Site B: 5 VMs (site-b-vm-01 to site-b-vm-05)"
    echo "  - Disk: 20G per VM"
    echo "  - Memory: 8192MB (8GB) per VM"
    echo "  - vCPUs: 1 per VM"
    echo "  - Network: bridge $BRIDGE (DHCP)"
    echo "  - Execution mode: $([ "$PARALLEL_MODE" = true ] && echo "PARALLEL" || echo "SEQUENTIAL")"
    echo ""
    
    MAC_FILE_A="${SCRIPT_DIR}/vm-mac-addresses-site-a.txt"
    MAC_FILE_B="${SCRIPT_DIR}/vm-mac-addresses-site-b.txt"
    
    # Create Site A VMs
    log_info "Creating Site A VMs..."
    for i in {01..05}; do
        vm_name="site-a-vm-$i"
        if [ "$PARALLEL_MODE" = true ]; then
            create_vm "$vm_name" "$ISO_SITE_A" "$MAC_FILE_A" &
        else
            create_vm "$vm_name" "$ISO_SITE_A" "$MAC_FILE_A"
        fi
    done
    
    # Create Site B VMs
    log_info "Creating Site B VMs..."
    for i in {01..05}; do
        vm_name="site-b-vm-$i"
        if [ "$PARALLEL_MODE" = true ]; then
            create_vm "$vm_name" "$ISO_SITE_B" "$MAC_FILE_B" &
        else
            create_vm "$vm_name" "$ISO_SITE_B" "$MAC_FILE_B"
        fi
    done
    
    if [ "$PARALLEL_MODE" = true ]; then
        wait
    fi

    wait_for_vms_running || true
    
    echo ""
    echo "=========================================="
    log_info "All VMs created successfully"
    echo "=========================================="
    echo ""
    echo "VM Management Commands:"
    echo "  List VMs:        virsh --connect qemu:///system list --all | grep site-"
    echo "  Start Site A:    for i in {01..05}; do virsh --connect qemu:///system start site-a-vm-\$i; done"
    echo "  Start Site B:    for i in {01..05}; do virsh --connect qemu:///system start site-b-vm-\$i; done"
    echo ""
    echo "Monitor Registration:"
    echo "  watch kubectl get machineinventory -n fleet-default -l test-group=dual-site-multinode"
    echo "  watch kubectl get cluster -n fleet-default -l test-group=dual-site-multinode"
}

main


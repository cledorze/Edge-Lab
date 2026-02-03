#!/bin/bash
# Kiosk Standalone K3s - Create Test VM
# Step 2: Create a libvirt VM to test the kiosk image
#
# Prerequisites:
#   - libvirt/KVM installed and running
#   - ISO built from step 01

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="${SCRIPT_DIR}/../.."
EIB_DIR="${PROJECT_ROOT}/EIB-kiosk-standalone"

# VM Configuration
VM_NAME="${VM_NAME:-kiosk-standalone}"
VM_MEMORY="${VM_MEMORY:-4096}"
VM_VCPUS="${VM_VCPUS:-2}"
VM_DISK_SIZE="${VM_DISK_SIZE:-40}"
VM_NETWORK="${VM_NETWORK:-default}"
ISO_PATH="${EIB_DIR}/kiosk-standalone-k3s.iso"

echo ""
echo "╔══════════════════════════════════════════════════════════════╗"
echo "║       Kiosk Standalone K3s - Step 2: Create VM              ║"
echo "╚══════════════════════════════════════════════════════════════╝"
echo ""

# Check ISO exists
if [ ! -f "$ISO_PATH" ]; then
    echo "ERROR: ISO not found: $ISO_PATH"
    echo "Run ./01-build-iso.sh first"
    exit 1
fi

# Check if VM already exists
if virsh dominfo "$VM_NAME" &>/dev/null; then
    echo "WARNING: VM '$VM_NAME' already exists"
    read -p "Delete and recreate? [y/N] " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        echo "Stopping and removing existing VM..."
        virsh destroy "$VM_NAME" 2>/dev/null || true
        virsh undefine "$VM_NAME" --remove-all-storage 2>/dev/null || true
    else
        echo "Aborted."
        exit 1
    fi
fi

echo "Creating VM: $VM_NAME"
echo "  Memory: ${VM_MEMORY}MB"
echo "  vCPUs: ${VM_VCPUS}"
echo "  Disk: ${VM_DISK_SIZE}GB"
echo "  Network: ${VM_NETWORK}"
echo "  ISO: ${ISO_PATH}"
echo ""

# Create VM
virt-install \
    --name "$VM_NAME" \
    --memory "$VM_MEMORY" \
    --vcpus "$VM_VCPUS" \
    --disk size="$VM_DISK_SIZE",format=qcow2,bus=virtio \
    --cdrom "$ISO_PATH" \
    --network network="$VM_NETWORK",model=virtio \
    --os-variant slem6.0 \
    --graphics vnc,listen=0.0.0.0 \
    --video virtio \
    --boot uefi \
    --noautoconsole

echo ""
echo "VM created successfully!"
echo ""
echo "The VM is booting and installing. This takes a few minutes."
echo ""
echo "Monitor the VM:"
echo "  virsh console $VM_NAME"
echo "  virt-viewer $VM_NAME"
echo ""
echo "After installation completes, the VM will reboot."
echo "K3s will start automatically, followed by the kiosk workload."
echo ""
echo "Check status with:"
echo "  virsh domifaddr $VM_NAME"
echo "  ssh root@<ip> kubectl get pods -n kiosk"

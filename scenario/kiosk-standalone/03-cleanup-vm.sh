#!/bin/bash
# Kiosk Standalone K3s - Cleanup Test VM
# Step 3: Remove the test VM and associated storage

set -euo pipefail

VM_NAME="${VM_NAME:-kiosk-standalone}"

echo ""
echo "╔══════════════════════════════════════════════════════════════╗"
echo "║       Kiosk Standalone K3s - Step 3: Cleanup VM             ║"
echo "╚══════════════════════════════════════════════════════════════╝"
echo ""

if ! virsh dominfo "$VM_NAME" &>/dev/null; then
    echo "VM '$VM_NAME' does not exist. Nothing to clean up."
    exit 0
fi

echo "This will delete VM '$VM_NAME' and all its storage."
read -p "Continue? [y/N] " -n 1 -r
echo

if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Aborted."
    exit 0
fi

echo "Stopping VM..."
virsh destroy "$VM_NAME" 2>/dev/null || true

echo "Removing VM and storage..."
virsh undefine "$VM_NAME" --remove-all-storage --nvram 2>/dev/null || \
virsh undefine "$VM_NAME" --remove-all-storage 2>/dev/null || true

echo ""
echo "Cleanup complete."

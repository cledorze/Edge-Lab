#!/bin/bash
# Script to automatically select the first disk >200GB for Elemental installation
# This prevents installation on the USB key from which the ISO is booted
# This script configures Elemental's install.device in /etc/elemental/config.yaml

set -euo pipefail

echo "=== Detecting installation device for Elemental (first disk >200GB) ==="

# Minimum size in GB
MIN_SIZE_GB=200

# Find the first disk >200GB
INSTALL_DEVICE=""
for disk in /dev/sd[a-z] /dev/nvme[0-9]n[0-9] /dev/vd[a-z]; do
    # Check if device exists
    [ -b "$disk" ] || continue
    
    # Skip if it's a partition
    # For nvme: skip if it contains 'p' followed by a number
    # For others: skip if it ends with a number
    if [[ "$disk" =~ nvme.*p[0-9]+$ ]] || [[ "$disk" =~ [0-9]+$ ]]; then
        continue
    fi
    
    # Get disk size in bytes
    SIZE_BYTES=$(blockdev --getsize64 "$disk" 2>/dev/null || echo "0")
    
    # Skip if we couldn't get the size
    [ "$SIZE_BYTES" = "0" ] && continue
    
    # Convert to GB (divide by 1024^3)
    SIZE_GB=$((SIZE_BYTES / 1073741824))
    
    # Check if size is >200GB
    if [ "$SIZE_GB" -gt "$MIN_SIZE_GB" ]; then
        INSTALL_DEVICE="$disk"
        echo "Found suitable disk: $INSTALL_DEVICE (${SIZE_GB}GB)"
        break
    else
        echo "Skipping $disk (${SIZE_GB}GB < ${MIN_SIZE_GB}GB)"
    fi
done

if [ -z "$INSTALL_DEVICE" ]; then
    echo "WARNING: No disk >${MIN_SIZE_GB}GB found, falling back to /dev/sda"
    INSTALL_DEVICE="/dev/sda"
fi

echo "Selected installation device: $INSTALL_DEVICE"

# Update Elemental Configuration file
ELEMENTAL_CONFIG="/etc/elemental/config.yaml"
if [ -f "$ELEMENTAL_CONFIG" ]; then
    # Update the install.device field in the YAML file
    if grep -q "device:" "$ELEMENTAL_CONFIG"; then
        # Update existing device field
        sed -i "s|device:.*|device: $INSTALL_DEVICE|g" "$ELEMENTAL_CONFIG"
    else
        # Add device field under install section
        # Find the install section and add device after it
        if grep -q "install:" "$ELEMENTAL_CONFIG"; then
            sed -i "/install:/a\        device: $INSTALL_DEVICE" "$ELEMENTAL_CONFIG"
        else
            # Add install section with device
            sed -i "/^elemental:/a\    install:\n        device: $INSTALL_DEVICE" "$ELEMENTAL_CONFIG"
        fi
    fi
    echo "Updated $ELEMENTAL_CONFIG with installation device: $INSTALL_DEVICE"
else
    echo "WARNING: Elemental config file not found: $ELEMENTAL_CONFIG"
    echo "Creating it with installation device: $INSTALL_DEVICE"
    mkdir -p /etc/elemental
    cat > "$ELEMENTAL_CONFIG" <<EOF
elemental:
    install:
        device: $INSTALL_DEVICE
EOF
fi

echo "=== Elemental installation device configured: $INSTALL_DEVICE ==="


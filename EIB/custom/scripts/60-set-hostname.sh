#!/bin/bash
# Set hostname based on MAC address
# This script runs during combustion phase to set unique hostname for each VM
# MAC addresses are mapped to hostnames: node1 through node10

set -e

echo "=== Setting hostname based on MAC address ===" | tee -a /var/log/combustion-hostname.log

# Wait for eth0 to be available
for i in {1..30}; do
    if ip link show eth0 &>/dev/null; then
        echo "eth0 interface found" | tee -a /var/log/combustion-hostname.log
        break
    fi
    echo "Waiting for eth0... ($i/30)" | tee -a /var/log/combustion-hostname.log
    sleep 1
done

# Get MAC address
MAC=$(ip link show eth0 | grep -oP 'link/ether \K[^ ]+' | tr '[:lower:]' '[:upper:]' || echo "")
echo "Detected MAC: $MAC" | tee -a /var/log/combustion-hostname.log

# MAC to hostname mapping (case-insensitive matching)
# Format: node<number>-site<letter> (e.g., node1-sitea, node2-siteb)
declare -A MAC_TO_HOSTNAME=(
    # Site A VMs (site-a-vm-01 to site-a-vm-05)
    ["52:54:00:20:30:01"]="node1-sitea"
    ["52:54:00:20:30:02"]="node2-sitea"
    ["52:54:00:20:30:03"]="node3-sitea"
    ["52:54:00:20:30:04"]="node4-sitea"
    ["52:54:00:20:30:05"]="node5-sitea"
    # Site B VMs (site-b-vm-01 to site-b-vm-05)
    ["52:54:00:20:40:01"]="node1-siteb"
    ["52:54:00:20:40:02"]="node2-siteb"
    ["52:54:00:20:40:03"]="node3-siteb"
    ["52:54:00:20:40:04"]="node4-siteb"
    ["52:54:00:20:40:05"]="node5-siteb"
    # Legacy test-vm VMs (for backward compatibility)
    ["52:54:00:02:03:05"]="node1"
    ["52:54:00:04:06:0a"]="node2"
    ["52:54:00:04:06:0A"]="node2"
    ["52:54:00:06:09:0f"]="node3"
    ["52:54:00:06:09:0F"]="node3"
    ["52:54:00:08:0c:14"]="node4"
    ["52:54:00:08:0C:14"]="node4"
    ["52:54:00:0a:0f:19"]="node5"
    ["52:54:00:0A:0F:19"]="node5"
    ["52:54:00:0c:12:1e"]="node6"
    ["52:54:00:0C:12:1E"]="node6"
    ["52:54:00:0e:15:23"]="node7"
    ["52:54:00:0E:15:23"]="node7"
    ["52:54:00:10:18:28"]="node8"
    ["52:54:00:12:1b:2d"]="node9"
    ["52:54:00:12:1B:2D"]="node9"
    ["52:54:00:14:1e:32"]="node10"
    ["52:54:00:14:1E:32"]="node10"
)

# Set hostname based on MAC
if [ -n "$MAC" ] && [ -n "${MAC_TO_HOSTNAME[$MAC]}" ]; then
    HOSTNAME="${MAC_TO_HOSTNAME[$MAC]}"
    echo "Setting hostname to: $HOSTNAME" | tee -a /var/log/combustion-hostname.log
    
    # Set hostname
    hostnamectl set-hostname "$HOSTNAME" || echo "$HOSTNAME" > /etc/hostname
    
    # Update /etc/hostname
    echo "$HOSTNAME" > /etc/hostname
    
    # Update /etc/hosts if it exists
    if [ -f /etc/hosts ]; then
        # Remove old hostname entries
        sed -i '/^127.0.0.1/d' /etc/hosts
        sed -i '/^::1/d' /etc/hosts
        # Add new entry
        echo "127.0.0.1 localhost $HOSTNAME" >> /etc/hosts
        echo "::1 localhost $HOSTNAME" >> /etc/hosts
    fi
    
    echo "✓ Hostname set to: $HOSTNAME" | tee -a /var/log/combustion-hostname.log
else
    echo "WARNING: MAC address $MAC not found in mapping, using default hostname" | tee -a /var/log/combustion-hostname.log
    # Fallback: try to get hostname from network config or use default
    CURRENT_HOSTNAME=$(hostname || echo "slemicro")
    echo "Current hostname: $CURRENT_HOSTNAME" | tee -a /var/log/combustion-hostname.log
fi

echo "=== Hostname configuration complete ===" | tee -a /var/log/combustion-hostname.log


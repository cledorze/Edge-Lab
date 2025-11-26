#!/bin/bash
# Fallback network configuration for DHCP
# This script runs during combustion phase ONLY if nm-configurator (nmc) failed to configure the network
# nmc should have already configured the network from network/*.yaml files during EIB build
# This is a safety fallback in case nmc didn't work correctly

set -e

echo "=== Checking network configuration (fallback script) ===" | tee -a /var/log/combustion-network.log

# Check if network is already configured by nmc
# If eth0 has an IP or a connection exists, nmc likely worked
if ip addr show eth0 2>/dev/null | grep -q "inet " || nmcli connection show eth0 2>/dev/null | grep -q "connection.id"; then
    echo "Network already configured by nm-configurator (nmc). Skipping fallback script." | tee -a /var/log/combustion-network.log
    echo "Current network status:" | tee -a /var/log/combustion-network.log
    ip addr show eth0 2>/dev/null | tee -a /var/log/combustion-network.log || true
    nmcli connection show eth0 2>/dev/null | tee -a /var/log/combustion-network.log || true
    exit 0
fi

echo "nmc configuration not detected. Applying fallback DHCP configuration..." | tee -a /var/log/combustion-network.log
echo "=== Configuring network for DHCP (fallback) ===" | tee -a /var/log/combustion-network.log

# Wait for eth0 to be available
for i in {1..30}; do
    if ip link show eth0 &>/dev/null; then
        echo "eth0 interface found" | tee -a /var/log/combustion-network.log
        break
    fi
    echo "Waiting for eth0... ($i/30)" | tee -a /var/log/combustion-network.log
    sleep 1
done

# Get MAC address
MAC=$(ip link show eth0 | grep -oP 'link/ether \K[^ ]+' || echo "")
echo "Detected MAC: $MAC" | tee -a /var/log/combustion-network.log

# Check if NetworkManager is available
if ! command -v nmcli &>/dev/null; then
    echo "ERROR: nmcli not found, trying to install NetworkManager..." | tee -a /var/log/combustion-network.log
    # NetworkManager should be installed, but if not, we'll use systemd-networkd
    if command -v systemctl &>/dev/null; then
        echo "Using systemd-networkd as fallback..." | tee -a /var/log/combustion-network.log
        cat > /etc/systemd/network/10-eth0.network << NETCONF
[Match]
Name=eth0

[Network]
DHCP=yes
LinkLocalAddressing=yes
NETCONF
        systemctl enable systemd-networkd 2>/dev/null || true
        systemctl start systemd-networkd 2>/dev/null || true
    fi
    exit 0
fi

# Remove any existing connection
echo "Removing existing connections..." | tee -a /var/log/combustion-network.log
nmcli connection delete eth0 2>/dev/null || true
nmcli connection delete "Wired connection 1" 2>/dev/null || true

# Create new connection with DHCP
echo "Creating DHCP connection..." | tee -a /var/log/combustion-network.log
nmcli connection add type ethernet \
    ifname eth0 \
    name eth0 \
    autoconnect yes \
    ipv4.method auto \
    ipv4.dhcp-timeout 60 \
    ipv6.method ignore \
    connection.autoconnect-priority 100 2>&1 | tee -a /var/log/combustion-network.log || {
    echo "ERROR: Failed to create connection" | tee -a /var/log/combustion-network.log
    exit 1
}

# Bring up the connection
echo "Bringing up connection..." | tee -a /var/log/combustion-network.log
nmcli connection up eth0 2>&1 | tee -a /var/log/combustion-network.log || {
    echo "WARNING: Failed to bring up connection, will retry..." | tee -a /var/log/combustion-network.log
    sleep 5
    nmcli connection up eth0 2>&1 | tee -a /var/log/combustion-network.log || true
}

# Wait for DHCP with longer timeout
echo "Waiting for DHCP lease (up to 60 seconds)..." | tee -a /var/log/combustion-network.log
for i in {1..60}; do
    if ip addr show eth0 | grep -q "inet "; then
        IP=$(ip addr show eth0 | grep -oP 'inet \K[^ ]+')
        echo "✅ DHCP lease obtained! IP: $IP" | tee -a /var/log/combustion-network.log
        ip addr show eth0 | tee -a /var/log/combustion-network.log
        ip route show | tee -a /var/log/combustion-network.log
        break
    fi
    if [ $((i % 10)) -eq 0 ]; then
        echo "Still waiting... ($i/60)" | tee -a /var/log/combustion-network.log
    fi
    sleep 1
done

# Show final status
echo "=== Network configuration complete ===" | tee -a /var/log/combustion-network.log
ip addr show eth0 | tee -a /var/log/combustion-network.log
ip route show | tee -a /var/log/combustion-network.log
nmcli connection show eth0 2>&1 | tee -a /var/log/combustion-network.log || true

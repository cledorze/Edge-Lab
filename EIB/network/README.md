# Network Configuration with nm-configurator

This directory contains NetworkManager desired state configuration files for nm-configurator.

## How it works

1. During combustion, `60-set-hostname.sh` sets the hostname based on MAC address
2. nm-configurator (nmc) runs automatically and uses the hostname to select the appropriate network configuration
3. The network configuration file matching the hostname (e.g., `node1-sitea.yaml` for hostname `node1-sitea`) is applied
4. If nm-configurator fails, `70-configure-network.sh` provides a DHCP fallback

## File naming convention

Network configuration files are named after the hostname they configure:
- `node1-sitea.yaml` → for hostname `node1-sitea`
- `node2-sitea.yaml` → for hostname `node2-sitea`
- etc.

## Configuration format

Files use NetworkManager connection format (YAML). Each file specifies:
- Connection ID and type
- Interface name (eth0)
- MAC address (for matching)
- IPv4 method (auto/DHCP)
- IPv6 method (ignore)

## MAC address mapping

| Hostname | MAC Address | VM |
|----------|-------------|-----|
| node1-sitea | 52:54:00:20:30:01 | site-a-vm-01 |
| node2-sitea | 52:54:00:20:30:02 | site-a-vm-02 |
| node3-sitea | 52:54:00:20:30:03 | site-a-vm-03 |
| node4-sitea | 52:54:00:20:30:04 | site-a-vm-04 |
| node5-sitea | 52:54:00:20:30:05 | site-a-vm-05 |
| node1-siteb | 52:54:00:20:40:01 | site-b-vm-01 |
| node2-siteb | 52:54:00:20:40:02 | site-b-vm-02 |
| node3-siteb | 52:54:00:20:40:03 | site-b-vm-03 |
| node4-siteb | 52:54:00:20:40:04 | site-b-vm-04 |
| node5-siteb | 52:54:00:20:40:05 | site-b-vm-05 |

## References

- [EIB Network Configuration Documentation](https://github.com/suse-edge/edge-image-builder/blob/release-1.3/docs/building-images.md#network-configuration)
- [nm-configurator Documentation](https://github.com/suse-edge/nm-configurator/)


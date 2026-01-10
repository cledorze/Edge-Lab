# Scenario: Metal3 Demo Deployment

This scenario automates the deployment of the [SUSE Edge Metal3 Demo](https://github.com/suse-edge/metal3-demo) on this host.

## Overview

Metal3 (Metal-Kubed) allows for bare metal host management using Kubernetes-native APIs. This demo creates:
1.  A **Management Cluster** (running in a VM on this host).
2.  **Virtual Bare Metal Hosts** (emulated by VMs on this host, managed via Virtual BMC / Sushy).
3.  A **Workload Cluster** (deployed on the virtual bare metal hosts using Cluster API).

## Directory Structure

```
metal3-demo-deployment/
├── 01_prepare_host.sh         # Step 1: Install host prerequisites
├── 02_configure_host.sh       # Step 2: Configure libvirt and networks
├── 03_build_images.sh         # Step 3: Build base images for VMs
├── 04_launch_mgmt_cluster.sh  # Step 4: Launch management cluster VM
├── 05_apply_bmh.sh            # Step 5: Register virtual BM hosts
├── 06_deploy_workload.sh      # Step 6: Deploy RKE2 workload cluster
├── 07_health_check.sh         # Health check and auto-fix script
├── docs/
│   └── TROUBLESHOOTING.md     # Troubleshooting guide
└── ... (original demo files)
```

## Quick Start

1.  **Prepare Host**:
    ```bash
    ./01_prepare_host.sh
    ```
    *Note: This will install `ansible`, `pkgconf`, and other dependencies via `zypper`.*

2.  **Configure Host**:
    ```bash
    ./02_configure_host.sh
    ```
    *Note: This creates a libvirt network named `external` with bridge `m3-external` (192.168.125.0/24).*

3.  **Build Images**:
    ```bash
    ./03_build_images.sh
    ```

4.  **Launch Management Cluster**:
    ```bash
    ./04_launch_mgmt_cluster.sh
    ```

5.  **Apply BareMetalHosts**:
    ```bash
    ./05_apply_bmh.sh
    ```

6.  **Deploy Workload Cluster**:
    ```bash
    ./06_deploy_workload.sh
    ```

## Health Check & Troubleshooting

After deployment, run the health check script to verify all components:

```bash
./07_health_check.sh
```

If you encounter issues (BMH errors, provisioning failures), see:
- [Troubleshooting Guide](docs/TROUBLESHOOTING.md)

### Common Issues

| Issue | Symptom | Quick Fix |
|-------|---------|-----------|
| sushy-tools connection lost | BMH "registration error" | `sudo podman restart sushy-tools` |
| image-cache not running | BMH "provisioning error" (ECONNREFUSED) | Start image-cache container |
| Ironic state cache | BMH stuck in error | Restart Ironic deployment |

## Accessing the Workload Cluster

```bash
# Get kubeconfig for workload cluster
export KUBECONFIG=./metal3-mgmt.kubeconfig
clusterctl get kubeconfig sample-cluster > /tmp/sample-cluster.kubeconfig

# Access workload cluster
KUBECONFIG=/tmp/sample-cluster.kubeconfig kubectl get nodes
```

## Notes

- All original files from `suse-edge/metal3-demo` are preserved.
- The deployment uses `192.168.125.0/24` for the emulated baremetal network.
- Virtual BMC is provided by `sushy-tools` listening on port 8000.
- OS images are served by `image-cache` container on port 8443.

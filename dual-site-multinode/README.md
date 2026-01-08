# Scenario: Dual-Site Multinode (3 CP + 2 Workers)

This scenario deploys a 2-site infrastructure where each site is a **multinode Kubernetes cluster** instead of 5 separate single-node clusters.

## Architecture
- **Site A**: 1 Cluster (3 Control-Plane nodes, 2 Worker nodes)
- **Site B**: 1 Cluster (3 Control-Plane nodes, 2 Worker nodes)
- **Total VMs**: 10 (5 per site)
- **GitOps**: Fleet deploys workloads to each site-specific cluster group.

## Configuration changes
- `vms-config-2-sites.csv`: Defines 2 clusters with `cp-nodes=3` and `worker-nodes=2`.
- `site-a-registration.yaml`: Labels machines with `site-id=site-a` (all 5 nodes get the same label).
- `SelectorTemplates`: Automatically matches all 5 nodes to the same cluster definition in Rancher.

## Deployment Steps
1. `./1-cleanup-vms.sh`: Clean existing environment.
2. `./2-create-registration-endpoints.sh`: Create the 2 registration endpoints.
3. `./3-build-isos-2-sites.sh`: Build the 2 ISOs (one per site).
4. `./4-create-rancher-resources.sh`: Pre-create the Cluster resources in Rancher.
5. `./5-create-fleet-resources.sh`: Setup Fleet for GitOps.
6. `./6-create-vms-2-sites.sh --sequential`: Provision and start the 10 VMs.
7. Wait for registration and cluster provisioning.
8. `./8-label-clusters.sh`: Label the clusters for Fleet selection.

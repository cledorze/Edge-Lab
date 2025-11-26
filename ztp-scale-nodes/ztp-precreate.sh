#!/bin/bash
# Zero Touch Provisioning (ZTP) Pre-creation Script for SUSE Edge Elemental
# This script automates the creation of Kubernetes objects required for ZTP
# with SUSE Edge Elemental in phone-home scenarios.
#
# Usage:
#   ./ztp-precreate.sh --site <site-name> [options]
#   ./ztp-precreate.sh --batch <csv-file> [options]
#   ./ztp-precreate.sh --help

set -euo pipefail

# Script version
SCRIPT_VERSION="1.0.0"

# Default values
DEFAULT_NAMESPACE="fleet-default"
DEFAULT_K8S_VERSION_K3S="v1.30.5+k3s1"
DEFAULT_K8S_VERSION_RKE2="v1.30.5+rke2r1"
DEFAULT_DISTRO="k3s"
DEFAULT_CP_COUNT=1
DEFAULT_WORKER_COUNT=0
DEFAULT_SINGLE_NODE=false

# Global variables
SITE_NAME=""
NAMESPACE="${DEFAULT_NAMESPACE}"
K8S_VERSION=""
DISTRO="${DEFAULT_DISTRO}"
CP_COUNT=${DEFAULT_CP_COUNT}
WORKER_COUNT=${DEFAULT_WORKER_COUNT}
SINGLE_NODE=${DEFAULT_SINGLE_NODE}
VIP=""
LABELS=""
DRY_RUN=false
BATCH_MODE=false
BATCH_FILE=""
APPLY_RESOURCES=true
OUTPUT_DIR=""
VERBOSE=false

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions
log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1" >&2
}

log_debug() {
    if [ "$VERBOSE" = true ]; then
        echo -e "${BLUE}[DEBUG]${NC} $1"
    fi
}

# Print usage information
usage() {
    cat << EOF
Zero Touch Provisioning (ZTP) Pre-creation Script for SUSE Edge Elemental
Version: ${SCRIPT_VERSION}

DESCRIPTION:
    This script automates the creation of Kubernetes objects required for ZTP
    with SUSE Edge Elemental. It creates MachineInventorySelectorTemplate and
    Cluster (provisioning.cattle.io/v1) resources before physical machines
    boot and register.

USAGE:
    ./ztp-precreate.sh --site <site-name> [OPTIONS]
    ./ztp-precreate.sh --batch <csv-file> [OPTIONS]
    ./ztp-precreate.sh --help

OPTIONS:
    --site <name>              Site/cluster name (required for single site mode)
    --namespace <ns>           Kubernetes namespace (default: ${DEFAULT_NAMESPACE})
    --k3s                      Use K3s distribution (default)
    --rke2                     Use RKE2 distribution
    --k8s-version <version>    Kubernetes version
                               (default: ${DEFAULT_K8S_VERSION_K3S} for K3s,
                                        ${DEFAULT_K8S_VERSION_RKE2} for RKE2)
    --single-node              Single-node cluster (control-plane + worker roles)
    --cp-nodes <count>         Number of control-plane nodes (default: ${DEFAULT_CP_COUNT})
    --worker-nodes <count>     Number of worker nodes (default: ${DEFAULT_WORKER_COUNT})
    --vip <ip>                 Virtual IP for multi-node HA setup
    --labels <key=value,...>   Additional labels for machine selection
                               (format: key1=value1,key2=value2)
    --batch <file>             Batch mode: process multiple sites from CSV file
    --dry-run                  Generate YAML without applying to cluster
    --output-dir <dir>         Save generated manifests to directory
    --no-apply                 Generate manifests but do not apply
    --verbose                  Enable verbose output
    --help                     Show this help message

BATCH FILE FORMAT (CSV):
    site-name,namespace,distro,k8s-version,cp-nodes,worker-nodes,single-node,vip,labels
    paris-edge-01,fleet-default,k3s,v1.30.5+k3s1,1,0,true,,site-id=paris-edge-01
    berlin-dc-02,fleet-default,rke2,v1.30.5+rke2r1,3,2,false,10.1.1.100,site-id=berlin-dc-02

EXAMPLES:
    # Single site with K3s, single-node
    ./ztp-precreate.sh --site paris-edge-01 --k3s --single-node --apply

    # Multiple sites from CSV file (dry-run)
    ./ztp-precreate.sh --batch sites.csv --dry-run

    # Advanced configuration with RKE2, multi-node
    ./ztp-precreate.sh --site berlin-dc-02 --rke2 --cp-nodes 3 --worker-nodes 2 \\
                       --vip 10.1.1.100 --labels site-id=berlin-dc-02,deployment=ztp-wave1

    # Generate manifests without applying
    ./ztp-precreate.sh --site test-site --k3s --single-node --output-dir ./manifests --no-apply

EOF
}

# Validate prerequisites
validate_prerequisites() {
    log_info "Validating prerequisites..."
    
    # Check kubectl
    if ! command -v kubectl &> /dev/null; then
        log_error "kubectl is not installed or not in PATH"
        log_info "Install kubectl or set KUBECONFIG environment variable"
        exit 1
    fi
    
    # Check cluster access
    if ! kubectl cluster-info &> /dev/null; then
        log_error "Cannot access Kubernetes cluster"
        log_info "Configure KUBECONFIG: export KUBECONFIG=/home/tofix/LAB/EIB-demo-1/scale-out-eib-elemental/rancher-provisioning-setup/rke2.yaml"
        exit 1
    fi
    
    log_debug "Prerequisites validated successfully"
}

# Parse labels string into YAML format
# Excludes 'site-id' as it's automatically added from site_name
parse_labels() {
    local labels_str="$1"
    local yaml_labels=""
    
    if [ -z "$labels_str" ]; then
        echo ""
        return
    fi
    
    IFS=',' read -ra LABEL_ARRAY <<< "$labels_str"
    for label in "${LABEL_ARRAY[@]}"; do
        IFS='=' read -ra LABEL_PAIR <<< "$label"
        if [ ${#LABEL_PAIR[@]} -eq 2 ]; then
            # Skip site-id as it's already added from site_name
            if [ "${LABEL_PAIR[0]}" = "site-id" ]; then
                continue
            fi
            if [ -n "$yaml_labels" ]; then
                yaml_labels="${yaml_labels}\n          ${LABEL_PAIR[0]}: ${LABEL_PAIR[1]}"
            else
                yaml_labels="          ${LABEL_PAIR[0]}: ${LABEL_PAIR[1]}"
            fi
        fi
    done
    
    echo -e "$yaml_labels"
}

# Generate MachineInventorySelectorTemplate YAML
generate_selector_template() {
    local site_name="$1"
    local namespace="$2"
    local labels_yaml="$3"
    
    # Build matchLabels section
    local match_labels="          site-id: ${site_name}"
    if [ -n "$labels_yaml" ]; then
        # Labels already have correct indentation (10 spaces), just append
        match_labels="${match_labels}
$(echo -e "$labels_yaml")"
    fi
    
    cat << EOF
apiVersion: elemental.cattle.io/v1beta1
kind: MachineInventorySelectorTemplate
metadata:
  name: ${site_name}-selector
  namespace: ${namespace}
spec:
  template:
    spec:
      selector:
        matchLabels:
${match_labels}
EOF
}

# Generate Cluster YAML
generate_cluster() {
    local site_name="$1"
    local namespace="$2"
    local k8s_version="$3"
    local cp_count="$4"
    local worker_count="$5"
    local single_node="$6"
    local vip="$7"
    
    # Determine worker role based on single-node flag
    local worker_role="false"
    if [ "$single_node" = true ]; then
        worker_role="true"
    fi
    
    # Build machinePools
    local machine_pools=""
    
    # Control plane pool
    machine_pools="    - name: control-plane
      quantity: ${cp_count}
      etcdRole: true
      controlPlaneRole: true
      workerRole: ${worker_role}
      machineConfigRef:
        kind: MachineInventorySelectorTemplate
        name: ${site_name}-selector
        apiVersion: elemental.cattle.io/v1beta1"
    
    # Worker pool (only if not single-node and worker_count > 0)
    if [ "$single_node" = false ] && [ "$worker_count" -gt 0 ]; then
        machine_pools="${machine_pools}
    - name: workers
      quantity: ${worker_count}
      etcdRole: false
      controlPlaneRole: false
      workerRole: true
      machineConfigRef:
        kind: MachineInventorySelectorTemplate
        name: ${site_name}-selector
        apiVersion: elemental.cattle.io/v1beta1"
    fi
    
    # Build cluster YAML
    local cluster_yaml="apiVersion: provisioning.cattle.io/v1
kind: Cluster
metadata:
  name: ${site_name}
  namespace: ${namespace}
spec:
  kubernetesVersion: ${k8s_version}
  rkeConfig:
    machinePools:
${machine_pools}"
    
    # Add VIP configuration if provided
    if [ -n "$vip" ]; then
        cluster_yaml="${cluster_yaml}
    controlPlaneConfig:
      clusterUpgradeStrategy:
        controlPlaneConcurrency: \"1\"
        workerConcurrency: \"1\"
    localClusterAuthEndpoint:
      enabled: true
      fqdn: ${vip}"
    fi
    
    echo "$cluster_yaml"
}

# Validate site configuration
validate_site_config() {
    local site_name="$1"
    local cp_count="$2"
    local worker_count="$3"
    local single_node="$4"
    
    # Validate site name
    if [ -z "$site_name" ]; then
        log_error "Site name is required"
        exit 1
    fi
    
    # Validate site name format (alphanumeric and hyphens)
    if ! [[ "$site_name" =~ ^[a-z0-9]([-a-z0-9]*[a-z0-9])?$ ]]; then
        log_error "Invalid site name: $site_name (must be lowercase alphanumeric with hyphens)"
        exit 1
    fi
    
    # Validate node counts
    if [ "$cp_count" -lt 1 ]; then
        log_error "Control-plane node count must be at least 1"
        exit 1
    fi
    
    if [ "$worker_count" -lt 0 ]; then
        log_error "Worker node count cannot be negative"
        exit 1
    fi
    
    # Validate single-node configuration
    if [ "$single_node" = true ] && [ "$worker_count" -gt 0 ]; then
        log_warn "Single-node mode enabled, worker nodes will be ignored"
    fi
    
    log_debug "Site configuration validated: $site_name"
}

# Create resources for a single site
create_site() {
    local site_name="$1"
    local namespace="$2"
    local k8s_version="$3"
    local distro="$4"
    local cp_count="$5"
    local worker_count="$6"
    local single_node="$7"
    local vip="$8"
    local labels_str="$9"
    
    log_info "Creating ZTP resources for site: $site_name"
    
    # Validate configuration
    validate_site_config "$site_name" "$cp_count" "$worker_count" "$single_node"
    
    # Parse labels
    local labels_yaml=$(parse_labels "$labels_str")
    
    # Generate YAML manifests
    local selector_yaml=$(generate_selector_template "$site_name" "$namespace" "$labels_yaml")
    local cluster_yaml=$(generate_cluster "$site_name" "$namespace" "$k8s_version" \
                                          "$cp_count" "$worker_count" "$single_node" "$vip")
    
    # Combine manifests
    local combined_yaml="${selector_yaml}
---
${cluster_yaml}"
    
    # Output directory handling
    if [ -n "$OUTPUT_DIR" ]; then
        mkdir -p "$OUTPUT_DIR"
        local output_file="${OUTPUT_DIR}/${site_name}.yaml"
        echo "$combined_yaml" > "$output_file"
        log_info "Manifests saved to: $output_file"
    fi
    
    # Dry-run mode
    if [ "$DRY_RUN" = true ]; then
        log_info "=== DRY RUN: Generated manifests for $site_name ==="
        echo "$combined_yaml"
        echo ""
        return 0
    fi
    
    # Apply resources
    if [ "$APPLY_RESOURCES" = true ]; then
        log_info "Applying resources to cluster..."
        
        # Check if namespace exists, create if not
        if ! kubectl get namespace "$namespace" &> /dev/null; then
            log_info "Creating namespace: $namespace"
            kubectl create namespace "$namespace"
        fi
        
        # Apply MachineInventorySelectorTemplate
        log_debug "Applying MachineInventorySelectorTemplate: ${site_name}-selector"
        echo "$selector_yaml" | kubectl apply -f - || {
            log_error "Failed to apply MachineInventorySelectorTemplate"
            return 1
        }
        
        # Apply Cluster
        log_debug "Applying Cluster: $site_name"
        echo "$cluster_yaml" | kubectl apply -f - || {
            log_error "Failed to apply Cluster"
            return 1
        }
        
        log_info "OK: Resources created successfully for site: $site_name"
        
        # Verify resources
        log_info "Verifying created resources..."
        kubectl get machineinventoryselectortemplate "${site_name}-selector" -n "$namespace" &> /dev/null && \
        kubectl get cluster "$site_name" -n "$namespace" &> /dev/null && {
            log_info "OK: Verification successful"
        } || {
            log_warn "Verification failed, resources may not be ready yet"
        }
    else
        log_info "Manifests generated (--no-apply specified, not applying)"
        echo "$combined_yaml"
    fi
}

# Process batch file
process_batch() {
    local batch_file="$1"
    
    if [ ! -f "$batch_file" ]; then
        log_error "Batch file not found: $batch_file"
        exit 1
    fi
    
    log_info "Processing batch file: $batch_file"
    
    local line_num=0
    local success_count=0
    local error_count=0
    
    # Read CSV file (skip header if present)
    while IFS=',' read -r site_name namespace distro k8s_version cp_count worker_count single_node vip labels || [ -n "$site_name" ]; do
        line_num=$((line_num + 1))
        
        # Skip empty lines and header
        if [ -z "$site_name" ] || [ "$site_name" = "site-name" ]; then
            continue
        fi
        
        # Trim whitespace
        site_name=$(echo "$site_name" | xargs)
        namespace=$(echo "${namespace:-$DEFAULT_NAMESPACE}" | xargs)
        distro=$(echo "${distro:-$DEFAULT_DISTRO}" | xargs)
        k8s_version=$(echo "$k8s_version" | xargs)
        cp_count=$(echo "${cp_count:-$DEFAULT_CP_COUNT}" | xargs)
        worker_count=$(echo "${worker_count:-$DEFAULT_WORKER_COUNT}" | xargs)
        single_node=$(echo "${single_node:-false}" | xargs)
        vip=$(echo "$vip" | xargs)
        labels=$(echo "$labels" | xargs)
        
        # Set default K8s version based on distro
        if [ -z "$k8s_version" ]; then
            if [ "$distro" = "rke2" ]; then
                k8s_version="$DEFAULT_K8S_VERSION_RKE2"
            else
                k8s_version="$DEFAULT_K8S_VERSION_K3S"
            fi
        fi
        
        # Convert single_node string to boolean
        local single_node_bool=false
        if [ "$single_node" = "true" ] || [ "$single_node" = "1" ] || [ "$single_node" = "yes" ]; then
            single_node_bool=true
        fi
        
        log_info "Processing site $line_num: $site_name"
        
        if create_site "$site_name" "$namespace" "$k8s_version" "$distro" \
                      "$cp_count" "$worker_count" "$single_node_bool" "$vip" "$labels"; then
            success_count=$((success_count + 1))
        else
            error_count=$((error_count + 1))
            log_error "Failed to create resources for site: $site_name"
        fi
        
        echo ""
    done < "$batch_file"
    
    log_info "Batch processing completed: $success_count successful, $error_count failed"
}

# Parse command line arguments
parse_args() {
    if [ $# -eq 0 ]; then
        usage
        exit 1
    fi
    
    while [[ $# -gt 0 ]]; do
        case $1 in
            --site)
                SITE_NAME="$2"
                shift 2
                ;;
            --namespace)
                NAMESPACE="$2"
                shift 2
                ;;
            --k3s)
                DISTRO="k3s"
                shift
                ;;
            --rke2)
                DISTRO="rke2"
                shift
                ;;
            --k8s-version)
                K8S_VERSION="$2"
                shift 2
                ;;
            --single-node)
                SINGLE_NODE=true
                shift
                ;;
            --cp-nodes)
                CP_COUNT="$2"
                shift 2
                ;;
            --worker-nodes)
                WORKER_COUNT="$2"
                shift 2
                ;;
            --vip)
                VIP="$2"
                shift 2
                ;;
            --labels)
                LABELS="$2"
                shift 2
                ;;
            --batch)
                BATCH_MODE=true
                BATCH_FILE="$2"
                shift 2
                ;;
            --dry-run)
                DRY_RUN=true
                APPLY_RESOURCES=false
                shift
                ;;
            --output-dir)
                OUTPUT_DIR="$2"
                shift 2
                ;;
            --no-apply)
                APPLY_RESOURCES=false
                shift
                ;;
            --verbose)
                VERBOSE=true
                shift
                ;;
            --help)
                usage
                exit 0
                ;;
            *)
                log_error "Unknown option: $1"
                usage
                exit 1
                ;;
        esac
    done
    
    # Validate required parameters
    if [ "$BATCH_MODE" = false ] && [ -z "$SITE_NAME" ]; then
        log_error "Site name is required (use --site <name> or --batch <file>)"
        usage
        exit 1
    fi
    
    # Set default K8s version if not specified
    if [ -z "$K8S_VERSION" ]; then
        if [ "$DISTRO" = "rke2" ]; then
            K8S_VERSION="$DEFAULT_K8S_VERSION_RKE2"
        else
            K8S_VERSION="$DEFAULT_K8S_VERSION_K3S"
        fi
    fi
    
    # Validate node counts are integers
    if ! [[ "$CP_COUNT" =~ ^[0-9]+$ ]]; then
        log_error "Control-plane node count must be a positive integer"
        exit 1
    fi
    
    if ! [[ "$WORKER_COUNT" =~ ^[0-9]+$ ]]; then
        log_error "Worker node count must be a non-negative integer"
        exit 1
    fi
}

# Main function
main() {
    log_info "ZTP Pre-creation Script v${SCRIPT_VERSION}"
    log_info "=========================================="
    
    # Parse arguments
    parse_args "$@"
    
    # Validate prerequisites (skip in dry-run mode if no cluster access needed)
    if [ "$DRY_RUN" = false ] && [ "$APPLY_RESOURCES" = true ]; then
        validate_prerequisites
    fi
    
    # Process batch mode or single site
    if [ "$BATCH_MODE" = true ]; then
        process_batch "$BATCH_FILE"
    else
        create_site "$SITE_NAME" "$NAMESPACE" "$K8S_VERSION" "$DISTRO" \
                   "$CP_COUNT" "$WORKER_COUNT" "$SINGLE_NODE" "$VIP" "$LABELS"
    fi
    
    log_info "=========================================="
    log_info "Script completed successfully"
}

# Run main function
main "$@"


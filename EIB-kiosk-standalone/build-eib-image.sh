#!/bin/bash
# EIB Image Build Script - Kiosk Standalone K3s
# Builds an EIB image with K3s and Firefox kiosk pre-deployed
# No Rancher/Elemental registration - fully standalone

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Configuration
EIB_VERSION="1.3.0"
EIB_IMAGE="registry.suse.com/edge/3.4/edge-image-builder:${EIB_VERSION}"
CONFIG_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OUTPUT_DIR="/mnt/build-data/eib-output"
DEFINITION_FILE="iso-definition.yaml"
BASE_IMAGE="SL-Micro.x86_64-6.1-Base-RT-SelfInstall-GM.install.iso"

# Logging functions
log() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $1"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1" >&2
    exit 1
}

warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

# Prerequisites check
check_prerequisites() {
    log "Checking prerequisites..."

    # Check podman
    if ! command -v podman &> /dev/null; then
        error "Podman is not installed. Install it with: sudo zypper install podman"
    fi

    # Check base image
    if [ ! -f "${CONFIG_DIR}/base-images/${BASE_IMAGE}" ]; then
        error "Base image not found: ${CONFIG_DIR}/base-images/${BASE_IMAGE}"
        echo "Please download it from: https://www.suse.com/download/sle-micro/"
    fi

    # Check definition file
    if [ ! -f "${CONFIG_DIR}/${DEFINITION_FILE}" ]; then
        error "Definition file not found: ${CONFIG_DIR}/${DEFINITION_FILE}"
    fi

    # Check kubernetes manifests
    local manifest_count=$(find "${CONFIG_DIR}/kubernetes/manifests" -name "*.yaml" 2>/dev/null | wc -l)
    if [ "$manifest_count" -gt 0 ]; then
        info "Found ${manifest_count} Kubernetes manifest(s) to deploy"
    else
        warning "No Kubernetes manifests found in ${CONFIG_DIR}/kubernetes/manifests/"
    fi

    log "Prerequisites check completed"
}

# Create output directory
prepare_output() {
    log "Preparing output directory..."
    mkdir -p "${OUTPUT_DIR}"
    log "Output directory ready: ${OUTPUT_DIR}"
}

# Build the image
build_image() {
    log "Starting EIB image build..."
    log "This may take several minutes..."
    log "Using EIB image: ${EIB_IMAGE}"
    log "Definition file: ${DEFINITION_FILE}"
    log ""

    # EIB build command
    mkdir -p /mnt/build-data/tmp
    podman run --rm --privileged --security-opt label=disable \
        -v "${CONFIG_DIR}:/eib" \
        -v "${OUTPUT_DIR}:/build" \
        -v "/mnt/build-data/tmp:/var/tmp" \
        "${EIB_IMAGE}" \
        build \
        --definition-file "${DEFINITION_FILE}" \
        --config-dir /eib \
        --build-dir /build

    if [ $? -eq 0 ]; then
        log "Image built successfully"
    else
        error "Image build failed"
    fi
}

# Post-processing
post_process() {
    log "Post-processing image..."

    # Find generated image
    local iso_file=$(find "${CONFIG_DIR}" -maxdepth 1 -name "*.iso" -type f | head -n1)
    if [ -z "$iso_file" ]; then
        iso_file=$(find "${OUTPUT_DIR}" -name "*.iso" -type f | head -n1)
    fi

    if [ -z "$iso_file" ]; then
        error "No ISO image found in ${CONFIG_DIR} or ${OUTPUT_DIR}"
    fi

    # Calculate checksum
    local checksum_file="${iso_file}.sha256"
    sha256sum "$iso_file" > "$checksum_file"

    log "Image generated: $iso_file"
    log "Checksum: $checksum_file"

    # Display information
    echo ""
    echo "╔══════════════════════════════════════════════════════════════╗"
    echo "║     Kiosk Standalone K3s - Build completed successfully!     ║"
    echo "╚══════════════════════════════════════════════════════════════╝"
    echo ""
    echo "ISO Image: $iso_file"
    echo "Size: $(du -h "$iso_file" | cut -f1)"
    echo "SHA256: $(cut -d' ' -f1 "$checksum_file")"
    echo ""
    echo "This image includes:"
    echo "  - SL Micro 6.1 (SUSE Edge 3.4)"
    echo "  - K3s v1.33.5+k3s1 (singlenode, standalone)"
    echo "  - Firefox kiosk DaemonSet (auto-deployed)"
    echo ""
    echo "Next steps:"
    echo "  1. Boot the target machine from the ISO"
    echo "  2. Installation is fully unattended (on /dev/vda)"
    echo "  3. K3s will start automatically on first boot"
    echo "  4. Kiosk workload deploys automatically once K3s is ready"
    echo ""
    echo "Access:"
    echo "  - SSH: root@<ip> or tofix@<ip>"
    echo "  - Kubectl: ssh root@<ip> kubectl get pods -n kiosk"
    echo ""
}

# Main
main() {
    echo ""
    echo "╔══════════════════════════════════════════════════════════════╗"
    echo "║    SUSE Edge 3.4 - Kiosk Standalone K3s Image Builder       ║"
    echo "║    No Rancher/Elemental - Fully Standalone                  ║"
    echo "╚══════════════════════════════════════════════════════════════╝"
    echo ""

    check_prerequisites
    prepare_output
    build_image
    post_process
}

# Execution
main "$@"

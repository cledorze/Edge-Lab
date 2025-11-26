#!/bin/bash
# EIB Image Build Script for Rancher Fleet
# Builds an EIB image with Elemental registration for Rancher

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Configuration
EIB_VERSION="1.3.0"
EIB_IMAGE="registry.suse.com/edge/3.4/edge-image-builder:${EIB_VERSION}"
CONFIG_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OUTPUT_DIR="${CONFIG_DIR}/output"
DEFINITION_FILE="iso-VM-definition.yaml"
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
        echo "Expected file: ${CONFIG_DIR}/base-images/${BASE_IMAGE}"
        echo "Please download it from: https://www.suse.com/download/sle-micro/"
    fi
    
    # Check definition file
    if [ ! -f "${CONFIG_DIR}/${DEFINITION_FILE}" ]; then
        error "Definition file not found: ${CONFIG_DIR}/${DEFINITION_FILE}"
    fi
    
    # Check Elemental config (warning if placeholder)
    if [ -f "${CONFIG_DIR}/elemental/elemental_config.yaml" ]; then
        if grep -q "This file must be downloaded" "${CONFIG_DIR}/elemental/elemental_config.yaml"; then
            warning "Elemental config appears to be a placeholder template"
            warning "Make sure you've downloaded the actual elemental_config.yaml from Rancher UI"
        fi
    else
        warning "Elemental config file not found: ${CONFIG_DIR}/elemental/elemental_config.yaml"
        warning "You may need to download it from Rancher UI"
    fi
    
    log "✓ Prerequisites check completed"
}

# Create output directory
prepare_output() {
    log "Preparing output directory..."
    mkdir -p "${OUTPUT_DIR}"
    log "✓ Output directory ready: ${OUTPUT_DIR}"
}

# Build the image
build_image() {
    log "Starting EIB image build..."
    log "This may take several minutes..."
    log "Using EIB image: ${EIB_IMAGE}"
    log "Definition file: ${DEFINITION_FILE}"
    log ""
    
    # EIB build command
    podman run --rm --privileged \
        -v "${CONFIG_DIR}:/eib:Z" \
        -v "${OUTPUT_DIR}:/build:Z" \
        "${EIB_IMAGE}" \
        build \
        --definition-file "${DEFINITION_FILE}" \
        --config-dir /eib \
        --build-dir /build
    
    if [ $? -eq 0 ]; then
        log "✓ Image built successfully"
    else
        error "Image build failed"
    fi
}

# Post-processing
post_process() {
    log "Post-processing image..."
    
    # Find generated image (EIB may create it in config dir or build dir)
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
    
    log "✓ Image generated: $iso_file"
    log "✓ Checksum: $checksum_file"
    
    # Display information
    echo ""
    echo "========================================="
    echo " Build completed successfully!"
    echo "========================================="
    echo ""
    echo "ISO Image: $iso_file"
    echo "Size: $(du -h "$iso_file" | cut -f1)"
    echo "SHA256: $(cut -d' ' -f1 "$checksum_file")"
    echo ""
    echo "Next steps:"
    echo "1. Write the ISO to USB drive (SanDisk Extreme 128Go):"
    echo "   ./write-iso-to-usb.sh $iso_file"
    echo "   Or use it in a VM"
    echo "2. Boot the target machine from the ISO"
    echo "3. The installation will be fully unattended"
    echo "4. On first boot, the node will automatically register with Rancher"
    echo ""
}

# Main
main() {
    echo ""
    echo "╔══════════════════════════════════════════╗"
    echo "║  SUSE Edge 3.4 - EIB Image Builder      ║"
    echo "║  Rancher Fleet Registration             ║"
    echo "╚══════════════════════════════════════════╝"
    echo ""
    
    check_prerequisites
    prepare_output
    build_image
    post_process
}

# Execution
main "$@"


#!/bin/bash
# Script to build EIB ISOs for 2 sites (Site A and Site B)
# This script requires elemental/elemental_config-site-a.yaml and elemental/elemental_config-site-b.yaml
# These files must be created from Rancher Registration Endpoints first
#
# Usage: ./build-isos-2-sites.sh

set -e

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; exit 1; }

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
ELEMENTAL_DIR="${PROJECT_ROOT}/elemental"
OUTPUT_DIR="${PROJECT_ROOT}/output"

CONFIG_A="${ELEMENTAL_DIR}/elemental_config-site-a.yaml"
CONFIG_B="${ELEMENTAL_DIR}/elemental_config-site-b.yaml"
CONFIG_CURRENT="${ELEMENTAL_DIR}/elemental_config.yaml"
CONFIG_BACKUP="${ELEMENTAL_DIR}/elemental_config.yaml.backup"

ISO_A="${OUTPUT_DIR}/vm-rancher-fleet-scale-site-a.iso"
ISO_B="${OUTPUT_DIR}/vm-rancher-fleet-scale-site-b.iso"

log_info "Building EIB ISOs for 2 Sites"
echo ""

# Check if config files exist BEFORE moving anything
if [ ! -f "$CONFIG_A" ]; then
    log_error "Configuration file not found: $CONFIG_A"
    log_info "Please create this file from Rancher Registration Endpoint 'site-a-registration'"
    log_info "See BUILD-ISOS-2-SITES.md for instructions"
    exit 1
fi

if [ ! -f "$CONFIG_B" ]; then
    log_error "Configuration file not found: $CONFIG_B"
    log_info "Please create this file from Rancher Registration Endpoint 'site-b-registration'"
    log_info "See BUILD-ISOS-2-SITES.md for instructions"
    exit 1
fi

# Create temp directory for other config files (EIB requires only one file in elemental/)
TEMP_DIR=$(mktemp -d)
log_info "Temporary directory for config files: $TEMP_DIR"

# Store paths to configs before moving them
CONFIG_A_TEMP="$TEMP_DIR/elemental_config-site-a.yaml"
CONFIG_B_TEMP="$TEMP_DIR/elemental_config-site-b.yaml"

# Move ALL config files to temp directory (EIB requires only one file)
log_info "Moving all config files temporarily (EIB requires only one file)"
if [ -f "$CONFIG_CURRENT" ]; then
    mv "$CONFIG_CURRENT" "$TEMP_DIR/elemental_config.yaml.backup" 2>/dev/null || true
fi
# Move Site A and Site B configs to temp (we'll restore them later)
if [ -f "$CONFIG_A" ]; then
    mv "$CONFIG_A" "$CONFIG_A_TEMP" 2>/dev/null || true
fi
if [ -f "$CONFIG_B" ]; then
    mv "$CONFIG_B" "$CONFIG_B_TEMP" 2>/dev/null || true
fi

# Build Site A ISO
echo "=========================================="
log_info "Building ISO for Site A"
echo "=========================================="
log_info "Using config from: $CONFIG_A_TEMP"
cp "$CONFIG_A_TEMP" "$CONFIG_CURRENT"

cd "$PROJECT_ROOT"
log_info "Running EIB build..."
./build-eib-image.sh

# Find ISO (may be in output/ or parent directory)
ISO_BUILT=""
if [ -f "${OUTPUT_DIR}/vm-rancher-fleet-scale.iso" ]; then
    ISO_BUILT="${OUTPUT_DIR}/vm-rancher-fleet-scale.iso"
elif [ -f "${EIB_DIR}/vm-rancher-fleet-scale.iso" ]; then
    ISO_BUILT="${EIB_DIR}/vm-rancher-fleet-scale.iso"
fi

if [ -n "$ISO_BUILT" ]; then
    mv "$ISO_BUILT" "$ISO_A"
    log_info "OK: Site A ISO created: $ISO_A"
    ls -lh "$ISO_A"
else
    log_error "ISO build failed for Site A - ISO not found"
    exit 1
fi

echo ""

# Build Site B ISO
echo "=========================================="
log_info "Building ISO for Site B"
echo "=========================================="
log_info "Using config from: $CONFIG_B_TEMP"
# Remove Site A config and use Site B
rm -f "$CONFIG_CURRENT"
cp "$CONFIG_B_TEMP" "$CONFIG_CURRENT"

cd "$PROJECT_ROOT"
log_info "Running EIB build..."
./build-eib-image.sh

# Find ISO (may be in output/ or parent directory)
ISO_BUILT=""
if [ -f "${OUTPUT_DIR}/vm-rancher-fleet-scale.iso" ]; then
    ISO_BUILT="${OUTPUT_DIR}/vm-rancher-fleet-scale.iso"
elif [ -f "${EIB_DIR}/vm-rancher-fleet-scale.iso" ]; then
    ISO_BUILT="${EIB_DIR}/vm-rancher-fleet-scale.iso"
fi

if [ -n "$ISO_BUILT" ]; then
    mv "$ISO_BUILT" "$ISO_B"
    log_info "OK: Site B ISO created: $ISO_B"
    ls -lh "$ISO_B"
else
    log_error "ISO build failed for Site B - ISO not found"
    exit 1
fi

# Restore original config and other files
log_info "Restoring original files"
rm -f "$CONFIG_CURRENT"
if [ -f "$TEMP_DIR/elemental_config.yaml.backup" ]; then
    mv "$TEMP_DIR/elemental_config.yaml.backup" "$CONFIG_CURRENT" 2>/dev/null || true
fi
if [ -f "$CONFIG_A_TEMP" ]; then
    mv "$CONFIG_A_TEMP" "$CONFIG_A" 2>/dev/null || true
fi
if [ -f "$CONFIG_B_TEMP" ]; then
    mv "$CONFIG_B_TEMP" "$CONFIG_B" 2>/dev/null || true
fi
rm -rf "$TEMP_DIR"

echo ""
echo "=========================================="
log_info "All ISOs built successfully"
echo "=========================================="
echo ""
echo "ISOs created:"
ls -lh "$ISO_A" "$ISO_B"
echo ""
log_info "You can now create VMs using:"
echo "  cd test-10-VMs"
echo "  ./create-vms-2-sites.sh --parallel"


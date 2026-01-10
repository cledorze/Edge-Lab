#!/bin/bash
# Script to build EIB ISOs for 2 sites (Site A and Site B)
#
# PREREQUISITES:
#   - generated/elemental/elemental_config-site-a.yaml (REQUIRED)
#   - generated/elemental/elemental_config-site-b.yaml (REQUIRED)
#   These files are created by 2-create-registration-endpoints.sh (Step 2)
#   They contain the registration endpoints and CA certificates needed for ISO build
#
# Usage: ./3-build-isos-2-sites.sh
#
# This script:
#   1. Verifies both config files exist
#   2. Builds ISO for Site A using elemental_config-site-a.yaml
#   3. Builds ISO for Site B using elemental_config-site-b.yaml
#   4. Outputs ISOs to output/vm-rancher-fleet-scale-site-a.iso and output/vm-rancher-fleet-scale-site-b.iso

set -e

KUBECONFIG_PATH="/home/tofix/LAB/AI/Edge-3.4/rancher-kubeconfig.yaml"
export KUBECONFIG="$KUBECONFIG_PATH"

# Trap to ensure cleanup happens even on error
# Note: Files are COPIED (not moved) so originals remain safe
cleanup() {
    local exit_code=$?
    
    # Restore EIB elemental directory files if backed up
    if [ -n "$EIB_ELEMENTAL_BACKUP_DIR" ] && [ -d "$EIB_ELEMENTAL_BACKUP_DIR" ] && [ -n "$(ls -A "$EIB_ELEMENTAL_BACKUP_DIR" 2>/dev/null)" ]; then
        log_info "Restoring EIB elemental directory files..."
        if [ -n "$EIB_ELEMENTAL_DIR" ] && [ -d "$EIB_ELEMENTAL_DIR" ]; then
            mv "$EIB_ELEMENTAL_BACKUP_DIR"/* "$EIB_ELEMENTAL_DIR/" 2>/dev/null || true
        fi
    fi
    
    if [ -n "$TEMP_DIR" ] && [ -d "$TEMP_DIR" ]; then
        log_info "Cleaning up temporary files..."
        # Remove temporary directory (originals are safe since we copied, not moved)
        rm -rf "$TEMP_DIR"
    fi
    if [ $exit_code -ne 0 ]; then
        log_error "Script failed with exit code $exit_code"
    fi
}

trap cleanup EXIT INT TERM

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
ELEMENTAL_DIR="${PROJECT_ROOT}/generated/elemental"
OUTPUT_DIR="${PROJECT_ROOT}/output"

# EIB directory configuration (local EIB directory)
EIB_DIR="${PROJECT_ROOT}/EIB"
EIB_BUILD_SCRIPT="${EIB_DIR}/build-eib-image.sh"
EIB_DEFINITION_FILE="${EIB_DIR}/iso-VM-definition.yaml"

CONFIG_A="${ELEMENTAL_DIR}/elemental_config-site-a.yaml"
CONFIG_B="${ELEMENTAL_DIR}/elemental_config-site-b.yaml"
CONFIG_CURRENT="${ELEMENTAL_DIR}/elemental_config.yaml"
CONFIG_BACKUP="${ELEMENTAL_DIR}/elemental_config.yaml.backup"

ISO_A="${OUTPUT_DIR}/vm-rancher-fleet-scale-site-a.iso"
ISO_B="${OUTPUT_DIR}/vm-rancher-fleet-scale-site-b.iso"

log_info "Building EIB ISOs for 2 Sites"
echo ""
log_info "Using Elemental config files:"
log_info "  Site A: $CONFIG_A"
log_info "  Site B: $CONFIG_B"
echo ""

# Check and setup EIB directory
setup_eib() {
    log_info "Checking EIB directory..."
    
    # Check if EIB directory exists
    if [ ! -d "$EIB_DIR" ]; then
        log_error "EIB directory not found at: $EIB_DIR"
        log_info "Expected location: ${PROJECT_ROOT}/EIB"
        log_info "The EIB directory should contain build-eib-image.sh, iso-VM-definition.yaml, and other EIB files"
        exit 1
    fi
    
    # Check if build script exists
    if [ ! -f "$EIB_BUILD_SCRIPT" ]; then
        log_error "build-eib-image.sh not found at: $EIB_BUILD_SCRIPT"
        log_info "Expected location: ${EIB_DIR}/build-eib-image.sh"
        exit 1
    fi
    
    # Check if definition file exists
    if [ ! -f "$EIB_DEFINITION_FILE" ]; then
        log_error "iso-VM-definition.yaml not found at: $EIB_DEFINITION_FILE"
        log_info "Expected location: ${EIB_DIR}/iso-VM-definition.yaml"
        exit 1
    fi
    
    # Check prerequisites (podman)
    if ! command -v podman &> /dev/null; then
        log_error "podman is not installed"
        log_info "Install with: sudo zypper install podman"
        exit 1
    fi
    
    log_info "✓ EIB directory ready"
}

# Setup EIB build environment
setup_eib

# Create output directory if it doesn't exist
mkdir -p "$OUTPUT_DIR"

# Check if config files exist BEFORE moving anything
# These files are REQUIRED for building the ISOs - they contain the registration endpoints
# and are created by 2-create-registration-endpoints.sh (Step 2)
if [ ! -f "$CONFIG_A" ]; then
    log_error "Configuration file not found: $CONFIG_A"
    log_error "This file is REQUIRED for building Site A ISO"
    log_info "Please run Step 2 first to create registration endpoints and download config files:"
    log_info "  export KUBECONFIG=/home/tofix/LAB/AI/Edge-3.4/rancher-kubeconfig.yaml"
    log_info "  ./2-create-registration-endpoints.sh"
    log_info "Or see DEPLOYMENT-GUIDE.md Step 2 for manual instructions"
    exit 1
fi

if [ ! -f "$CONFIG_B" ]; then
    log_error "Configuration file not found: $CONFIG_B"
    log_error "This file is REQUIRED for building Site B ISO"
    log_info "Please run Step 2 first to create registration endpoints and download config files:"
    log_info "  export KUBECONFIG=/home/tofix/LAB/AI/Edge-3.4/rancher-kubeconfig.yaml"
    log_info "  ./2-create-registration-endpoints.sh"
    log_info "Or see DEPLOYMENT-GUIDE.md Step 2 for manual instructions"
    exit 1
fi

# Create temp directory for other config files (EIB requires only one file in generated/elemental/)
TEMP_DIR=$(mktemp -d)
log_info "Temporary directory for config files: $TEMP_DIR"

# Initialize EIB elemental directory variables (needed for cleanup)
EIB_ELEMENTAL_DIR="${EIB_DIR}/elemental"
EIB_ELEMENTAL_BACKUP_DIR="${TEMP_DIR}/eib_elemental_backup"

# Store paths to configs before moving them
CONFIG_A_TEMP="$TEMP_DIR/elemental_config-site-a.yaml"
CONFIG_B_TEMP="$TEMP_DIR/elemental_config-site-b.yaml"

# Copy config files to temp directory (EIB requires only one file)
# We COPY instead of MOVE to prevent data loss if script fails
log_info "Copying config files to temporary location (EIB requires only one file)"
if [ -f "$CONFIG_CURRENT" ]; then
    cp "$CONFIG_CURRENT" "$TEMP_DIR/elemental_config.yaml.backup" 2>/dev/null || true
fi
# Copy Site A and Site B configs to temp (we'll restore originals later)
if [ -f "$CONFIG_A" ]; then
    cp "$CONFIG_A" "$CONFIG_A_TEMP" 2>/dev/null || true
fi
if [ -f "$CONFIG_B" ]; then
    cp "$CONFIG_B" "$CONFIG_B_TEMP" 2>/dev/null || true
fi

# Build Site A ISO
echo "=========================================="
log_info "Building ISO for Site A"
echo "=========================================="
log_info "Using Elemental config: $CONFIG_A"
log_info "This config contains the registration endpoint and CA certificate for Site A"
cp "$CONFIG_A_TEMP" "$CONFIG_CURRENT"

# Change to EIB directory for build
cd "$EIB_DIR"
log_info "Running EIB build from: $(pwd)"
log_info "Using build script: $EIB_BUILD_SCRIPT"

# Prepare EIB elemental directory (EIB requires ONLY elemental_config.yaml)
mkdir -p "$EIB_ELEMENTAL_DIR"

# Backup existing files in EIB elemental directory (if any)
mkdir -p "$EIB_ELEMENTAL_BACKUP_DIR"
if [ -d "$EIB_ELEMENTAL_DIR" ]; then
    # Move all existing files to backup (except .gitkeep if it exists)
    find "$EIB_ELEMENTAL_DIR" -maxdepth 1 -type f ! -name ".gitkeep" -exec mv {} "$EIB_ELEMENTAL_BACKUP_DIR/" \; 2>/dev/null || true
fi

# Copy the current config as elemental_config.yaml (EIB requires this exact name)
cp "$CONFIG_CURRENT" "${EIB_ELEMENTAL_DIR}/elemental_config.yaml"

# Run the build script
"$EIB_BUILD_SCRIPT"

# Find ISO (may be in EIB output/ or EIB config directory)
EIB_OUTPUT_DIR="${EIB_DIR}/output"
ISO_BUILT=""
if [ -f "${EIB_OUTPUT_DIR}/vm-rancher-fleet-scale.iso" ]; then
    ISO_BUILT="${EIB_OUTPUT_DIR}/vm-rancher-fleet-scale.iso"
elif [ -f "${EIB_DIR}/vm-rancher-fleet-scale.iso" ]; then
    ISO_BUILT="${EIB_DIR}/vm-rancher-fleet-scale.iso"
elif [ -f "${OUTPUT_DIR}/vm-rancher-fleet-scale.iso" ]; then
    ISO_BUILT="${OUTPUT_DIR}/vm-rancher-fleet-scale.iso"
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
log_info "Using Elemental config: $CONFIG_B"
log_info "This config contains the registration endpoint and CA certificate for Site B"
# Remove Site A config and use Site B
rm -f "$CONFIG_CURRENT"
cp "$CONFIG_B_TEMP" "$CONFIG_CURRENT"

# Change to EIB directory for build
cd "$EIB_DIR"
log_info "Running EIB build from: $(pwd)"
log_info "Using build script: $EIB_BUILD_SCRIPT"

# Prepare EIB elemental directory (EIB requires ONLY elemental_config.yaml)
mkdir -p "$EIB_ELEMENTAL_DIR"

# Backup existing files in EIB elemental directory (if any)
mkdir -p "$EIB_ELEMENTAL_BACKUP_DIR"
if [ -d "$EIB_ELEMENTAL_DIR" ]; then
    # Move all existing files to backup (except .gitkeep if it exists)
    find "$EIB_ELEMENTAL_DIR" -maxdepth 1 -type f ! -name ".gitkeep" -exec mv {} "$EIB_ELEMENTAL_BACKUP_DIR/" \; 2>/dev/null || true
fi

# Copy the current config as elemental_config.yaml (EIB requires this exact name)
cp "$CONFIG_CURRENT" "${EIB_ELEMENTAL_DIR}/elemental_config.yaml"

# Run the build script
"$EIB_BUILD_SCRIPT"

# Find ISO (may be in EIB output/ or EIB config directory)
EIB_OUTPUT_DIR="${EIB_DIR}/output"
ISO_BUILT=""
if [ -f "${EIB_OUTPUT_DIR}/vm-rancher-fleet-scale.iso" ]; then
    ISO_BUILT="${EIB_OUTPUT_DIR}/vm-rancher-fleet-scale.iso"
elif [ -f "${EIB_DIR}/vm-rancher-fleet-scale.iso" ]; then
    ISO_BUILT="${EIB_DIR}/vm-rancher-fleet-scale.iso"
elif [ -f "${OUTPUT_DIR}/vm-rancher-fleet-scale.iso" ]; then
    ISO_BUILT="${OUTPUT_DIR}/vm-rancher-fleet-scale.iso"
fi

if [ -n "$ISO_BUILT" ]; then
    mv "$ISO_BUILT" "$ISO_B"
    log_info "OK: Site B ISO created: $ISO_B"
    ls -lh "$ISO_B"
else
    log_error "ISO build failed for Site B - ISO not found"
    exit 1
fi

# Restore EIB elemental directory files (if backed up)
if [ -d "$EIB_ELEMENTAL_BACKUP_DIR" ] && [ -n "$(ls -A "$EIB_ELEMENTAL_BACKUP_DIR" 2>/dev/null)" ]; then
    log_info "Restoring EIB elemental directory files"
    mv "$EIB_ELEMENTAL_BACKUP_DIR"/* "$EIB_ELEMENTAL_DIR/" 2>/dev/null || true
fi

# Clean up temporary files (originals are already in place since we copied, not moved)
log_info "Cleaning up temporary files"
rm -f "$CONFIG_CURRENT"
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


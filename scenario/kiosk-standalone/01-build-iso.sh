#!/bin/bash
# Kiosk Standalone K3s - Build ISO
# Step 1: Build the EIB image with K3s and kiosk workload
#
# This script builds a standalone K3s image with Firefox kiosk pre-deployed
# No Rancher or Elemental registration required

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="${SCRIPT_DIR}/../.."
EIB_DIR="${PROJECT_ROOT}/EIB-kiosk-standalone"

echo ""
echo "╔══════════════════════════════════════════════════════════════╗"
echo "║       Kiosk Standalone K3s - Step 1: Build ISO              ║"
echo "╚══════════════════════════════════════════════════════════════╝"
echo ""

# Verify EIB directory exists
if [ ! -d "$EIB_DIR" ]; then
    echo "ERROR: EIB directory not found: $EIB_DIR"
    exit 1
fi

# Run the build
cd "$EIB_DIR"
./build-eib-image.sh

echo ""
echo "Build complete. Check ${EIB_DIR}/ for the generated ISO."
echo ""
echo "Next step: ./02-create-vm.sh (optional - to test in a VM)"

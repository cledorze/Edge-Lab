#!/bin/bash
set -euo pipefail
echo "Enabling ASCII boot splash..."
systemctl enable bootsplash.service
echo "Boot splash enabled"

# EIB (Edge Image Builder) Configuration

This directory contains all files and directories needed to build EIB images for SUSE Edge 3.4.

## Directory Structure

```
EIB/
├── build-eib-image.sh          # Main build script
├── iso-VM-definition.yaml      # EIB image definition file
├── iso-definition.yaml         # Alternative definition file
├── base-images/                # Base ISO images (SL-Micro)
├── elemental/                  # Elemental configuration files
├── custom/                     # Custom scripts
│   └── scripts/
│       ├── 60-set-hostname.sh
│       └── 70-configure-network.sh
├── os-files/                   # OS configuration files
│   ├── etc/                    # System configuration
│   ├── home/                   # User home directories
│   ├── root/                   # Root directory files
│   └── usr/                    # User binaries and scripts
└── output/                     # Generated ISO files (created during build)
```

## Prerequisites

1. **Podman**: Required to run the EIB container
   ```bash
   sudo zypper install podman
   ```

2. **Base ISO Image**: Download SUSE Linux Micro 6.1 Base RT SelfInstall ISO
   - File: `SL-Micro.x86_64-6.1-Base-RT-SelfInstall-GM.install.iso`
   - Place it in: `EIB/base-images/`
   - Download from: https://www.suse.com/download/sle-micro/

3. **Elemental Config**: Elemental configuration files are managed in `generated/elemental/`
   - The build script will copy the appropriate config to `EIB/elemental/elemental_config.yaml` during build

## Usage

The EIB build is invoked by `scenario/3-build-isos-2-sites.sh`, which:
1. Copies the appropriate elemental config to `EIB/elemental/elemental_config.yaml`
2. Changes to the `EIB/` directory
3. Runs `build-eib-image.sh`
4. Finds the generated ISO and moves it to `output/`

## Build Process

The `build-eib-image.sh` script:
1. Checks prerequisites (podman, base image, definition file)
2. Creates output directory
3. Runs EIB container with podman
4. Generates ISO image
5. Creates SHA256 checksum

## Files Reference

This directory structure is based on:
- SUSE Edge 3.4 EIB documentation
- EIB-demo repository: `http://gitea.cledorze.lan/nostromo/EIB-demo/src/branch/master/scale-out-eib-elemental`

## Notes

- The `elemental/` directory in this EIB folder contains example configs
- Actual configs used for builds come from `generated/elemental/` in the project root
- The `output/` directory is created automatically during build
- Base ISO images are not included in git (add to `.gitignore`)

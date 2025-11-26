#!/bin/bash
# Create Registration Endpoints in Rancher and download Elemental config files
# This script follows Step 2 of DEPLOYMENT-GUIDE.md
#
# What it does:
# 1. Applies MachineRegistrations for site-a and site-b
# 2. Waits for registration URLs to be generated
# 3. Downloads elemental_config.yaml from each endpoint
# 4. Saves them as generated/elemental/elemental_config-site-a.yaml and generated/elemental/elemental_config-site-b.yaml
#
# Usage: ./create-registration-endpoints.sh

set -e

KUBECONFIG_FILE="/etc/rancher/rke2/rke2.yaml"
if [ ! -f "$KUBECONFIG_FILE" ]; then
    echo "WARNING:  Kubeconfig not found at $KUBECONFIG_FILE"
    echo "Please set KUBECONFIG environment variable"
    exit 1
fi

export KUBECONFIG="$KUBECONFIG_FILE"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
YAML_DIR="$SCRIPT_DIR/yaml"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
ELEMENTAL_DIR="$PROJECT_ROOT/generated/elemental"

echo "=========================================="
echo "Create Registration Endpoints"
echo "Step 2 of DEPLOYMENT-GUIDE.md"
echo "=========================================="
echo ""

# Check that kubectl is available
if ! command -v kubectl &> /dev/null; then
    echo "ERROR: kubectl is not available"
    echo "   Configure KUBECONFIG: export KUBECONFIG=/etc/rancher/rke2/rke2.yaml"
    exit 1
fi

# Check cluster connection
if ! kubectl cluster-info &> /dev/null; then
    echo "ERROR: Cannot connect to Kubernetes cluster"
    exit 1
fi

# Verify that YAML files exist
if [ ! -f "$YAML_DIR/site-a-registration.yaml" ]; then
    echo "ERROR: site-a-registration.yaml not found in $YAML_DIR"
    exit 1
fi

if [ ! -f "$YAML_DIR/site-b-registration.yaml" ]; then
    echo "ERROR: site-b-registration.yaml not found in $YAML_DIR"
    exit 1
fi

echo "=== Step 1: Applying MachineRegistrations ==="
echo ""

echo "Applying site-a-registration..."
kubectl apply -f "$YAML_DIR/site-a-registration.yaml"
echo "OK: site-a-registration applied"

echo ""
echo "Applying site-b-registration..."
kubectl apply -f "$YAML_DIR/site-b-registration.yaml"
echo "OK: site-b-registration applied"

echo ""
echo "=== Step 2: Waiting for registration URLs ==="
echo ""

# Wait for registration URLs to be generated (max 30 seconds)
MAX_WAIT=30
WAIT_COUNT=0
SITE_A_URL=""
SITE_B_URL=""

while [ $WAIT_COUNT -lt $MAX_WAIT ]; do
    SITE_A_URL=$(kubectl get machineregistration site-a-registration -n fleet-default -o jsonpath='{.status.registrationURL}' 2>/dev/null || echo "")
    SITE_B_URL=$(kubectl get machineregistration site-b-registration -n fleet-default -o jsonpath='{.status.registrationURL}' 2>/dev/null || echo "")
    
    if [ -n "$SITE_A_URL" ] && [ -n "$SITE_B_URL" ]; then
        break
    fi
    
    echo "  Waiting for registration URLs... ($WAIT_COUNT/$MAX_WAIT seconds)"
    sleep 2
    WAIT_COUNT=$((WAIT_COUNT + 2))
done

if [ -z "$SITE_A_URL" ] || [ -z "$SITE_B_URL" ]; then
    echo "WARNING:  Registration URLs not available after $MAX_WAIT seconds"
    echo "   Please check the MachineRegistrations manually:"
    echo "   kubectl get machineregistration -n fleet-default"
    exit 1
fi

echo "OK: Registration URLs generated:"
echo "   Site A: $SITE_A_URL"
echo "   Site B: $SITE_B_URL"

echo ""
echo "=== Step 3: Downloading Elemental config files ==="
echo ""

# Create elemental directory if it doesn't exist
mkdir -p "$ELEMENTAL_DIR"

# Download elemental_config.yaml from each endpoint
# The registration URL itself returns the YAML config when accessed with Accept: application/yaml header

echo "Downloading elemental_config for Site A..."

SITE_A_DOWNLOADED=false
# The registration URL itself returns the YAML config when accessed with proper headers
if curl -s -f -k -H "Accept: application/yaml" -o "$ELEMENTAL_DIR/elemental_config-site-a.yaml" "$SITE_A_URL" 2>/dev/null; then
    FILE_SIZE=$(stat -f%z "$ELEMENTAL_DIR/elemental_config-site-a.yaml" 2>/dev/null || stat -c%s "$ELEMENTAL_DIR/elemental_config-site-a.yaml" 2>/dev/null || echo "0")
    if [ "$FILE_SIZE" -gt 50 ]; then
        echo "OK: Downloaded: $ELEMENTAL_DIR/elemental_config-site-a.yaml ($FILE_SIZE bytes)"
        SITE_A_DOWNLOADED=true
    else
        echo "WARNING:  Downloaded file seems too small ($FILE_SIZE bytes)"
        echo "   Please download manually from Rancher UI:"
        echo "   1. Go to Elemental → Registration Endpoints"
        echo "   2. Click on 'site-a-registration'"
        echo "   3. Download 'elemental_config.yaml'"
        echo "   4. Save as: $ELEMENTAL_DIR/elemental_config-site-a.yaml"
        echo "   Registration URL: $SITE_A_URL"
        rm -f "$ELEMENTAL_DIR/elemental_config-site-a.yaml"
    fi
else
    echo "WARNING:  Could not download Site A config automatically"
    echo "   Please download manually from Rancher UI:"
    echo "   1. Go to Elemental → Registration Endpoints"
    echo "   2. Click on 'site-a-registration'"
    echo "   3. Download 'elemental_config.yaml'"
    echo "   4. Save as: $ELEMENTAL_DIR/elemental_config-site-a.yaml"
    echo "   Registration URL: $SITE_A_URL"
fi

echo ""
echo "Downloading elemental_config for Site B..."

SITE_B_DOWNLOADED=false
# The registration URL itself returns the YAML config when accessed with proper headers
if curl -s -f -k -H "Accept: application/yaml" -o "$ELEMENTAL_DIR/elemental_config-site-b.yaml" "$SITE_B_URL" 2>/dev/null; then
    FILE_SIZE=$(stat -f%z "$ELEMENTAL_DIR/elemental_config-site-b.yaml" 2>/dev/null || stat -c%s "$ELEMENTAL_DIR/elemental_config-site-b.yaml" 2>/dev/null || echo "0")
    if [ "$FILE_SIZE" -gt 50 ]; then
        echo "OK: Downloaded: $ELEMENTAL_DIR/elemental_config-site-b.yaml ($FILE_SIZE bytes)"
        SITE_B_DOWNLOADED=true
    else
        echo "WARNING:  Downloaded file seems too small ($FILE_SIZE bytes)"
        echo "   Please download manually from Rancher UI:"
        echo "   1. Go to Elemental → Registration Endpoints"
        echo "   2. Click on 'site-b-registration'"
        echo "   3. Download 'elemental_config.yaml'"
        echo "   4. Save as: $ELEMENTAL_DIR/elemental_config-site-b.yaml"
        echo "   Registration URL: $SITE_B_URL"
        rm -f "$ELEMENTAL_DIR/elemental_config-site-b.yaml"
    fi
else
    echo "WARNING:  Could not download Site B config automatically"
    echo "   Please download manually from Rancher UI:"
    echo "   1. Go to Elemental → Registration Endpoints"
    echo "   2. Click on 'site-b-registration'"
    echo "   3. Download 'elemental_config.yaml'"
    echo "   4. Save as: $ELEMENTAL_DIR/elemental_config-site-b.yaml"
    echo "   Registration URL: $SITE_B_URL"
fi

echo ""
echo "=== Step 4: Verification ==="
echo ""

# Verify files were downloaded
if [ -f "$ELEMENTAL_DIR/elemental_config-site-a.yaml" ]; then
    FILE_SIZE=$(stat -f%z "$ELEMENTAL_DIR/elemental_config-site-a.yaml" 2>/dev/null || stat -c%s "$ELEMENTAL_DIR/elemental_config-site-a.yaml" 2>/dev/null || echo "0")
    if [ "$FILE_SIZE" -gt 50 ]; then
        echo "OK: Site A config file exists and has content ($FILE_SIZE bytes)"
    else
        echo "WARNING:  Site A config file exists but seems too small ($FILE_SIZE bytes)"
        SITE_A_DOWNLOADED=false
    fi
else
    echo "ERROR: Site A config file not found"
    SITE_A_DOWNLOADED=false
fi

if [ -f "$ELEMENTAL_DIR/elemental_config-site-b.yaml" ]; then
    FILE_SIZE=$(stat -f%z "$ELEMENTAL_DIR/elemental_config-site-b.yaml" 2>/dev/null || stat -c%s "$ELEMENTAL_DIR/elemental_config-site-b.yaml" 2>/dev/null || echo "0")
    if [ "$FILE_SIZE" -gt 50 ]; then
        echo "OK: Site B config file exists and has content ($FILE_SIZE bytes)"
    else
        echo "WARNING:  Site B config file exists but seems too small ($FILE_SIZE bytes)"
        SITE_B_DOWNLOADED=false
    fi
else
    echo "ERROR: Site B config file not found"
    SITE_B_DOWNLOADED=false
fi

echo ""
echo "=== Step 5: Committing to Git ==="
echo ""

# Commit and push downloaded config files to git
if [ "$SITE_A_DOWNLOADED" = true ] || [ "$SITE_B_DOWNLOADED" = true ]; then
    if command -v git &> /dev/null && [ -d "$PROJECT_ROOT/.git" ]; then
        cd "$PROJECT_ROOT"
        
        # Check if there are changes to commit
        FILES_TO_COMMIT=""
        if [ "$SITE_A_DOWNLOADED" = true ] && [ -f "$ELEMENTAL_DIR/elemental_config-site-a.yaml" ]; then
            FILES_TO_COMMIT="$FILES_TO_COMMIT $ELEMENTAL_DIR/elemental_config-site-a.yaml"
        fi
        if [ "$SITE_B_DOWNLOADED" = true ] && [ -f "$ELEMENTAL_DIR/elemental_config-site-b.yaml" ]; then
            FILES_TO_COMMIT="$FILES_TO_COMMIT $ELEMENTAL_DIR/elemental_config-site-b.yaml"
        fi
        
        if [ -n "$FILES_TO_COMMIT" ]; then
            # Check if files have changes
            if git status --porcelain $FILES_TO_COMMIT | grep -q .; then
                echo "Committing elemental config files to git..."
                git add $FILES_TO_COMMIT 2>/dev/null || true
            
                COMMIT_MSG="Update elemental config files from registration endpoints"
                if [ "$SITE_A_DOWNLOADED" = true ] && [ "$SITE_B_DOWNLOADED" = true ]; then
                    COMMIT_MSG="$COMMIT_MSG (Site A and Site B)"
                elif [ "$SITE_A_DOWNLOADED" = true ]; then
                    COMMIT_MSG="$COMMIT_MSG (Site A)"
                else
                    COMMIT_MSG="$COMMIT_MSG (Site B)"
                fi
                
                if git commit -m "$COMMIT_MSG" 2>/dev/null; then
                    echo "OK: Committed elemental config files"
                    
                    # Try to push (may fail if remote is not configured or no network)
                    if git push origin main 2>/dev/null; then
                        echo "OK: Pushed elemental config files to remote repository"
                    else
                        echo "WARNING:  Could not push to remote repository (may need manual push)"
                        echo "   Run: cd $PROJECT_ROOT && git push origin main"
                    fi
                else
                    echo "WARNING:  No changes to commit (files may already be up to date)"
                fi
            else
                echo "OK: No changes to commit (files already up to date)"
            fi
        else
            echo "WARNING:  No files to commit (download may have failed)"
        fi
    else
        echo "WARNING:  Git not available or not in a git repository, skipping commit"
    fi
else
    echo "WARNING:  No config files were downloaded successfully, skipping git commit"
fi

echo ""
echo "=========================================="
echo "OK: Registration Endpoints Setup Complete"
echo "=========================================="
echo ""

echo "Summary:"
echo "  - MachineRegistrations applied: OK:"
echo "  - Registration URLs:"
echo "    Site A: $SITE_A_URL"
echo "    Site B: $SITE_B_URL"
echo "  - Config files:"
if [ -f "$ELEMENTAL_DIR/elemental_config-site-a.yaml" ]; then
    echo "    OK: $ELEMENTAL_DIR/elemental_config-site-a.yaml"
else
    echo "    ERROR: $ELEMENTAL_DIR/elemental_config-site-a.yaml (not downloaded)"
fi
if [ -f "$ELEMENTAL_DIR/elemental_config-site-b.yaml" ]; then
    echo "    OK: $ELEMENTAL_DIR/elemental_config-site-b.yaml"
else
    echo "    ERROR: $ELEMENTAL_DIR/elemental_config-site-b.yaml (not downloaded)"
fi

echo ""
echo "Next steps:"
echo "  1. If config files were not downloaded automatically, download them manually from Rancher UI:"
echo "     - Go to Elemental → Registration Endpoints"
echo "     - Click on each endpoint and download elemental_config.yaml"
echo "     - Save as: $ELEMENTAL_DIR/elemental_config-site-a.yaml"
echo "     - Save as: $ELEMENTAL_DIR/elemental_config-site-b.yaml"
echo ""
echo "  2. Proceed with Step 2 of DEPLOYMENT-GUIDE.md: Build ISOs"
echo "     cd $PROJECT_ROOT"
echo "     ./build-isos-2-sites.sh"


#!/bin/bash
# Wait for hostname to be set before registering with Elemental
# This ensures that ${Runtime/Hostname} template variable is resolved correctly

set -e

MAX_WAIT=60
WAIT_COUNT=0
DEFAULT_HOSTNAME="slemicro"

echo "Waiting for hostname to be set..."

while [ $WAIT_COUNT -lt $MAX_WAIT ]; do
    CURRENT_HOSTNAME=$(hostname 2>/dev/null || echo "")
    
    # Check if hostname is set and not the default
    if [ -n "$CURRENT_HOSTNAME" ] && [ "$CURRENT_HOSTNAME" != "$DEFAULT_HOSTNAME" ] && [ "$CURRENT_HOSTNAME" != "localhost" ]; then
        echo "Hostname is set to: $CURRENT_HOSTNAME"
        break
    fi
    
    echo "Waiting for hostname... ($WAIT_COUNT/$MAX_WAIT seconds) - current: ${CURRENT_HOSTNAME:-not set}"
    sleep 2
    WAIT_COUNT=$((WAIT_COUNT + 2))
done

if [ $WAIT_COUNT -ge $MAX_WAIT ]; then
    echo "WARNING: Hostname not set after $MAX_WAIT seconds, proceeding anyway"
    echo "Current hostname: $(hostname 2>/dev/null || echo 'not set')"
fi

# Now run the actual registration
echo "Starting Elemental registration..."
exec /usr/sbin/elemental-register --emulate-tpm --debug --config-path /etc/elemental/config.yaml --state-path /etc/elemental/state.yaml --install --no-toolkit


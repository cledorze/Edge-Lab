#!/bin/bash
# Script to update Ingress hostname with Ingress Controller IP
# This script is used by the update-ingress-hostname Job in Fleet workloads
# It automatically detects Traefik LoadBalancer, nginx LoadBalancer, or falls back to node IP

set -e

INGRESS_NAME="${INGRESS_NAME:-demo-workload-site-a}"
NAMESPACE="${NAMESPACE:-demo-workload-site-a}"
HOSTNAME_PREFIX="${HOSTNAME_PREFIX:-demo-workload-site-a}"

echo "=== Updating Ingress hostname with Ingress Controller IP ==="
echo "Ingress: $INGRESS_NAME"
echo "Namespace: $NAMESPACE"
echo "Hostname prefix: $HOSTNAME_PREFIX"
echo ""

# Try to detect Ingress Controller type and get IP
MAX_WAIT=120
WAITED=0
INGRESS_IP=""

echo "Detecting Ingress Controller..."

# First, try Traefik LoadBalancer (for Traefik with MetalLB)
if kubectl get svc traefik -n kube-system &>/dev/null; then
  echo "Found Traefik service, checking for LoadBalancer IP..."
  while [ $WAITED -lt $MAX_WAIT ]; do
    INGRESS_IP=$(kubectl get svc traefik -n kube-system -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || echo "")
    
    if [ -n "$INGRESS_IP" ] && [ "$INGRESS_IP" != "null" ] && [ "$INGRESS_IP" != "" ]; then
      echo "OK: Traefik LoadBalancer IP found: $INGRESS_IP"
      break
    fi
    
    sleep 2
    WAITED=$((WAITED + 2))
    echo "Waiting for Traefik LoadBalancer IP... (${WAITED}s/${MAX_WAIT}s)"
  done
fi

# If no Traefik LoadBalancer, try nginx ingress controller LoadBalancer
if [ -z "$INGRESS_IP" ] || [ "$INGRESS_IP" = "null" ] || [ "$INGRESS_IP" = "" ]; then
  echo "Traefik LoadBalancer not found, checking nginx ingress controller..."
  # Try common nginx ingress controller service names
  for svc_name in "rke2-ingress-nginx-controller" "ingress-nginx-controller" "nginx-ingress-controller"; do
    if kubectl get svc "$svc_name" -n kube-system &>/dev/null; then
      echo "Found $svc_name service, checking for LoadBalancer IP..."
      INGRESS_IP=$(kubectl get svc "$svc_name" -n kube-system -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || echo "")
      if [ -n "$INGRESS_IP" ] && [ "$INGRESS_IP" != "null" ] && [ "$INGRESS_IP" != "" ]; then
        echo "OK: nginx LoadBalancer IP found: $INGRESS_IP"
        break
      fi
    fi
  done
fi

# If still no LoadBalancer IP, use node IP (for single-node clusters or NodePort)
if [ -z "$INGRESS_IP" ] || [ "$INGRESS_IP" = "null" ] || [ "$INGRESS_IP" = "" ]; then
  echo "No LoadBalancer IP found, using node IP (single-node cluster)..."
  NODE_NAME=$(kubectl get nodes -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")
  if [ -n "$NODE_NAME" ]; then
    INGRESS_IP=$(kubectl get node "$NODE_NAME" -o jsonpath='{.status.addresses[?(@.type=="InternalIP")].address}' 2>/dev/null || echo "")
    if [ -n "$INGRESS_IP" ]; then
      echo "OK: Using node IP: $INGRESS_IP"
    fi
  fi
fi

if [ -z "$INGRESS_IP" ] || [ "$INGRESS_IP" = "null" ] || [ "$INGRESS_IP" = "" ]; then
  echo "ERROR: Could not determine Ingress Controller IP"
  echo "The Ingress will need to be updated manually"
  exit 1
fi

# Get current Ingress
CURRENT_HOST=$(kubectl get ingress "$INGRESS_NAME" -n "$NAMESPACE" -o jsonpath='{.spec.rules[0].host}' 2>/dev/null || echo "")
NEW_HOST="${HOSTNAME_PREFIX}.${INGRESS_IP}.sslip.io"

if [ "$CURRENT_HOST" = "$NEW_HOST" ]; then
  echo "OK: Ingress hostname is already correct: $NEW_HOST"
  exit 0
fi

# Check if Ingress has any rules
RULE_COUNT=$(kubectl get ingress "$INGRESS_NAME" -n "$NAMESPACE" -o jsonpath='{.spec.rules[*].host}' 2>/dev/null | wc -w || echo "0")

if [ "$RULE_COUNT" = "0" ] || [ -z "$CURRENT_HOST" ]; then
  # Ingress has no rules, add the first rule using kubectl patch with JSON
  echo "Adding Ingress rule with hostname: $NEW_HOST"
  PATCH_JSON="{\"spec\":{\"rules\":[{\"host\":\"$NEW_HOST\",\"http\":{\"paths\":[{\"path\":\"/\",\"pathType\":\"Prefix\",\"backend\":{\"service\":{\"name\":\"$INGRESS_NAME\",\"port\":{\"number\":80}}}}]}}]}}"
  kubectl patch ingress "$INGRESS_NAME" -n "$NAMESPACE" --type merge -p "$PATCH_JSON" && {
    echo "OK: Ingress rule added successfully"
    echo "OK: Access URL: http://$NEW_HOST"
  } || {
    echo "ERROR: Failed to add Ingress rule"
    exit 1
  }
else
  # Ingress has rules, update the first rule's hostname
  echo "Updating Ingress hostname from $CURRENT_HOST to $NEW_HOST"
  PATCH_JSON="[{\"op\": \"replace\", \"path\": \"/spec/rules/0/host\", \"value\": \"$NEW_HOST\"}]"
  kubectl patch ingress "$INGRESS_NAME" -n "$NAMESPACE" --type='json' -p "$PATCH_JSON" && {
    echo "OK: Ingress updated successfully"
    echo "OK: Access URL: http://$NEW_HOST"
  } || {
    echo "ERROR: Failed to update Ingress"
    exit 1
  }
fi

# Verify update
VERIFIED_HOST=$(kubectl get ingress "$INGRESS_NAME" -n "$NAMESPACE" -o jsonpath='{.spec.rules[0].host}' 2>/dev/null || echo "")
if [ "$VERIFIED_HOST" = "$NEW_HOST" ]; then
  echo "OK: Verification successful: Ingress hostname is $VERIFIED_HOST"
else
  echo "⚠ Warning: Verification failed. Expected $NEW_HOST, got $VERIFIED_HOST"
fi


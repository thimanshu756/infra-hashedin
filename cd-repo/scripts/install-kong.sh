#!/bin/bash
# =============================================================================
# Kong Ingress Controller Install Script
# =============================================================================
# Installs Kong with Gateway API support.
# Run this BEFORE applying the api-gateway ArgoCD app.
# Kong CRDs must exist before Gateway/HTTPRoute resources can be created.
#
# Usage: ./install-kong.sh
# =============================================================================

set -euo pipefail

echo "============================================="
echo "  Installing Kong Ingress Controller"
echo "============================================="

# ── 1. Install Gateway API CRDs ──
echo ""
echo "=== Step 1: Installing Gateway API CRDs ==="
kubectl apply -f https://github.com/kubernetes-sigs/gateway-api/releases/download/v1.0.0/standard-install.yaml
echo "Gateway API CRDs installed"

# ── 2. Add Kong Helm repo ──
echo ""
echo "=== Step 2: Adding Kong Helm repo ==="
helm repo add kong https://charts.konghq.com 2>/dev/null || true
helm repo update

# ── 3. Install Kong Ingress Controller ──
echo ""
echo "=== Step 3: Installing Kong ==="
helm upgrade --install kong kong/ingress \
  --namespace api-gateway \
  --create-namespace \
  --set controller.ingressController.enabled=true \
  --set controller.replicaCount=1 \
  --set controller.resources.requests.cpu=100m \
  --set controller.resources.requests.memory=256Mi \
  --set controller.resources.limits.cpu=500m \
  --set controller.resources.limits.memory=512Mi \
  --wait \
  --timeout 5m

echo "Kong installed successfully"

# ── 4. Wait for LoadBalancer IP ──
echo ""
echo "=== Step 4: Waiting for LoadBalancer IP ==="
echo "This may take 2-3 minutes on AWS..."

for i in $(seq 1 30); do
  EXTERNAL=$(kubectl get svc -n api-gateway -o jsonpath='{.items[0].status.loadBalancer.ingress[0].hostname}' 2>/dev/null || echo "")
  if [ -n "$EXTERNAL" ] && [ "$EXTERNAL" != "null" ]; then
    echo ""
    echo "============================================="
    echo "  Kong Gateway is ready!"
    echo "============================================="
    echo ""
    echo "External hostname: $EXTERNAL"
    echo ""
    echo "Test with:"
    echo "  curl http://$EXTERNAL/"
    echo ""
    echo "Note: Routes won't work until api-gateway ArgoCD app is synced"
    exit 0
  fi
  echo "  Waiting... ($i/30)"
  sleep 10
done

echo ""
echo "WARNING: LoadBalancer IP not assigned after 5 minutes"
echo "Check status with: kubectl get svc -n api-gateway"
echo "Kong is installed but may still be provisioning the ELB"

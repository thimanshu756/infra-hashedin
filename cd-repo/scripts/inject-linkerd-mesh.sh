#!/bin/bash
# =============================================================================
# Linkerd Mesh Injection
# =============================================================================
# Annotates namespaces for automatic Linkerd proxy injection
# and rolling restarts existing deployments.
# Run AFTER Linkerd control plane is installed.
#
# Usage: ./inject-linkerd-mesh.sh
# =============================================================================

set -euo pipefail

MESHED_NAMESPACES=(
  "frontend"
  "backend-users"
  "backend-products"
  "backend-orders"
)

echo "============================================="
echo "  Linkerd Mesh Injection"
echo "============================================="

# ── 1. Annotate namespaces ──
echo ""
echo "── 1. Annotating namespaces for Linkerd injection ──"
for NS in "${MESHED_NAMESPACES[@]}"; do
  kubectl annotate namespace "$NS" \
    linkerd.io/inject=enabled \
    --overwrite
  echo "  Annotated: $NS"
done

# ── 2. Rolling restart to inject sidecar ──
echo ""
echo "── 2. Rolling restart to inject Linkerd proxy ──"
kubectl rollout restart deployment/frontend -n frontend
kubectl rollout restart deployment/users-service -n backend-users
kubectl rollout restart deployment/products-service -n backend-products
kubectl rollout restart deployment/orders-service -n backend-orders

# ── 3. Wait for rollouts ──
echo ""
echo "── 3. Waiting for rollouts to complete ──"
kubectl rollout status deployment/frontend -n frontend --timeout=120s
kubectl rollout status deployment/users-service -n backend-users --timeout=120s
kubectl rollout status deployment/products-service -n backend-products --timeout=120s
kubectl rollout status deployment/orders-service -n backend-orders --timeout=120s

# ── 4. Verify injection ──
echo ""
echo "── 4. Verifying Linkerd injection ──"
echo "Pods should now show 2/2 READY (app + linkerd-proxy sidecar):"
echo ""
echo "frontend:"
kubectl get pods -n frontend
echo ""
echo "backend-users:"
kubectl get pods -n backend-users
echo ""
echo "backend-products:"
kubectl get pods -n backend-products
echo ""
echo "backend-orders:"
kubectl get pods -n backend-orders

echo ""
echo "── 5. Proxy check ──"
linkerd check --proxy

echo ""
echo "============================================="
echo "  Linkerd injection complete"
echo "============================================="
echo ""
echo "  All app pods should show 2/2 READY"
echo "  Next: push linkerd-config chart for zero-trust policies"
echo ""
echo "============================================="

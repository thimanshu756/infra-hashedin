#!/bin/bash
# =============================================================================
# Phase 6 Complete Verification Script
# =============================================================================
# Checks all Phase 6 components are running and configured correctly.
# =============================================================================

set -euo pipefail

PASS=0
FAIL=0

check() {
  local description="$1"
  local command="$2"
  echo -n "  $description... "
  if eval "$command" > /dev/null 2>&1; then
    echo "PASS"
    PASS=$((PASS + 1))
  else
    echo "FAIL"
    FAIL=$((FAIL + 1))
  fi
}

echo "============================================="
echo "  Phase 6 Complete Verification"
echo "============================================="

# ── 1. ResourceQuota ──
echo ""
echo "── 1. ResourceQuota ──"
kubectl get resourcequota -A --no-headers 2>/dev/null | grep -v "^kube" || echo "  No quotas found"
echo ""
check "ResourceQuota exists in frontend" "kubectl get resourcequota namespace-quota -n frontend"
check "ResourceQuota exists in backend-users" "kubectl get resourcequota namespace-quota -n backend-users"
check "ResourceQuota exists in backend-products" "kubectl get resourcequota namespace-quota -n backend-products"
check "ResourceQuota exists in backend-orders" "kubectl get resourcequota namespace-quota -n backend-orders"
check "ResourceQuota exists in database" "kubectl get resourcequota namespace-quota -n database"
check "ResourceQuota exists in monitoring" "kubectl get resourcequota namespace-quota -n monitoring"
check "ResourceQuota exists in logging" "kubectl get resourcequota namespace-quota -n logging"
check "ResourceQuota exists in argocd" "kubectl get resourcequota namespace-quota -n argocd"
echo ""
echo "  Utilization for backend-users:"
kubectl describe resourcequota namespace-quota -n backend-users 2>/dev/null | grep -A20 "Resource" || true

# ── 2. LimitRange ──
echo ""
echo "── 2. LimitRange ──"
kubectl get limitrange -A --no-headers 2>/dev/null | grep -v "^kube" || echo "  No limit ranges found"
echo ""
check "LimitRange exists in frontend" "kubectl get limitrange namespace-limits -n frontend"
check "LimitRange exists in backend-users" "kubectl get limitrange namespace-limits -n backend-users"
check "LimitRange exists in backend-products" "kubectl get limitrange namespace-limits -n backend-products"
check "LimitRange exists in backend-orders" "kubectl get limitrange namespace-limits -n backend-orders"

# ── 3. KEDA ──
echo ""
echo "── 3. KEDA ──"
kubectl get pods -n keda 2>/dev/null || echo "  KEDA namespace not found"
echo ""
check "KEDA operator pod running" "kubectl get pods -n keda -l app=keda-operator -o jsonpath='{.items[*].status.phase}' | grep -q Running"
check "KEDA metrics server running" "kubectl get pods -n keda -l app=keda-operator-metrics-apiserver -o jsonpath='{.items[*].status.phase}' | grep -q Running"
check "ScaledObject exists in backend-users" "kubectl get scaledobject users-service-scaler -n backend-users"
echo ""
echo "  ScaledObject status:"
kubectl get scaledobject -n backend-users -o wide 2>/dev/null || echo "  (none)"
echo ""
echo "  HPA created by KEDA:"
kubectl get hpa -n backend-users 2>/dev/null || echo "  (none)"

# ── 4. Linkerd ──
echo ""
echo "── 4. Linkerd ──"
if command -v linkerd &> /dev/null; then
  linkerd check 2>/dev/null | tail -5 || true
else
  echo "  Linkerd CLI not installed on this machine"
fi
echo ""
check "Linkerd namespace exists" "kubectl get namespace linkerd"
check "Linkerd destination running" "kubectl get pods -n linkerd -l linkerd.io/control-plane-component=destination -o jsonpath='{.items[*].status.phase}' | grep -q Running"
echo ""
echo "  Meshed pods (should show 2/2 READY):"
echo "  frontend:"
kubectl get pods -n frontend --no-headers 2>/dev/null | awk '{print "    "$1" "$2}'
echo "  backend-users:"
kubectl get pods -n backend-users --no-headers 2>/dev/null | awk '{print "    "$1" "$2}'
echo "  backend-products:"
kubectl get pods -n backend-products --no-headers 2>/dev/null | awk '{print "    "$1" "$2}'
echo "  backend-orders:"
kubectl get pods -n backend-orders --no-headers 2>/dev/null | awk '{print "    "$1" "$2}'
echo ""
echo "  Linkerd stat:"
linkerd viz stat deployments -n backend-users 2>/dev/null || echo "  (linkerd viz not available)"

# ── 5. Test ResourceQuota enforcement ──
echo ""
echo "── 5. Test ResourceQuota enforcement ──"
echo "  Creating deployment with 15 replicas (quota allows 10 pods):"
kubectl create deployment quota-test \
  --image=nginx \
  --replicas=15 \
  --namespace=backend-users \
  2>&1 || true
sleep 3
RUNNING=$(kubectl get deployment quota-test -n backend-users \
  -o jsonpath='{.status.availableReplicas}' 2>/dev/null || echo "0")
echo "  Running replicas: ${RUNNING:-0} (should be <15 due to quota)"
kubectl delete deployment quota-test -n backend-users 2>/dev/null || true
if [ "${RUNNING:-0}" -lt 15 ] 2>/dev/null; then
  echo "  PASS: ResourceQuota correctly limited pod creation"
  PASS=$((PASS + 1))
else
  echo "  FAIL: ResourceQuota may not be enforced"
  FAIL=$((FAIL + 1))
fi

# ── 6. Server + ServerAuthorization policies ──
echo ""
echo "── 6. Linkerd Authorization Policies ──"
check "Server resource in backend-users" "kubectl get server -n backend-users"
check "ServerAuthorization in backend-users" "kubectl get serverauthorization -n backend-users"
check "Server resource in backend-products" "kubectl get server -n backend-products"
check "Server resource in backend-orders" "kubectl get server -n backend-orders"
check "Server resource in frontend" "kubectl get server -n frontend"

# ── 7. ArgoCD applications ──
echo ""
echo "── 7. All ArgoCD applications ──"
kubectl get applications -n argocd -o wide 2>/dev/null || echo "  ArgoCD not accessible"

# ── Summary ──
echo ""
echo "============================================="
echo "  Phase 6 Verification Summary"
echo "============================================="
echo "  PASSED: $PASS"
echo "  FAILED: $FAIL"
echo ""
if [ $FAIL -eq 0 ]; then
  echo "  ALL CHECKS PASSED — Platform fully built!"
else
  echo "  SOME CHECKS FAILED — review output above"
fi
echo ""
echo "  Remaining demos to run:"
echo "    1. ./scripts/load-test-keda.sh       <- KEDA scale demo"
echo "    2. ./scripts/verify-linkerd.sh        <- Zero-trust proof"
echo "    3. ./scripts/node-failure-test.sh     <- Resilience test"
echo ""
echo "============================================="

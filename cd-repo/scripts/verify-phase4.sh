#!/bin/bash
# =============================================================================
# Phase 4 Verification Script
# =============================================================================
# Comprehensive checks for all Phase 4 components:
#   1. Percona PostgreSQL
#   2. Kong Gateway
#   3. Sealed Secrets
#   4. Kyverno policies
#   5. Network Policies
#   6. End-to-end API test
#
# Usage: ./verify-phase4.sh
# =============================================================================

set -e

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
echo "  Phase 4 — Comprehensive Verification"
echo "============================================="

# ── 1. Percona PostgreSQL ──
echo ""
echo "── 1. Percona PostgreSQL ──"
kubectl get pods -n database
echo ""
check "Percona pods running" "kubectl get pods -n database -o jsonpath='{.items[*].status.phase}' | grep -q Running"
check "PerconaPGCluster exists" "kubectl get PerconaPGCluster -n database"
check "PgBouncer service exists" "kubectl get svc -n database | grep -q pgbouncer"
check "DB appuser secret exists" "kubectl get secret -n database | grep -q appuser"

# ── 2. Kong Gateway ──
echo ""
echo "── 2. Kong Gateway ──"
kubectl get pods -n api-gateway
echo ""
check "Kong pods running" "kubectl get pods -n api-gateway -o jsonpath='{.items[*].status.phase}' | grep -q Running"
check "Gateway resource exists" "kubectl get gateway -n api-gateway"
check "HTTPRoutes exist" "test \$(kubectl get httproute -n api-gateway --no-headers 2>/dev/null | wc -l) -ge 4"

EXTERNAL_IP=$(kubectl get svc -n api-gateway \
  -o jsonpath='{.items[0].status.loadBalancer.ingress[0].hostname}' 2>/dev/null || echo "")
if [ -n "$EXTERNAL_IP" ] && [ "$EXTERNAL_IP" != "null" ]; then
  echo "  External IP/Hostname: $EXTERNAL_IP"
else
  echo "  External IP: NOT YET ASSIGNED (may still be provisioning)"
fi

# ── 3. Sealed Secrets ──
echo ""
echo "── 3. Sealed Secrets ──"
kubectl get pods -n sealed-secrets
echo ""
check "Sealed Secrets controller running" "kubectl get pods -n sealed-secrets -o jsonpath='{.items[*].status.phase}' | grep -q Running"
check "db-credentials in backend-users" "kubectl get secret db-credentials -n backend-users"
check "db-credentials in backend-products" "kubectl get secret db-credentials -n backend-products"
check "db-credentials in backend-orders" "kubectl get secret db-credentials -n backend-orders"

# ── 4. Kyverno ──
echo ""
echo "── 4. Kyverno Policies ──"
kubectl get pods -n security 2>/dev/null || kubectl get pods -n kyverno 2>/dev/null || echo "Kyverno namespace check"
echo ""
check "Kyverno admission controller running" "kubectl get pods -A -l app.kubernetes.io/component=admission-controller -o jsonpath='{.items[*].status.phase}' | grep -q Running"
check "disallow-root-user policy exists" "kubectl get clusterpolicy disallow-root-user"
check "require-resource-limits policy exists" "kubectl get clusterpolicy require-resource-limits"
check "disallow-latest-tag policy exists" "kubectl get clusterpolicy disallow-latest-tag"

# ── 5. Network Policies ──
echo ""
echo "── 5. Network Policies ──"
check "default-deny in frontend" "kubectl get networkpolicy default-deny-all -n frontend"
check "default-deny in backend-users" "kubectl get networkpolicy default-deny-all -n backend-users"
check "allow-dns in frontend" "kubectl get networkpolicy allow-dns-egress -n frontend"
check "allow-from-gateway in backend-users" "kubectl get networkpolicy allow-from-gateway -n backend-users"
check "allow-to-database in backend-users" "kubectl get networkpolicy allow-to-database -n backend-users"
check "allow-from-backends in database" "kubectl get networkpolicy allow-from-backends -n database"

# ── 6. ArgoCD Application Status ──
echo ""
echo "── 6. ArgoCD Applications ──"
kubectl get applications -n argocd
echo ""
check "All apps synced" "! kubectl get applications -n argocd -o jsonpath='{.items[*].status.sync.status}' | grep -qv Synced"

# ── 7. Kyverno Enforcement Test ──
echo ""
echo "── 7. Kyverno Enforcement Test ──"
echo "  Testing: Root container should be REJECTED..."
ROOT_TEST=$(kubectl run root-test \
  --image=nginx \
  --restart=Never \
  --namespace=backend-users \
  --overrides='{"spec":{"securityContext":{"runAsUser":0,"runAsNonRoot":false},"containers":[{"name":"root-test","image":"nginx","resources":{"limits":{"cpu":"100m","memory":"128Mi"}}}]}}' \
  --dry-run=server 2>&1 || true)

if echo "$ROOT_TEST" | grep -qi "denied\|blocked\|violated\|disallow"; then
  echo "  PASS — Kyverno correctly REJECTED root container"
  PASS=$((PASS + 1))
else
  echo "  FAIL — Root container was NOT rejected"
  echo "  Output: $ROOT_TEST"
  FAIL=$((FAIL + 1))
fi

# ── 8. End-to-End API Test ──
echo ""
echo "── 8. End-to-End API Test ──"
if [ -n "$EXTERNAL_IP" ] && [ "$EXTERNAL_IP" != "null" ]; then
  echo "  Testing through Kong Gateway at: $EXTERNAL_IP"

  check "GET /api/users" "curl -sf http://$EXTERNAL_IP/api/users"
  check "GET /api/products" "curl -sf http://$EXTERNAL_IP/api/products"
  check "GET /api/orders" "curl -sf http://$EXTERNAL_IP/api/orders"
  check "GET / (frontend)" "curl -sf http://$EXTERNAL_IP/"

  # Test POST
  echo ""
  echo "  Testing POST /api/users..."
  POST_RESULT=$(curl -sf -X POST "http://$EXTERNAL_IP/api/users" \
    -H "Content-Type: application/json" \
    -d '{"name":"Phase4 Test","email":"phase4@test.com","role":"admin"}' 2>/dev/null || echo "FAILED")

  if echo "$POST_RESULT" | grep -q "Phase4 Test"; then
    echo "  PASS — POST /api/users works through Kong"
    PASS=$((PASS + 1))
  else
    echo "  FAIL — POST /api/users failed"
    echo "  Response: $POST_RESULT"
    FAIL=$((FAIL + 1))
  fi
else
  echo "  SKIP — No external IP available yet"
  echo "  Run this test after LoadBalancer IP is assigned"
fi

# ── Summary ──
echo ""
echo "============================================="
echo "  Phase 4 Verification Summary"
echo "============================================="
echo "  PASSED: $PASS"
echo "  FAILED: $FAIL"
echo ""

if [ $FAIL -eq 0 ]; then
  echo "  ALL CHECKS PASSED"
else
  echo "  SOME CHECKS FAILED — review output above"
fi

echo ""
echo "============================================="

#!/bin/bash
# =============================================================================
# Node Failure Resilience Test
# =============================================================================
# Demonstrates cluster resilience under single node failure.
# Drains one node and shows:
#   1. Workloads reschedule to remaining node
#   2. Service stays available
#   3. ArgoCD continues reconciling
#   4. Observability captures the event
#
# Usage: ./node-failure-test.sh [gateway-ip-or-hostname]
# =============================================================================

set -euo pipefail

GATEWAY=${1:-$(kubectl get svc -n api-gateway \
  -o jsonpath='{.items[0].status.loadBalancer.ingress[0].hostname}' 2>/dev/null || echo "")}

if [ -z "$GATEWAY" ] || [ "$GATEWAY" = "null" ]; then
  echo "Could not detect Gateway IP automatically."
  echo "Usage: ./node-failure-test.sh <external-ip-or-hostname>"
  exit 1
fi

echo "============================================="
echo "  Node Failure Resilience Test"
echo "============================================="

# ── PRE-TEST: Baseline state ──
echo ""
echo "── PRE-TEST: Baseline state ──"
echo "Current nodes:"
kubectl get nodes -o wide
echo ""
echo "Current pod distribution across nodes:"
kubectl get pods -A -o wide --no-headers | grep -E "backend|frontend" | \
  awk '{printf "  %-20s %-35s %s\n", $8, $2, $1}' | sort

# ── PRE-TEST: Start background traffic ──
echo ""
echo "── PRE-TEST: Start background traffic ──"
echo "Sending continuous traffic during node failure..."
(while true; do
  curl -s "http://$GATEWAY/api/users" > /dev/null 2>&1
  sleep 0.5
done) &
TRAFFIC_PID=$!
echo "Traffic generator PID: $TRAFFIC_PID"

# ── STEP 1: Select node to drain ──
echo ""
echo "── STEP 1: Select node to drain ──"
NODE_TO_DRAIN=$(kubectl get pods -n backend-users -o wide \
  --no-headers | head -1 | awk '{print $7}')
echo "Selected node: $NODE_TO_DRAIN"

# ── STEP 2: Cordon node ──
echo ""
echo "── STEP 2: Cordon node (prevent new scheduling) ──"
kubectl cordon "$NODE_TO_DRAIN"
echo "Node cordoned — no new pods will schedule here"
kubectl get nodes

# ── STEP 3: Drain node ──
echo ""
echo "── STEP 3: Drain node (evict pods) ──"
kubectl drain "$NODE_TO_DRAIN" \
  --ignore-daemonsets \
  --delete-emptydir-data \
  --force \
  --grace-period=30

# ── STEP 4: Watch pod rescheduling ──
echo ""
echo "── STEP 4: Watch pod rescheduling ──"
echo "Pods should reschedule to remaining node..."
for i in $(seq 1 12); do
  echo ""
  echo "[$(date +%H:%M:%S)] Pod status:"
  kubectl get pods -n backend-users -o wide --no-headers 2>/dev/null | awk '{printf "  %-35s %-10s %-8s %s\n", $1, $3, $2, $7}'
  kubectl get pods -n backend-products -o wide --no-headers 2>/dev/null | awk '{printf "  %-35s %-10s %-8s %s\n", $1, $3, $2, $7}'
  kubectl get pods -n backend-orders -o wide --no-headers 2>/dev/null | awk '{printf "  %-35s %-10s %-8s %s\n", $1, $3, $2, $7}'
  kubectl get pods -n frontend -o wide --no-headers 2>/dev/null | awk '{printf "  %-35s %-10s %-8s %s\n", $1, $3, $2, $7}'
  sleep 5
done

# ── STEP 5: Verify service still available ──
echo ""
echo "── STEP 5: Verify service still available ──"
echo "Testing API during/after node failure:"
SVC_PASS=0
SVC_FAIL=0
for i in $(seq 1 5); do
  RESP=$(curl -s -o /dev/null -w "%{http_code}" "http://$GATEWAY/api/users" 2>/dev/null || echo "000")
  echo "  HTTP Status: $RESP ($(date +%H:%M:%S))"
  if [ "$RESP" = "200" ]; then
    SVC_PASS=$((SVC_PASS + 1))
  else
    SVC_FAIL=$((SVC_FAIL + 1))
  fi
  sleep 2
done
echo "  Results: $SVC_PASS passed, $SVC_FAIL failed"

# ── STEP 6: Check ArgoCD still reconciling ──
echo ""
echo "── STEP 6: Check ArgoCD still reconciling ──"
kubectl get applications -n argocd -o wide 2>/dev/null | head -20
echo "ArgoCD should still show Synced + Healthy (or Progressing)"

# ── STEP 7: Check Grafana captured the event ──
echo ""
echo "── STEP 7: Grafana queries to verify ──"
echo "  In Grafana, check:"
echo "    1. Node readiness metric dropped"
echo "       Query: kube_node_status_condition{condition='Ready',status='true'}"
echo "    2. Pod restart count increased temporarily"
echo "       Query: kube_pod_container_status_restarts_total"
echo "    3. Error spike in logs during drain"
echo "       Loki: {namespace='backend-users'} |= 'ERROR'"

# ── STEP 8: Restore node ──
echo ""
echo "── STEP 8: Restore node ──"
echo "Uncordoning node — bringing it back to cluster:"
kubectl uncordon "$NODE_TO_DRAIN"
echo "Node restored."
kubectl get nodes

# ── CLEANUP ──
echo ""
echo "── CLEANUP ──"
kill "$TRAFFIC_PID" 2>/dev/null || true
echo "Traffic generator stopped."

echo ""
echo "============================================="
echo "  Node Failure Test Complete"
echo "============================================="
echo ""
echo "  Key observations to document:"
echo "    1. Pods rescheduled to surviving node"
echo "    2. API returned 200s during drain (or brief 5xx during eviction)"
echo "    3. ArgoCD remained Synced throughout"
echo "    4. Grafana shows node went NotReady and pods restarted"
echo "    5. PostgreSQL had a brief unavailability (single instance limitation)"
echo "       -> This is EXPECTED and ACCEPTABLE — document it"
echo ""
echo "============================================="

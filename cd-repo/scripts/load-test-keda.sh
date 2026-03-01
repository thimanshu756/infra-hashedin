#!/bin/bash
# =============================================================================
# KEDA Autoscaling Demo
# =============================================================================
# Demonstrates KEDA autoscaling in real time.
# Sends high traffic to users-service, watches replicas scale out,
# then stops traffic and watches scale-in.
#
# Usage: ./load-test-keda.sh [gateway-ip-or-hostname]
# =============================================================================

set -euo pipefail

GATEWAY=${1:-$(kubectl get svc -n api-gateway \
  -o jsonpath='{.items[0].status.loadBalancer.ingress[0].hostname}' 2>/dev/null || echo "")}

if [ -z "$GATEWAY" ] || [ "$GATEWAY" = "null" ]; then
  echo "Could not detect Gateway IP automatically."
  echo "Usage: ./load-test-keda.sh <external-ip-or-hostname>"
  exit 1
fi

echo "============================================="
echo "  KEDA Autoscaling Demo"
echo "============================================="
echo ""
echo "  Target: $GATEWAY"
echo "  Scaling trigger: >10 requests/sec to users-service"
echo ""
echo "  Watch replicas in another terminal:"
echo "    watch kubectl get pods -n backend-users"
echo ""
echo "  Or watch in Grafana:"
echo "    kube_deployment_status_replicas{deployment='users-service'}"
echo ""

# ── Phase 1: Baseline ──
echo "── Phase 1: Baseline (before load) ──"
kubectl get deployment users-service -n backend-users
BASELINE=$(kubectl get deploy users-service \
  -n backend-users -o jsonpath='{.status.readyReplicas}' 2>/dev/null || echo "?")
echo "Current replicas: $BASELINE"

echo ""
echo "Starting load test in 5 seconds..."
sleep 5

# ── Phase 2: Apply load ──
echo ""
echo "── Phase 2: Applying load (2 minutes) ──"
echo "Sending ~20 req/sec to users-service..."

# Run load in parallel (20 concurrent workers)
LOAD_PIDS=""
for i in $(seq 1 20); do
  (while true; do
    curl -s "http://$GATEWAY/api/users" > /dev/null 2>&1
    sleep 0.05
  done) &
  LOAD_PIDS="$LOAD_PIDS $!"
done

# Monitor scaling for 2 minutes
for i in $(seq 1 24); do
  sleep 5
  REPLICAS=$(kubectl get deploy users-service \
    -n backend-users \
    -o jsonpath='{.status.readyReplicas}' 2>/dev/null || echo "?")
  REMAINING=$((120 - i * 5))
  printf "\r  [%s] Replicas: %s | Time remaining: %ds  " \
    "$(date +%H:%M:%S)" "$REPLICAS" "$REMAINING"
done

echo ""

# ── Phase 3: Stop load ──
echo ""
echo "── Phase 3: Stopping load ──"
for PID in $LOAD_PIDS; do
  kill "$PID" 2>/dev/null || true
done
wait 2>/dev/null || true

echo "Load stopped. Watching scale-in (cooldown: 60s)..."

# ── Phase 4: Watch scale-in ──
echo ""
echo "── Phase 4: Scale-in monitoring ──"
for i in $(seq 1 12); do
  sleep 10
  REPLICAS=$(kubectl get deploy users-service \
    -n backend-users \
    -o jsonpath='{.status.readyReplicas}' 2>/dev/null || echo "?")
  echo "  [$(date +%H:%M:%S)] Replicas: $REPLICAS (cooling down...)"
done

# ── Summary ──
echo ""
echo "============================================="
echo "  KEDA Demo Summary"
echo "============================================="
echo ""
echo "  ScaledObject status:"
kubectl get scaledobject -n backend-users -o wide 2>/dev/null || echo "  (no scaledobject found)"
echo ""
echo "  HPA status (KEDA creates HPA under the hood):"
kubectl get hpa -n backend-users 2>/dev/null || echo "  (no HPA found)"
echo ""
echo "  Final replica count (should return to $BASELINE):"
kubectl get deployment users-service -n backend-users
echo ""
echo "============================================="

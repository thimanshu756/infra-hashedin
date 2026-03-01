#!/bin/bash
# =============================================================================
# Test Traffic Generator
# =============================================================================
# Generates sustained traffic to populate:
#   - Prometheus metrics (request rate, latency histograms)
#   - Tempo traces (distributed traces through OTEL)
#   - Loki logs (JSON structured logs from Flask apps)
#
# Usage: ./generate-test-traffic.sh [gateway-ip]
# =============================================================================

set -euo pipefail

GATEWAY_IP=${1:-$(kubectl get svc -n api-gateway \
  -o jsonpath='{.items[0].status.loadBalancer.ingress[0].hostname}' 2>/dev/null || echo "")}

if [ -z "$GATEWAY_IP" ] || [ "$GATEWAY_IP" = "null" ]; then
  echo "Could not detect Gateway IP automatically."
  echo "Usage: ./generate-test-traffic.sh <external-ip-or-hostname>"
  exit 1
fi

echo "============================================="
echo "  Generating Test Traffic"
echo "============================================="
echo "  Gateway: $GATEWAY_IP"
echo ""

# ── 1. Create test data ──
echo "── Creating test data ──"

echo "Creating 5 users..."
for i in $(seq 1 5); do
  curl -sf -X POST "http://$GATEWAY_IP/api/users" \
    -H "Content-Type: application/json" \
    -d "{\"name\":\"User$i\",\"email\":\"user${i}@test.com\",\"role\":\"user\"}" \
    > /dev/null 2>&1 && echo "  User$i created" || echo "  User$i failed (may exist)"
done

echo "Creating 5 products..."
for i in $(seq 1 5); do
  curl -sf -X POST "http://$GATEWAY_IP/api/products" \
    -H "Content-Type: application/json" \
    -d "{\"name\":\"Product$i\",\"price\":$((i*10)).99,\"category\":\"test\"}" \
    > /dev/null 2>&1 && echo "  Product$i created" || echo "  Product$i failed (may exist)"
done

echo "Creating 5 orders..."
for i in $(seq 1 5); do
  curl -sf -X POST "http://$GATEWAY_IP/api/orders" \
    -H "Content-Type: application/json" \
    -d "{\"user_id\":$i,\"product_id\":$i,\"quantity\":$i}" \
    > /dev/null 2>&1 && echo "  Order$i created" || echo "  Order$i failed"
done

# ── 2. Sustained traffic for metrics ──
echo ""
echo "── Generating sustained traffic for 60 seconds ──"
echo "  Watch Grafana dashboards update in real time"
echo "  (Ctrl+C to stop early)"
echo ""

REQUESTS=0
ERRORS=0
END=$((SECONDS+60))

while [ $SECONDS -lt $END ]; do
  # Hit all endpoints
  curl -sf "http://$GATEWAY_IP/api/users" > /dev/null 2>&1 && REQUESTS=$((REQUESTS+1)) || ERRORS=$((ERRORS+1))
  curl -sf "http://$GATEWAY_IP/api/products" > /dev/null 2>&1 && REQUESTS=$((REQUESTS+1)) || ERRORS=$((ERRORS+1))
  curl -sf "http://$GATEWAY_IP/api/orders" > /dev/null 2>&1 && REQUESTS=$((REQUESTS+1)) || ERRORS=$((ERRORS+1))
  curl -sf "http://$GATEWAY_IP/" > /dev/null 2>&1 && REQUESTS=$((REQUESTS+1)) || ERRORS=$((ERRORS+1))

  # Also hit individual items
  curl -sf "http://$GATEWAY_IP/api/users/1" > /dev/null 2>&1 || true
  curl -sf "http://$GATEWAY_IP/api/products/1" > /dev/null 2>&1 || true
  REQUESTS=$((REQUESTS+2))

  # Intentional 404 to generate error metrics
  curl -sf "http://$GATEWAY_IP/api/users/999" > /dev/null 2>&1 || true
  REQUESTS=$((REQUESTS+1))

  printf "\r  Requests: %d | Errors: %d | Time remaining: %ds  " \
    $REQUESTS $ERRORS $((END-SECONDS))
  sleep 1
done

echo ""
echo ""
echo "============================================="
echo "  Traffic Generation Complete"
echo "============================================="
echo "  Total requests: $REQUESTS"
echo "  Errors: $ERRORS"
echo ""
echo "  Check Grafana at http://localhost:3000"
echo "    -> Dashboards -> Flask Microservices"
echo "    -> Explore -> Loki -> {namespace=\"backend-users\"}"
echo "    -> Explore -> Tempo -> Search traces"
echo ""

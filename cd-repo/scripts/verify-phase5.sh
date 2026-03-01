#!/bin/bash
# =============================================================================
# Phase 5 Observability Verification Script
# =============================================================================
# Checks all observability components are running and connected.
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
echo "  Phase 5 — Observability Verification"
echo "============================================="

# ── 1. Monitoring Namespace ──
echo ""
echo "── 1. Monitoring Pods ──"
kubectl get pods -n monitoring
echo ""
check "Prometheus pod running" "kubectl get pods -n monitoring -l app.kubernetes.io/name=prometheus -o jsonpath='{.items[*].status.phase}' | grep -q Running"
check "Grafana pod running" "kubectl get pods -n monitoring -l app.kubernetes.io/name=grafana -o jsonpath='{.items[*].status.phase}' | grep -q Running"
check "Tempo pod running" "kubectl get pods -n monitoring -l app=tempo -o jsonpath='{.items[*].status.phase}' | grep -q Running"
check "OTEL Collector pod running" "kubectl get pods -n monitoring -l app=otel-collector -o jsonpath='{.items[*].status.phase}' | grep -q Running"
check "Node Exporter DaemonSet running" "kubectl get ds -n monitoring -l app.kubernetes.io/name=prometheus-node-exporter -o jsonpath='{.items[*].status.numberReady}' | grep -qv 0"
check "Kube State Metrics running" "kubectl get pods -n monitoring -l app.kubernetes.io/name=kube-state-metrics -o jsonpath='{.items[*].status.phase}' | grep -q Running"

# ── 2. Logging Namespace ──
echo ""
echo "── 2. Logging Pods ──"
kubectl get pods -n logging
echo ""
check "Loki pod running" "kubectl get pods -n logging -l app=loki -o jsonpath='{.items[*].status.phase}' | grep -q Running"
check "Promtail DaemonSet running" "kubectl get ds -n logging -l app.kubernetes.io/name=promtail -o jsonpath='{.items[*].status.numberReady}' | grep -qv 0"

# ── 3. Services ──
echo ""
echo "── 3. Services ──"
check "Prometheus service exists" "kubectl get svc prometheus-operated -n monitoring"
check "Grafana service exists" "kubectl get svc prometheus-grafana -n monitoring"
check "Tempo service exists" "kubectl get svc tempo -n monitoring"
check "OTEL Collector service exists" "kubectl get svc otel-collector -n monitoring"
check "Loki service exists" "kubectl get svc loki -n logging"

# ── 4. Grafana Datasources ──
echo ""
echo "── 4. Grafana Datasources ──"
echo "  Starting port-forward to check datasources..."
kubectl port-forward svc/prometheus-grafana -n monitoring 13000:80 &
PF_PID=$!
sleep 3

DS_OUTPUT=$(curl -sf -u admin:admin123 http://localhost:13000/api/datasources 2>/dev/null || echo "[]")
kill $PF_PID 2>/dev/null
wait $PF_PID 2>/dev/null

check "Prometheus datasource configured" "echo '$DS_OUTPUT' | grep -q Prometheus"
check "Loki datasource configured" "echo '$DS_OUTPUT' | grep -q Loki"
check "Tempo datasource configured" "echo '$DS_OUTPUT' | grep -q Tempo"

# ── 5. Flask Metrics Available ──
echo ""
echo "── 5. Flask Metrics ──"
echo "  Port-forwarding Prometheus to check targets..."
kubectl port-forward svc/prometheus-operated -n monitoring 19090:9090 &
PF_PID2=$!
sleep 3

TARGETS=$(curl -sf http://localhost:19090/api/v1/targets 2>/dev/null || echo "{}")
kill $PF_PID2 2>/dev/null
wait $PF_PID2 2>/dev/null

check "flask-users-service target exists" "echo '$TARGETS' | grep -q flask-users-service"
check "flask-products-service target exists" "echo '$TARGETS' | grep -q flask-products-service"
check "flask-orders-service target exists" "echo '$TARGETS' | grep -q flask-orders-service"
check "flask-frontend target exists" "echo '$TARGETS' | grep -q flask-frontend"

# ── 6. OTEL Pipeline Check ──
echo ""
echo "── 6. OTEL Trace Pipeline ──"
check "OTEL Collector has no error logs" "! kubectl logs -n monitoring -l app=otel-collector --tail=20 2>/dev/null | grep -qi 'error\|failed'"
check "Tempo has no error logs" "! kubectl logs -n monitoring -l app=tempo --tail=20 2>/dev/null | grep -qi 'error\|failed'"

# ── 7. Loki Ingestion Check ──
echo ""
echo "── 7. Loki Log Ingestion ──"
echo "  Querying Loki for recent logs..."
kubectl port-forward svc/loki -n logging 13100:3100 &
PF_PID3=$!
sleep 3

LOKI_RESULT=$(curl -sf "http://localhost:13100/loki/api/v1/query?query=%7Bnamespace%3D%22backend-users%22%7D&limit=1" 2>/dev/null || echo "{}")
kill $PF_PID3 2>/dev/null
wait $PF_PID3 2>/dev/null

check "Loki receiving logs from backend-users" "echo '$LOKI_RESULT' | grep -q result"

# ── 8. ArgoCD Application Status ──
echo ""
echo "── 8. ArgoCD Applications ──"
check "monitoring app synced" "kubectl get application monitoring -n argocd -o jsonpath='{.status.sync.status}' | grep -q Synced"
check "logging app synced" "kubectl get application logging -n argocd -o jsonpath='{.status.sync.status}' | grep -q Synced"

# ── Summary ──
echo ""
echo "============================================="
echo "  Phase 5 Verification Summary"
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
echo "  Next: Open Grafana to verify dashboards visually"
echo "    ./port-forward-grafana.sh"
echo "    http://localhost:3000 (admin/admin123)"
echo ""
echo "============================================="

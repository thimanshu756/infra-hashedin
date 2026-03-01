#!/bin/bash
# =============================================================================
# Grafana Port-Forward Script
# =============================================================================
# Opens Grafana UI via kubectl port-forward.
# Access at http://localhost:3000 after running this script.
#
# Usage: ./port-forward-grafana.sh
# =============================================================================

set -euo pipefail

echo "============================================="
echo "  Grafana UI Access"
echo "============================================="
echo ""
echo "  URL:      http://localhost:3000"
echo "  Username: admin"
echo "  Password: admin123"
echo ""
echo "  Press Ctrl+C to stop port-forward"
echo ""
echo "============================================="

# Kill any existing port-forward to Grafana
pkill -f "port-forward.*grafana" 2>/dev/null || true
sleep 1

kubectl port-forward \
  svc/prometheus-grafana \
  -n monitoring \
  3000:80

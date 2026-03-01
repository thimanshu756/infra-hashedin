#!/bin/bash
# =============================================================================
# Linkerd Control Plane Installation
# =============================================================================
# Installs Linkerd control plane on EKS cluster.
# Run ONCE manually from bastion or local with kubectl access.
#
# Usage: ./install-linkerd.sh
# =============================================================================

set -euo pipefail

echo "============================================="
echo "  Installing Linkerd Service Mesh"
echo "============================================="

# ── 1. Install Linkerd CLI ──
echo ""
echo "── 1. Installing Linkerd CLI ──"
if command -v linkerd &> /dev/null; then
  echo "  Linkerd CLI already installed: $(linkerd version --client --short)"
else
  curl --proto '=https' --tlsv1.2 -sSfL https://run.linkerd.io/install | sh
  export PATH=$PATH:$HOME/.linkerd2/bin
  echo "  Linkerd CLI installed: $(linkerd version --client --short)"
fi

# ── 2. Pre-install check ──
echo ""
echo "── 2. Checking pre-install requirements ──"
linkerd check --pre

# ── 3. Install CRDs ──
echo ""
echo "── 3. Installing Linkerd CRDs ──"
linkerd install --crds | kubectl apply -f -

# ── 4. Install control plane ──
echo ""
echo "── 4. Installing Linkerd control plane ──"
linkerd install \
  --set controllerReplicas=1 \
  --set controllerResources.cpu.request=100m \
  --set controllerResources.memory.request=128Mi \
  --set controllerResources.cpu.limit=300m \
  --set controllerResources.memory.limit=256Mi \
  --set destinationResources.cpu.request=100m \
  --set destinationResources.memory.request=128Mi \
  --set proxyResources.cpu.request=10m \
  --set proxyResources.memory.request=32Mi \
  | kubectl apply -f -

# ── 5. Wait for Linkerd to be ready ──
echo ""
echo "── 5. Waiting for Linkerd to be ready ──"
linkerd check

# ── 6. Install Linkerd Viz ──
echo ""
echo "── 6. Installing Linkerd Viz (dashboard) ──"
linkerd viz install \
  --set resources.cpu.request=100m \
  --set resources.memory.request=128Mi \
  | kubectl apply -f -

linkerd viz check

echo ""
echo "============================================="
echo "  Linkerd installed successfully"
echo "============================================="
echo ""
echo "  Next steps:"
echo "    1. Run ./inject-linkerd-mesh.sh to mesh app namespaces"
echo "    2. Access dashboard: linkerd viz dashboard &"
echo ""
echo "============================================="

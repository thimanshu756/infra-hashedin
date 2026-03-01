#!/bin/bash
# =============================================================================
# ArgoCD Bootstrap Script
# =============================================================================
# Run this ONCE from bastion (via SSM) or local machine with kubectl access.
# This is the only manual step — ArgoCD manages everything after this.
#
# Usage: ./bootstrap-argocd.sh <cd-repo-url> <cd-repo-pat>
# Example: ./bootstrap-argocd.sh https://github.com/thimanshu756/hitakshi-cd ghp_xxxxx
# =============================================================================

set -euo pipefail

CD_REPO_URL=${1:-""}
CD_REPO_PAT=${2:-""}

if [ -z "$CD_REPO_URL" ] || [ -z "$CD_REPO_PAT" ]; then
  echo "Usage: ./bootstrap-argocd.sh <cd-repo-url> <cd-repo-pat>"
  echo "  cd-repo-url: HTTPS URL of your CD repo (e.g., https://github.com/org/repo)"
  echo "  cd-repo-pat: GitHub Personal Access Token with repo scope"
  exit 1
fi

echo "============================================="
echo "  ArgoCD Bootstrap — Starting"
echo "============================================="

# ── 1. Add ArgoCD Helm repo ──
echo ""
echo "=== Step 1: Adding ArgoCD Helm repo ==="
helm repo add argo https://argoproj.github.io/argo-helm 2>/dev/null || true
helm repo update

# ── 2. Install ArgoCD ──
echo ""
echo "=== Step 2: Installing ArgoCD ==="
helm upgrade --install argocd argo/argo-cd \
  --namespace argocd \
  --create-namespace \
  --version 6.7.0 \
  --values "$(dirname "$0")/../argocd/install/values.yaml" \
  --wait \
  --timeout 5m

echo "ArgoCD installed successfully"

# ── 3. Wait for ArgoCD server to be ready ──
echo ""
echo "=== Step 3: Waiting for ArgoCD server ==="
kubectl wait --for=condition=available deployment/argocd-server \
  -n argocd --timeout=120s

# ── 4. Get initial admin password ──
echo ""
echo "=== Step 4: ArgoCD Admin Credentials ==="
ARGOCD_PASS=$(kubectl -n argocd get secret argocd-initial-admin-secret \
  -o jsonpath="{.data.password}" | base64 -d)
echo "Username: admin"
echo "Password: ${ARGOCD_PASS}"
echo ""
echo "Access ArgoCD UI:"
echo "  kubectl port-forward svc/argocd-server -n argocd 8080:80"
echo "  Then open: http://localhost:8080"

# ── 5. Add CD repo credentials ──
echo ""
echo "=== Step 5: Adding CD repo credentials ==="
kubectl create secret generic cd-repo-secret \
  --namespace argocd \
  --from-literal=type=git \
  --from-literal=url="${CD_REPO_URL}" \
  --from-literal=password="${CD_REPO_PAT}" \
  --from-literal=username=git \
  --dry-run=client -o yaml | kubectl apply -f -

kubectl label secret cd-repo-secret \
  -n argocd \
  argocd.argoproj.io/secret-type=repository \
  --overwrite

echo "CD repo credentials added"

# ── 6. Apply ArgoCD AppProject ──
echo ""
echo "=== Step 6: Applying ArgoCD AppProject ==="
kubectl apply -f "$(dirname "$0")/../argocd/projects/eks-assignment.yaml"

# ── 7. Apply ApplicationSets in order ──
echo ""
echo "=== Step 7: Applying ApplicationSets ==="

echo "Applying namespaces app (sync wave -2)..."
kubectl apply -f "$(dirname "$0")/../argocd/applicationsets/namespaces-app.yaml"

echo "Waiting 15s for namespaces to be created..."
sleep 15

echo "Applying platform appset (sync wave -1)..."
kubectl apply -f "$(dirname "$0")/../argocd/applicationsets/platform-appset.yaml"

echo "Waiting 5s..."
sleep 5

echo "Applying microservices appset (sync wave 0)..."
kubectl apply -f "$(dirname "$0")/../argocd/applicationsets/microservices-appset.yaml"

echo "Waiting 5s..."
sleep 5

echo "Applying platform phase4 apps (database, api-gateway, monitoring, logging)..."
kubectl apply -f "$(dirname "$0")/../argocd/applicationsets/platform-phase4-apps.yaml"

# ── 8. Summary ──
echo ""
echo "============================================="
echo "  ArgoCD Bootstrap — Complete!"
echo "============================================="
echo ""
echo "ArgoCD will now sync all applications from the CD repo."
echo ""
echo "Watch sync status:"
echo "  kubectl get applications -n argocd -w"
echo ""
echo "Expected state:"
echo "  namespaces       → Synced / Healthy"
echo "  gcr-pull-secret  → Synced / Degraded (empty dockerconfigjson until create-gcr-secret.sh runs)"
echo "  users-service    → Synced / Degraded (no db-credentials secret until Phase 4)"
echo "  products-service → Synced / Degraded (no db-credentials secret until Phase 4)"
echo "  orders-service   → Synced / Degraded (no db-credentials secret until Phase 4)"
echo "  frontend         → Synced / Healthy (no DB dependency)"
echo ""
echo "Next step: Run create-gcr-secret.sh to enable image pulling from GCR"

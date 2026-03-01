#!/bin/bash
# =============================================================================
# Create Sealed Secrets for DB Credentials
# =============================================================================
# Fetches the Percona-generated DB credentials, encrypts them using
# kubeseal, and saves them as SealedSecret YAML files in the Helm chart.
#
# These encrypted files are SAFE to commit to Git — only the Sealed Secrets
# controller in the cluster can decrypt them.
#
# Prerequisites:
#   1. Sealed Secrets controller is running (ArgoCD should have synced it)
#   2. Percona PostgreSQL cluster is up and its secret exists
#   3. kubeseal CLI is installed (brew install kubeseal)
#
# Usage: ./create-sealed-secrets.sh
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CD_REPO_ROOT="$(dirname "$SCRIPT_DIR")"
NAMESPACES=("backend-users" "backend-products" "backend-orders")

echo "============================================="
echo "  Creating Sealed Secrets for DB Credentials"
echo "============================================="

# ── 1. Wait for Percona to be ready ──
echo ""
echo "=== Step 1: Waiting for Percona PostgreSQL to be ready ==="
echo "This may take 3-5 minutes on first deploy..."

kubectl wait --for=condition=Ready \
  pod -l postgres-operator.crunchydata.com/role=master \
  -n database \
  --timeout=300s 2>/dev/null || {
    echo "Trying alternative label selector..."
    kubectl wait --for=condition=Ready \
      pod -l app.kubernetes.io/name=percona-db \
      -n database \
      --timeout=300s 2>/dev/null || {
        echo "WARNING: Could not detect ready pod via label selector"
        echo "Checking pod status manually..."
        kubectl get pods -n database
        echo ""
        echo "If pods are Running, continuing anyway..."
    }
}

# ── 2. Fetch DB credentials from Percona secret ──
echo ""
echo "=== Step 2: Fetching DB credentials ==="

# Try the Percona v2 secret naming convention
SECRET_NAME="percona-db-pguser-appuser"
if ! kubectl get secret "$SECRET_NAME" -n database > /dev/null 2>&1; then
  echo "Secret $SECRET_NAME not found, trying alternative..."
  SECRET_NAME=$(kubectl get secrets -n database -o name | grep -i appuser | head -1 | sed 's|secret/||')
  if [ -z "$SECRET_NAME" ]; then
    echo "ERROR: Could not find appuser secret in database namespace"
    echo "Available secrets:"
    kubectl get secrets -n database
    exit 1
  fi
fi

echo "Using secret: $SECRET_NAME"

DB_USER=$(kubectl get secret "$SECRET_NAME" \
  -n database \
  -o jsonpath='{.data.user}' | base64 -d)

DB_PASSWORD=$(kubectl get secret "$SECRET_NAME" \
  -n database \
  -o jsonpath='{.data.password}' | base64 -d)

echo "DB_USER: $DB_USER"
echo "DB_PASSWORD: [hidden — ${#DB_PASSWORD} chars]"

# ── 3. Fetch Sealed Secrets public cert ──
echo ""
echo "=== Step 3: Fetching Sealed Secrets public certificate ==="

kubeseal --fetch-cert \
  --controller-name=sealed-secrets-controller \
  --controller-namespace=sealed-secrets \
  > /tmp/sealed-secrets-pub.pem

echo "Certificate fetched successfully"

# ── 4. Create SealedSecrets for each namespace ──
echo ""
echo "=== Step 4: Creating SealedSecrets ==="

for NS in "${NAMESPACES[@]}"; do
  echo "Creating sealed db-credentials in namespace: $NS"

  # Create plain secret YAML (dry-run — NOT applied to cluster)
  kubectl create secret generic db-credentials \
    --namespace="$NS" \
    --from-literal=username="$DB_USER" \
    --from-literal=password="$DB_PASSWORD" \
    --dry-run=client -o yaml > "/tmp/db-secret-$NS.yaml"

  # Encrypt with kubeseal
  kubeseal \
    --cert /tmp/sealed-secrets-pub.pem \
    --format yaml \
    < "/tmp/db-secret-$NS.yaml" \
    > "$CD_REPO_ROOT/helm/sealed-secrets/templates/sealed-db-$NS.yaml"

  echo "  Created: helm/sealed-secrets/templates/sealed-db-$NS.yaml"
done

# ── 5. Clean up plaintext secrets ──
rm -f /tmp/db-secret-*.yaml /tmp/sealed-secrets-pub.pem
echo ""
echo "Cleaned up plaintext files"

# ── 6. Summary ──
echo ""
echo "============================================="
echo "  Sealed Secrets Created Successfully"
echo "============================================="
echo ""
echo "Files created (safe to commit — they are encrypted):"
for NS in "${NAMESPACES[@]}"; do
  echo "  helm/sealed-secrets/templates/sealed-db-$NS.yaml"
done
echo ""
echo "Next steps:"
echo "  cd $CD_REPO_ROOT"
echo "  git add helm/sealed-secrets/templates/sealed-db-*.yaml"
echo "  git commit -m 'feat: add sealed DB credentials [skip ci]'"
echo "  git push origin HU-DEVOPS-26-yourname"
echo ""
echo "ArgoCD will apply them and the Sealed Secrets controller"
echo "will decrypt and create real K8s Secrets automatically."
echo "Backend pods will then restart and connect to PostgreSQL."

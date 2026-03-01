#!/bin/bash
# =============================================================================
# GCR Pull Secret Creator
# =============================================================================
# Creates imagePullSecret in all app namespaces so Kubernetes can pull
# Docker images from Google Container Registry (GCR).
#
# Usage: ./create-gcr-secret.sh <path-to-gcr-key.json> [gcp-project-id]
# Example: ./create-gcr-secret.sh ./gcr-key.json eks-assignment-01
#
# The GCR key JSON file is the service account key from Terraform output:
#   terraform output -raw gcr_service_account_key | base64 -d > gcr-key.json
# =============================================================================

set -euo pipefail

GCR_KEY_FILE=${1:-""}
GCP_PROJECT_ID=${2:-${GCP_PROJECT_ID:-""}}

if [ -z "$GCR_KEY_FILE" ]; then
  echo "Usage: ./create-gcr-secret.sh <path-to-gcr-key.json> [gcp-project-id]"
  echo ""
  echo "To get the key file from Terraform output:"
  echo "  cd terraform/environments/dev"
  echo "  terraform output -raw gcr_service_account_key | base64 -d > gcr-key.json"
  exit 1
fi

if [ ! -f "$GCR_KEY_FILE" ]; then
  echo "ERROR: File not found: $GCR_KEY_FILE"
  exit 1
fi

NAMESPACES=("frontend" "backend-users" "backend-products" "backend-orders")

echo "============================================="
echo "  Creating GCR Pull Secrets"
echo "============================================="

for NS in "${NAMESPACES[@]}"; do
  echo "Creating gcr-pull-secret in namespace: $NS"

  # Ensure namespace exists
  kubectl get namespace "$NS" > /dev/null 2>&1 || {
    echo "  WARNING: Namespace $NS does not exist yet — creating it"
    kubectl create namespace "$NS"
  }

  kubectl create secret docker-registry gcr-pull-secret \
    --docker-server=gcr.io \
    --docker-username=_json_key \
    --docker-password="$(cat "$GCR_KEY_FILE")" \
    --docker-email=ci@eks-assignment.com \
    --namespace="$NS" \
    --dry-run=client -o yaml | kubectl apply -f -

  echo "  Done"
done

echo ""
echo "============================================="
echo "  GCR Pull Secrets — Created Successfully"
echo "============================================="
echo ""
echo "Secrets created in: ${NAMESPACES[*]}"
echo ""
echo "Verify with:"
echo "  kubectl get secret gcr-pull-secret -n frontend"
echo "  kubectl get secret gcr-pull-secret -n backend-users"
echo "  kubectl get secret gcr-pull-secret -n backend-products"
echo "  kubectl get secret gcr-pull-secret -n backend-orders"
echo ""
echo "Test image pull:"
echo "  kubectl run test --image=gcr.io/${GCP_PROJECT_ID}/frontend:latest -n frontend --rm -it --restart=Never -- echo 'Pull OK'"

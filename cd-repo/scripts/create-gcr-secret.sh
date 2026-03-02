#!/bin/bash
# =============================================================================
# ECR Pull Secret — NOT NEEDED
# =============================================================================
# With AWS ECR, EKS nodes already have the AmazonEC2ContainerRegistryReadOnly
# IAM policy attached, so they can pull images from ECR natively.
#
# No imagePullSecret is required.
# This script is kept for reference only.
# =============================================================================

echo "============================================="
echo "  ECR Pull Secrets — NOT NEEDED"
echo "============================================="
echo ""
echo "EKS nodes have the AmazonEC2ContainerRegistryReadOnly IAM policy."
echo "They can pull from ECR natively without imagePullSecrets."
echo ""
echo "Verify nodes can pull by checking pod status:"
echo "  kubectl get pods -n frontend"
echo "  kubectl get pods -n backend-users"

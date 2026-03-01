#!/bin/bash
set -euxo pipefail

# =============================================================================
# Bastion User Data Script
# Installs: kubectl, helm, awscli v2, git; configures kubeconfig
# =============================================================================

# Update system packages
dnf update -y

# Install git
dnf install -y git

# ---------- AWS CLI v2 ----------
# Amazon Linux 2023 ships with AWS CLI v2 pre-installed, but ensure latest
dnf install -y aws-cli || true

# ---------- kubectl ----------
curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
chmod +x kubectl
mv kubectl /usr/local/bin/kubectl

# ---------- helm ----------
curl -fsSL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash

# ---------- Configure kubeconfig for the EKS cluster ----------
mkdir -p /home/ec2-user/.kube
aws eks update-kubeconfig \
  --name "${cluster_name}" \
  --region "${aws_region}" \
  --kubeconfig /home/ec2-user/.kube/config

chown -R ec2-user:ec2-user /home/ec2-user/.kube

echo "Bastion setup complete. kubectl, helm, awscli v2, and git installed."
echo "Kubeconfig configured for cluster: ${cluster_name}"

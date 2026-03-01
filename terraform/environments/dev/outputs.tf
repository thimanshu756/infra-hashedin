# =============================================================================
# Outputs — Dev Environment
# =============================================================================

# --- VPC ---
output "vpc_id" {
  description = "ID of the VPC"
  value       = module.vpc.vpc_id
}

output "public_subnet_id" {
  description = "ID of the public subnet"
  value       = module.vpc.public_subnet_id
}

output "private_subnet_ids" {
  description = "IDs of the private subnets"
  value       = module.vpc.private_subnet_ids
}

# --- EKS ---
output "eks_cluster_name" {
  description = "Name of the EKS cluster"
  value       = module.eks.cluster_name
}

output "eks_cluster_endpoint" {
  description = "Endpoint URL of the EKS cluster"
  value       = module.eks.cluster_endpoint
}

output "eks_cluster_arn" {
  description = "ARN of the EKS cluster"
  value       = module.eks.cluster_arn
}

output "eks_oidc_provider_arn" {
  description = "ARN of the EKS OIDC provider (needed for IRSA in later phases)"
  value       = module.eks.oidc_provider_arn
}

# --- Bastion ---
output "bastion_instance_id" {
  description = "ID of the bastion EC2 instance"
  value       = module.bastion.instance_id
}

output "bastion_ssm_command" {
  description = "AWS SSM command to connect to the bastion"
  value       = module.bastion.ssm_command
}

# --- GitHub Actions ---
output "github_actions_role_arn" {
  description = "ARN of the IAM role for GitHub Actions"
  value       = module.oidc_github.github_actions_role_arn
}

# --- GCR ---
output "gcr_service_account_email" {
  description = "Email of the GCR pusher service account"
  value       = module.gcr.service_account_email
}

output "gcr_workload_identity_provider" {
  description = "Workload Identity Provider for GitHub Actions GCP OIDC"
  value       = module.gcr.workload_identity_provider
}

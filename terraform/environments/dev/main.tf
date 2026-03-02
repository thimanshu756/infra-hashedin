# =============================================================================
# Dev Environment — Root Configuration
# =============================================================================
# Calls all modules to provision the complete Phase 1 infrastructure.
# Fill in terraform.tfvars with your account-specific values.
# =============================================================================

terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    tls = {
      source  = "hashicorp/tls"
      version = "~> 4.0"
    }
  }
}

# -----------------------------------------------------------------------------
# Providers
# -----------------------------------------------------------------------------
provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project     = var.project_name
      Environment = var.environment
      Owner       = var.owner
      ManagedBy   = "terraform"
    }
  }
}

# NOTE: Kubernetes provider removed — EKS managed node groups automatically
# handle aws-auth ConfigMap. The private endpoint is unreachable from outside
# the VPC. Use the bastion host for kubectl operations after deployment.

# -----------------------------------------------------------------------------
# Data Sources
# -----------------------------------------------------------------------------
data "aws_caller_identity" "current" {}

# -----------------------------------------------------------------------------
# VPC Module
# -----------------------------------------------------------------------------
module "vpc" {
  source = "../../modules/vpc"

  project_name         = var.project_name
  environment          = var.environment
  owner                = var.owner
  vpc_cidr             = var.vpc_cidr
  public_subnet_cidr   = var.public_subnet_cidr
  private_subnet_cidrs = var.private_subnet_cidrs
  availability_zones   = var.availability_zones
}

# -----------------------------------------------------------------------------
# EKS Module
# -----------------------------------------------------------------------------
module "eks" {
  source = "../../modules/eks"

  project_name       = var.project_name
  environment        = var.environment
  owner              = var.owner
  cluster_name       = var.cluster_name
  kubernetes_version = var.kubernetes_version
  vpc_id             = module.vpc.vpc_id
  private_subnet_ids = module.vpc.private_subnet_ids
  node_instance_type = var.node_instance_type
  node_desired_count = var.node_desired_count
  node_min_count     = var.node_min_count
  node_max_count     = var.node_max_count
}

# -----------------------------------------------------------------------------
# EC2 Bastion Module
# -----------------------------------------------------------------------------
module "bastion" {
  source = "../../modules/ec2-bastion"

  project_name     = var.project_name
  environment      = var.environment
  owner            = var.owner
  vpc_id           = module.vpc.vpc_id
  subnet_id        = module.vpc.private_subnet_ids[0]
  eks_cluster_name = module.eks.cluster_name
  aws_region       = var.aws_region
}

# -----------------------------------------------------------------------------
# OIDC GitHub Actions Module
# -----------------------------------------------------------------------------
module "oidc_github" {
  source = "../../modules/oidc-github"

  project_name  = var.project_name
  environment   = var.environment
  owner         = var.owner
  github_org    = var.github_org
  github_repo   = var.github_repo
  github_branch = var.github_branch
}

# -----------------------------------------------------------------------------
# ECR Module — Container Registry for microservice images
# -----------------------------------------------------------------------------
module "ecr" {
  source = "../../modules/ecr"

  project_name = var.project_name
  environment  = var.environment
  owner        = var.owner
}

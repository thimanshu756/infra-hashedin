# =============================================================================
# OIDC GitHub Actions Module
# =============================================================================
# Creates: GitHub Actions OIDC provider + IAM role for CI/CD pipeline
# This allows GitHub Actions to assume an AWS role without stored credentials.
# Supports multiple branches (IAC-DAY1 for Terraform, app branch for CI).
# =============================================================================

locals {
  common_tags = {
    Project     = var.project_name
    Environment = var.environment
    Owner       = var.owner
    ManagedBy   = "terraform"
  }
}

# -----------------------------------------------------------------------------
# GitHub Actions OIDC Provider
# -----------------------------------------------------------------------------
resource "aws_iam_openid_connect_provider" "github" {
  url = "https://token.actions.githubusercontent.com"

  client_id_list = ["sts.amazonaws.com"]

  # GitHub's OIDC thumbprint
  thumbprint_list = ["6938fd4d98bab03faadb97b34396831e3780aea1"]

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-${var.environment}-github-oidc"
  })
}

# -----------------------------------------------------------------------------
# IAM Role for GitHub Actions
# -----------------------------------------------------------------------------
# Allows all branches in the repo to assume this role.
# Both IAC-DAY1 (Terraform) and HU-DevOps-26-highai (CI) need access.
resource "aws_iam_role" "github_actions" {
  name = "${var.project_name}-${var.environment}-github-actions-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Federated = aws_iam_openid_connect_provider.github.arn
        }
        Action = "sts:AssumeRoleWithWebIdentity"
        Condition = {
          StringEquals = {
            "token.actions.githubusercontent.com:aud" = "sts.amazonaws.com"
          }
          StringLike = {
            "token.actions.githubusercontent.com:sub" = "repo:${var.github_org}/${var.github_repo}:*"
          }
        }
      }
    ]
  })

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-${var.environment}-github-actions-role"
  })
}

# -----------------------------------------------------------------------------
# Policy Attachments — Infrastructure management
# -----------------------------------------------------------------------------
resource "aws_iam_role_policy_attachment" "github_eks" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
  role       = aws_iam_role.github_actions.name
}

resource "aws_iam_role_policy_attachment" "github_ec2" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2FullAccess"
  role       = aws_iam_role.github_actions.name
}

resource "aws_iam_role_policy_attachment" "github_iam" {
  policy_arn = "arn:aws:iam::aws:policy/IAMFullAccess"
  role       = aws_iam_role.github_actions.name
}

resource "aws_iam_role_policy_attachment" "github_s3" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonS3FullAccess"
  role       = aws_iam_role.github_actions.name
}

resource "aws_iam_role_policy_attachment" "github_dynamodb" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonDynamoDBFullAccess"
  role       = aws_iam_role.github_actions.name
}

# -----------------------------------------------------------------------------
# Policy Attachment — ECR push/pull for CI pipeline
# -----------------------------------------------------------------------------
resource "aws_iam_role_policy_attachment" "github_ecr" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryPowerUser"
  role       = aws_iam_role.github_actions.name
}

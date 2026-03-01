You are a senior DevOps engineer. I need you to build a complete, 
production-grade, modular Terraform codebase for Phase 1 of an AWS EKS 
assignment. Everything must be modular, DRY, and easily migratable between 
AWS accounts (personal → company).

═══════════════════════════════════════════════
CONTEXT
═══════════════════════════════════════════════

This is Phase 1 of a larger platform. Later phases will add:
- ArgoCD + Helm (GitOps CD)
- Kong Gateway API
- Percona PostgreSQL Operator
- Prometheus + Grafana + Loki + Tempo
- Kyverno + Sealed Secrets + NetworkPolicies
- Linkerd service mesh
- KEDA autoscaling

So design the Terraform with extensibility in mind.

═══════════════════════════════════════════════
STRICT REQUIREMENTS
═══════════════════════════════════════════════

1. EVERYTHING provisioned via Terraform — zero manual AWS console clicks
2. Modular structure — each component is a separate module
3. Remote backend — S3 + DynamoDB state locking (must be bootstrapped first)
4. Terraform plan/apply must work via GitHub Actions pipeline (OIDC auth — NO stored AWS keys)
5. All sensitive values via variables — no hardcoded account IDs, keys, or passwords
6. Every resource must have Name tags and common tags (environment, project, owner)
7. GCR prerequisites on GCP side must also be provisioned via Terraform

═══════════════════════════════════════════════
EXACT INFRASTRUCTURE TO BUILD
═══════════════════════════════════════════════

── REMOTE BACKEND (bootstrap — applied first, separately) ──
- S3 bucket for Terraform state
  - versioning enabled
  - server-side encryption (AES256)
  - public access blocked
- DynamoDB table for state locking
  - billing mode: PAY_PER_REQUEST
  - hash key: LockID

── VPC ──
- CIDR: 10.0.0.0/16
- 1 public subnet (10.0.1.0/24) in AZ-a
- 2 private subnets (10.0.2.0/24, 10.0.3.0/24) in AZ-a and AZ-b
- Internet Gateway attached to VPC
- NAT Gateway in public subnet (single NAT — cost optimized for dev)
- Elastic IP for NAT Gateway
- Route table for public subnet → IGW
- Route table for private subnets → NAT Gateway
- Route table associations for all subnets
- VPC Flow Logs (optional but good practice)

── EKS CLUSTER ──
- Private cluster (API endpoint: private only — not public-facing)
- Kubernetes version: 1.29
- Cluster IAM role with AmazonEKSClusterPolicy
- Node group:
  - 2 nodes (desired: 2, min: 2, max: 3)
  - Instance type: t2.medium
  - Disk: 20GB gp2
  - Nodes in PRIVATE subnets only
  - Node IAM role with:
    - AmazonEKSWorkerNodePolicy
    - AmazonEC2ContainerRegistryReadOnly
    - AmazonEKS_CNI_Policy
- Cluster add-ons (declared in Terraform):
  - vpc-cni
  - coredns
  - kube-proxy
- Security groups:
  - Cluster SG: allow worker nodes to communicate with control plane
  - Node SG: allow node-to-node, node-to-control-plane communication
- OIDC provider for the EKS cluster (needed for IRSA later)
- aws-auth ConfigMap: map node IAM role to system:nodes group

── EC2 BASTION ──
- Amazon Linux 2023 AMI (latest, fetched via data source)
- Instance type: t2.micro
- Placed in PRIVATE subnet (NOT public)
- IAM instance profile with SSM policy (aws ssm start-session — no SSH key needed)
- Security group: allow outbound only (no inbound from internet)
- User data script:
  - Install kubectl
  - Install helm
  - Install awscli v2
  - Install git
  - Configure kubeconfig for the EKS cluster
- EBS volume: 8GB gp2, encrypted

── OIDC FOR GITHUB ACTIONS (AWS side) ──
- aws_iam_openid_connect_provider for GitHub Actions
  (url: https://token.actions.githubusercontent.com)
- IAM role: github-actions-role
  - Trust policy: only allow YOUR GitHub repo + branch
  - Condition on sub: repo:YOUR_ORG/YOUR_REPO:ref:refs/heads/IAC-DAY1
- Attach policies to the role:
  - AmazonEKSClusterPolicy
  - AmazonEC2FullAccess (for VPC/SG management)
  - IAMFullAccess (for creating roles)
  - AmazonS3FullAccess (for state bucket)
  - AmazonDynamoDBFullAccess (for state locking)

── GCR PREREQUISITES (GCP side via Terraform google provider) ──
- Google provider configured (project, region as variables)
- Enable APIs:
  - containerregistry.googleapis.com
  - iam.googleapis.com
  - storage.googleapis.com
- GCP Service Account: eks-gcr-pusher
  - Role: roles/storage.admin (GCR uses GCS internally)
- Service account key generated and output as sensitive value
- Workload Identity Pool + Provider for GitHub Actions OIDC
  (so GitHub Actions can push to GCR without JSON key)

═══════════════════════════════════════════════
EXACT FOLDER STRUCTURE TO CREATE
═══════════════════════════════════════════════

terraform/
├── bootstrap/                    ← Apply this FIRST (creates S3 + DynamoDB)
│   ├── main.tf
│   ├── variables.tf
│   └── outputs.tf
│
├── modules/
│   ├── vpc/
│   │   ├── main.tf
│   │   ├── variables.tf
│   │   └── outputs.tf
│   ├── eks/
│   │   ├── main.tf
│   │   ├── variables.tf
│   │   └── outputs.tf
│   ├── ec2-bastion/
│   │   ├── main.tf
│   │   ├── variables.tf
│   │   └── outputs.tf
│   ├── oidc-github/
│   │   ├── main.tf
│   │   ├── variables.tf
│   │   └── outputs.tf
│   └── gcr/
│       ├── main.tf
│       ├── variables.tf
│       └── outputs.tf
│
├── environments/
│   └── dev/                      ← Personal AWS account (current)
│       ├── main.tf               ← Calls all modules
│       ├── variables.tf
│       ├── outputs.tf
│       ├── terraform.tfvars      ← Personal account values (gitignored)
│       ├── terraform.tfvars.example  ← Template (committed to git)
│       └── backend.tf            ← Points to S3 remote backend
│
└── .github/
    └── workflows/
        └── terraform.yml         ← GitHub Actions Terraform pipeline

═══════════════════════════════════════════════
VARIABLES THAT MUST BE CONFIGURABLE
═══════════════════════════════════════════════

These allow easy migration from personal → company AWS account:

# AWS
aws_region          = "eu-west-1"
aws_account_id      = ""           # Never hardcode
project_name        = "eks-assignment"
environment         = "dev"
owner               = "your-name"

# VPC
vpc_cidr            = "10.0.0.0/16"
public_subnet_cidr  = "10.0.1.0/24"
private_subnet_cidrs = ["10.0.2.0/24", "10.0.3.0/24"]
availability_zones  = ["eu-west-1a", "eu-west-1b"]

# EKS
cluster_name        = "eks-assignment-cluster"
kubernetes_version  = "1.29"
node_instance_type  = "t2.medium"
node_desired_count  = 2
node_min_count      = 2
node_max_count      = 3

# GitHub OIDC
github_org          = ""
github_repo         = ""
github_branch       = "IAC-DAY1"

# GCP
gcp_project_id      = ""
gcp_region          = "us-central1"

═══════════════════════════════════════════════
GITHUB ACTIONS TERRAFORM PIPELINE REQUIREMENTS
═══════════════════════════════════════════════

File: .github/workflows/terraform.yml

Triggers:
- push to IAC-DAY1 branch → runs terraform apply
- pull_request to IAC-DAY1 branch → runs terraform plan only

Steps:
1. Checkout code
2. Configure AWS credentials using OIDC 
   (aws-actions/configure-aws-credentials@v4, role-to-assume from secret)
3. Setup Terraform (hashicorp/setup-terraform@v3)
4. terraform init (with backend config)
5. terraform fmt -check
6. terraform validate
7. terraform plan (always)
8. terraform apply -auto-approve (only on push to IAC-DAY1, not on PR)
9. On PR: post terraform plan output as PR comment

Environment variables needed (GitHub Secrets):
- AWS_ROLE_ARN (the github-actions-role ARN from OIDC module output)
- GCP_PROJECT_ID
- TF_VAR_github_org
- TF_VAR_github_repo

═══════════════════════════════════════════════
OUTPUTS REQUIRED
═══════════════════════════════════════════════

From environments/dev/outputs.tf, expose:
- vpc_id
- public_subnet_id
- private_subnet_ids
- eks_cluster_name
- eks_cluster_endpoint
- eks_cluster_arn
- eks_oidc_provider_arn      ← needed for IRSA in later phases
- bastion_instance_id
- bastion_ssm_command        ← print the exact aws ssm start-session command
- github_actions_role_arn
- gcr_service_account_email
- gcr_workload_identity_provider  ← for GitHub Actions GCP OIDC

═══════════════════════════════════════════════
IMPORTANT NOTES
═══════════════════════════════════════════════

1. bootstrap/ has its OWN backend (local state) because S3 doesn't exist yet
   when bootstrap runs. All other modules use remote S3 backend.

2. Use data sources wherever possible:
   - aws_availability_zones (don't hardcode AZ names)
   - aws_ami for latest Amazon Linux 2023
   - aws_caller_identity for account ID

3. Add lifecycle { prevent_destroy = true } on:
   - S3 state bucket
   - DynamoDB lock table
   - EKS cluster

4. All modules must have a README.md explaining:
   - What the module creates
   - Required inputs
   - Outputs
   - How to use it

5. terraform.tfvars must be in .gitignore
   terraform.tfvars.example must be committed with placeholder values

6. Use consistent tagging on every resource:
   tags = {
     Project     = var.project_name
     Environment = var.environment
     Owner       = var.owner
     ManagedBy   = "terraform"
   }

7. The EKS cluster endpoint access:
   - endpoint_private_access = true
   - endpoint_public_access  = false
   This means kubectl only works from INSIDE the VPC (bastion or pipeline)

8. For the Terraform pipeline to run terraform apply on a private EKS cluster,
   the GitHub Actions runner needs VPC access. Handle this by:
   - Using a self-hosted runner on the bastion (preferred), OR
   - Making endpoint_public_access = true temporarily with IP restriction
   Note this constraint clearly in comments.

═══════════════════════════════════════════════
GENERATE ALL FILES WITH COMPLETE CODE
═══════════════════════════════════════════════

Generate every file completely — no placeholders, no "add your logic here" 
comments. Every .tf file must be immediately runnable after filling in 
terraform.tfvars values.

Start with:
1. bootstrap/
2. modules/ (all 5 modules)
3. environments/dev/
4. .github/workflows/terraform.yml

After generating all files, provide:
- The exact order to run commands (bootstrap first, then dev)
- The exact commands to run
- How to verify each component after apply

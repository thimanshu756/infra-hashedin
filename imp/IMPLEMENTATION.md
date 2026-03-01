# Implementation Guide — EKS Assignment (Phase 1 + Phase 2)

Complete setup guide for a new DevOps engineer starting from scratch.

---

## Prerequisites

| Tool | Install |
|---|---|
| Terraform >= 1.5 | `brew install terraform` |
| AWS CLI v2 | `brew install awscli` |
| Google Cloud SDK | `brew install --cask google-cloud-sdk` |
| Docker + Docker Compose | `brew install --cask docker` |
| kubectl | `brew install kubectl` |
| Git | `brew install git` |

---

## 1. AWS Account Setup

### 1.1 Create IAM User

```bash
# Login to AWS Console > IAM > Users > Create User
# Attach these managed policies:
```

| Policy | Purpose |
|---|---|
| AmazonEC2FullAccess | VPC, subnets, NAT, bastion |
| AmazonS3FullAccess | Terraform state bucket |
| AmazonDynamoDBFullAccess | Terraform state locking |
| IAMFullAccess | Roles, OIDC providers |
| CloudWatchLogsFullAccess | VPC flow logs |

Add this inline policy for EKS:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": "eks:*",
      "Resource": "*"
    },
    {
      "Effect": "Allow",
      "Action": "iam:PassRole",
      "Resource": "*",
      "Condition": {
        "StringEquals": {
          "iam:PassedToService": ["eks.amazonaws.com", "ec2.amazonaws.com"]
        }
      }
    }
  ]
}
```

### 1.2 Configure AWS CLI

```bash
aws configure
# Access Key ID:     <from IAM user>
# Secret Access Key: <from IAM user>
# Region:            eu-west-1
# Output format:     json
```

### 1.3 Verify

```bash
aws sts get-caller-identity
# Should return your account ID, ARN, and user ID
```

---

## 2. GCP Account Setup

### 2.1 Install and Login

```bash
gcloud auth login
```

### 2.2 Create Project (or use existing)

```bash
gcloud projects create YOUR_PROJECT_ID --name="EKS Assignment"
gcloud config set project YOUR_PROJECT_ID
```

### 2.3 Link Billing

```bash
gcloud billing accounts list
gcloud billing projects link YOUR_PROJECT_ID --billing-account=BILLING_ACCOUNT_ID
```

### 2.4 Enable Base APIs

```bash
gcloud services enable cloudresourcemanager.googleapis.com
gcloud services enable iam.googleapis.com
gcloud services enable sts.googleapis.com
gcloud services enable iamcredentials.googleapis.com
gcloud services enable containerregistry.googleapis.com
gcloud services enable storage.googleapis.com
```

### 2.5 Set Application Default Credentials

```bash
gcloud auth application-default login
```

### 2.6 Verify

```bash
gcloud config get-value project
gcloud auth application-default print-access-token
```

---

## 3. Terraform — Bootstrap (Remote State Backend)

This creates the S3 bucket and DynamoDB table for Terraform state. Uses local state.

```bash
cd terraform/bootstrap

terraform init

# Get your account ID
aws sts get-caller-identity --query Account --output text

terraform apply \
  -var="aws_account_id=YOUR_ACCOUNT_ID" \
  -var="owner=your-name"
```

Note the output `state_bucket_name` — you need it next.

---

## 4. Terraform — Configure Dev Environment

### 4.1 Update Backend Config

Edit `terraform/environments/dev/backend.tf`:

```hcl
terraform {
  backend "s3" {
    bucket         = "eks-assignment-dev-tfstate-YOUR_ACCOUNT_ID"  # <-- update this
    key            = "environments/dev/terraform.tfstate"
    region         = "eu-west-1"
    dynamodb_table = "eks-assignment-dev-tflock"
    encrypt        = true
  }
}
```

### 4.2 Create terraform.tfvars

```bash
cd terraform/environments/dev
cp terraform.tfvars.example terraform.tfvars
```

Edit `terraform.tfvars` — fill in all values:

```hcl
aws_account_id = "YOUR_ACCOUNT_ID"
owner          = "your-name"
github_org     = "your-github-username"
github_repo    = "your-repo-name"
gcp_project_id = "your-gcp-project-id"
```

For production accounts, update instance types:
```hcl
node_instance_type = "t2.medium"   # Free Tier accounts: use "t3.micro"
```

---

## 5. Terraform — Apply Infrastructure

```bash
cd terraform/environments/dev

terraform init
terraform plan
terraform apply
```

Takes ~15-20 minutes (EKS cluster creation is slow).

### Expected Outputs

| Output | Description |
|---|---|
| `vpc_id` | VPC ID |
| `eks_cluster_name` | EKS cluster name |
| `eks_cluster_endpoint` | Cluster API endpoint (private) |
| `bastion_instance_id` | Bastion EC2 instance ID |
| `bastion_ssm_command` | Ready-to-use SSM connect command |
| `github_actions_role_arn` | IAM role ARN for GitHub Actions |
| `gcr_service_account_email` | GCP service account for GCR |
| `gcr_workload_identity_provider` | GCP Workload Identity for CI/CD |

---

## 6. Verify Infrastructure

### 6.1 VPC

```bash
aws ec2 describe-vpcs \
  --filters "Name=tag:Project,Values=eks-assignment" \
  --query "Vpcs[].{ID:VpcId,CIDR:CidrBlock}" --output table
```

### 6.2 EKS Cluster

```bash
aws eks describe-cluster --name eks-assignment-cluster \
  --query "cluster.{Status:status,Version:version}" --output table
```

### 6.3 Node Group

```bash
aws eks list-nodegroups --cluster-name eks-assignment-cluster
```

### 6.4 Bastion (connect via SSM)

```bash
# Get the command from terraform output
terraform output bastion_ssm_command

# Or directly:
aws ssm start-session --target INSTANCE_ID --region eu-west-1
```

### 6.5 kubectl (from bastion)

```bash
# After SSM into bastion:
kubectl get nodes
kubectl get pods -A
```

---

## 7. Run Microservices Locally (Phase 2)

### 7.1 Start All Services

```bash
cd app
docker-compose up --build
```

### 7.2 Verify Health

```bash
curl http://localhost:5001/health   # users-service
curl http://localhost:5002/health   # products-service
curl http://localhost:5003/health   # orders-service
curl http://localhost:3000/health   # frontend
```

### 7.3 Test CRUD

```bash
# Create user
curl -X POST http://localhost:5001/users \
  -H "Content-Type: application/json" \
  -d '{"name":"John","email":"john@test.com","role":"admin"}'

# List users
curl http://localhost:5001/users

# Create product
curl -X POST http://localhost:5002/products \
  -H "Content-Type: application/json" \
  -d '{"name":"Laptop","price":999.99,"category":"electronics"}'

# Create order
curl -X POST http://localhost:5003/orders \
  -H "Content-Type: application/json" \
  -d '{"user_id":1,"product_id":1,"quantity":2}'

# Update order status
curl -X PUT http://localhost:5003/orders/1 \
  -H "Content-Type: application/json" \
  -d '{"status":"completed"}'

# Delete user
curl -X DELETE http://localhost:5001/users/1
```

### 7.4 Frontend Dashboard

Open `http://localhost:3000` — 3 tabs: Users, Products, Orders with full CRUD.

### 7.5 Verify Non-Root Containers

```bash
docker compose run --rm users-service whoami
# Must print: appuser
```

### 7.6 Stop Services

```bash
docker-compose down
# To also remove data volumes:
docker-compose down -v
```

---

## 8. GitHub Actions CI/CD Setup

### 8.1 Create GitHub Repository

```bash
cd /path/to/project
git init
git add .
git commit -m "Initial commit: Phase 1 + Phase 2"
git branch -M IAC-DAY1
git remote add origin git@github.com:YOUR_ORG/YOUR_REPO.git
git push -u origin IAC-DAY1
```

### 8.2 Add GitHub Secrets

Go to GitHub repo > Settings > Secrets and variables > Actions. Add:

| Secret | Value |
|---|---|
| `AWS_ROLE_ARN` | `terraform output github_actions_role_arn` |
| `AWS_ACCOUNT_ID` | Your AWS account ID |
| `GCP_PROJECT_ID` | Your GCP project ID |
| `TF_VAR_github_org` | Your GitHub org/username |
| `TF_VAR_github_repo` | Your repo name |
| `TF_VAR_owner` | Resource owner name |

### 8.3 Pipeline Behavior

| Trigger | Action |
|---|---|
| Push to `IAC-DAY1` | `terraform plan` + `terraform apply` |
| PR to `IAC-DAY1` | `terraform plan` only + PR comment |

---

## 9. Teardown (Destroy Everything)

**Order matters — destroy in reverse.**

### 9.1 Destroy Dev Infrastructure

```bash
cd terraform/environments/dev
terraform destroy
```

Note: EKS cluster has `prevent_destroy = true`. To destroy, first remove the lifecycle block from `terraform/modules/eks/main.tf`, then run destroy again.

### 9.2 Destroy Bootstrap

```bash
cd terraform/bootstrap
terraform destroy \
  -var="aws_account_id=YOUR_ACCOUNT_ID" \
  -var="owner=your-name"
```

Note: S3 bucket and DynamoDB table have `prevent_destroy = true`. Remove the lifecycle blocks first if you want to destroy them.

### 9.3 Clean Up Docker

```bash
cd app
docker-compose down -v
docker system prune -a
```

---

## Architecture Reference

```
                  ┌─────────────────────────────────────────┐
                  │              AWS (eu-west-1)             │
                  │                                         │
                  │  ┌──────────── VPC 10.0.0.0/16 ───────┐ │
                  │  │                                     │ │
                  │  │  Public Subnet (10.0.1.0/24)        │ │
                  │  │  ├── Internet Gateway               │ │
                  │  │  └── NAT Gateway + EIP              │ │
                  │  │                                     │ │
                  │  │  Private Subnet A (10.0.2.0/24)     │ │
                  │  │  ├── EKS Worker Node 1              │ │
                  │  │  └── Bastion Host (SSM)             │ │
                  │  │                                     │ │
                  │  │  Private Subnet B (10.0.3.0/24)     │ │
                  │  │  └── EKS Worker Node 2              │ │
                  │  │                                     │ │
                  │  │  EKS Control Plane (private API)    │ │
                  │  └─────────────────────────────────────┘ │
                  │                                         │
                  │  IAM: OIDC GitHub Actions Role          │
                  │  S3:  Terraform State Bucket            │
                  │  DDB: Terraform Lock Table              │
                  └─────────────────────────────────────────┘

                  ┌─────────────────────────────────────────┐
                  │              GCP                         │
                  │  Service Account: eks-gcr-pusher         │
                  │  Workload Identity: GitHub Actions OIDC  │
                  │  GCR: Container Registry                 │
                  └─────────────────────────────────────────┘

                  ┌─────────────────────────────────────────┐
                  │         Microservices (Docker)           │
                  │  ┌─────────┐ ┌──────────┐ ┌──────────┐  │
                  │  │ users   │ │ products │ │ orders   │  │
                  │  │ :5000   │ │ :5000    │ │ :5000    │  │
                  │  └────┬────┘ └────┬─────┘ └────┬─────┘  │
                  │       └───────────┼────────────┘        │
                  │              PostgreSQL                  │
                  │              (appdb)                     │
                  │                                         │
                  │  ┌──────────┐                            │
                  │  │ frontend │                            │
                  │  │ :3000    │                            │
                  │  └──────────┘                            │
                  └─────────────────────────────────────────┘
```

---

## Migrating to a New AWS Account

1. Run bootstrap with new account ID
2. Update `backend.tf` bucket name with new account ID
3. Update `terraform.tfvars` with new account values
4. Run `terraform init` (migrates state to new bucket)
5. Run `terraform apply`

No code changes needed — only variable values change.

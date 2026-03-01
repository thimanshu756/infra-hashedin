Phase 1 Complete — File Structure

terraform/
├── bootstrap/              (S3 + DynamoDB — local state)
├── modules/
│   ├── vpc/                (VPC, subnets, IGW, NAT, flow logs)
│   ├── eks/                (EKS cluster, nodes, OIDC, add-ons, aws-auth)
│   ├── ec2-bastion/        (private bastion with SSM, kubectl, helm)
│   ├── oidc-github/        (GitHub Actions OIDC + IAM role)
│   └── gcr/                (GCP APIs, service account, Workload Identity)
├── environments/dev/       (root config calling all modules)
└── .github/workflows/      (CI/CD pipeline)
Deployment Order
Step 1: Bootstrap (creates remote state backend)

cd terraform/bootstrap
terraform init
terraform plan -var="aws_account_id=YOUR_ACCOUNT_ID" -var="owner=your-name"
terraform apply -var="aws_account_id=YOUR_ACCOUNT_ID" -var="owner=your-name"
Step 2: Update backend config
Edit backend.tf — replace ACCOUNT_ID in the bucket name with your actual AWS account ID.

Step 3: Create terraform.tfvars

cd terraform/environments/dev
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars with your actual values
Step 4: Apply infrastructure

cd terraform/environments/dev
terraform init
terraform plan
terraform apply
Verification After Apply
Component	Verification Command
VPC	aws ec2 describe-vpcs --filters "Name=tag:Project,Values=eks-assignment"
EKS	aws eks describe-cluster --name eks-assignment-cluster
Nodes	aws eks list-nodegroups --cluster-name eks-assignment-cluster
Bastion	aws ssm start-session --target <bastion-instance-id>
kubectl (from bastion)	kubectl get nodes
OIDC	aws iam list-open-id-connect-providers
GitHub Secrets Required
Set these in your repo's Settings > Secrets:

AWS_ROLE_ARN — from github_actions_role_arn output
AWS_ACCOUNT_ID — your AWS account ID
GCP_PROJECT_ID — your GCP project ID
TF_VAR_github_org — your GitHub org/username
TF_VAR_github_repo — your repo name
TF_VAR_owner — resource owner name
cd terraform/bootstrap
terraform init
terraform plan -var="aws_account_id=YOUR_ACCOUNT_ID" -var="owner=your-name"
terraform apply -var="aws_account_id=YOUR_ACCOUNT_ID" -var="owner=your-name"


when i will run this in the terminal how thw authentication and authorisation is happening ?
Good question. When you run terraform init and terraform apply locally in the bootstrap directory, Terraform uses the AWS credentials configured on your local machine. There is no OIDC or GitHub Actions involved at this stage — that's only for CI/CD later.

How Local Authentication Works
Terraform's AWS provider looks for credentials in this order (first match wins):

1. Environment Variables (most common for dev)

export AWS_ACCESS_KEY_ID="your-access-key"
export AWS_SECRET_ACCESS_KEY="your-secret-key"
export AWS_REGION="eu-west-1"
2. AWS CLI Profile (~/.aws/credentials)

# First configure it:
aws configure

# This creates ~/.aws/credentials with your keys
# Terraform automatically picks it up
3. Named Profile (if you have multiple AWS accounts)

export AWS_PROFILE="personal"
# or
aws configure --profile personal
What You Actually Need To Do Before Running Bootstrap
Option A — AWS CLI (recommended):


aws configure
# Enter: Access Key ID, Secret Access Key, Region (eu-west-1), Output format (json)

# Verify it works:
aws sts get-caller-identity
Option B — Environment variables:


export AWS_ACCESS_KEY_ID="AKIA..."
export AWS_SECRET_ACCESS_KEY="..."
export AWS_REGION="eu-west-1"
Where To Get The Keys
AWS Console > IAM > Users > Your User > Security Credentials
Create Access Key > CLI use case
Save the key ID and secret (shown only once)
Your IAM user needs permissions for S3 and DynamoDB to run bootstrap (and broader permissions like EC2, EKS, IAM for the full apply later).

The Authentication Flow Summary
Stage	Auth Method
bootstrap/ (local)	Your local AWS CLI credentials
environments/dev/ (local)	Your local AWS CLI credentials
GitHub Actions CI/CD	OIDC — the oidc-github module creates this, no stored keys
The OIDC module you're provisioning in Phase 1 is specifically so that GitHub Actions can authenticate without storing AWS keys as secrets. Your local runs always use your own AWS credentials.



Based on all the resources being created across every module, your IAM user needs these policies:

Managed Policies To Attach
Policy	Needed For
AmazonEC2FullAccess	VPC, subnets, IGW, NAT, EIP, security groups, bastion EC2
AmazonEKSClusterPolicy	EKS cluster operations
AmazonS3FullAccess	State bucket (bootstrap + backend)
AmazonDynamoDBFullAccess	State locking table
IAMFullAccess	Creating roles, instance profiles, OIDC providers, policy attachments
CloudWatchLogsFullAccess	VPC flow logs log group
Plus One Inline Policy for EKS Node Group Management
The managed AmazonEKSClusterPolicy doesn't cover everything. Add this inline policy:


{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "EKSFullAccess",
      "Effect": "Allow",
      "Action": [
        "eks:*"
      ],
      "Resource": "*"
    },
    {
      "Sid": "PassRoleForEKS",
      "Effect": "Allow",
      "Action": "iam:PassRole",
      "Resource": "*",
      "Condition": {
        "StringEquals": {
          "iam:PassedToService": [
            "eks.amazonaws.com",
            "ec2.amazonaws.com"
          ]
        }
      }
    }
  ]
}
Quick Setup Via CLI

# Attach managed policies
aws iam attach-user-policy --user-name YOUR_USERNAME --policy-arn arn:aws:iam::aws:policy/AmazonEC2FullAccess
aws iam attach-user-policy --user-name YOUR_USERNAME --policy-arn arn:aws:iam::aws:policy/AmazonS3FullAccess
aws iam attach-user-policy --user-name YOUR_USERNAME --policy-arn arn:aws:iam::aws:policy/AmazonDynamoDBFullAccess
aws iam attach-user-policy --user-name YOUR_USERNAME --policy-arn arn:aws:iam::aws:policy/IAMFullAccess
aws iam attach-user-policy --user-name YOUR_USERNAME --policy-arn arn:aws:iam::aws:policy/CloudWatchLogsFullAccess

# Verify
aws iam list-attached-user-policies --user-name YOUR_USERNAME
For GCP (separate)
GCR module uses the Google provider, so you also need:

gcloud auth application-default login on your machine
Your GCP user needs Owner or Editor role on the GCP project
Summary
6 AWS policies (5 managed + 1 inline for EKS) cover everything Terraform needs to provision the full Phase 1 infrastructure. These are broad permissions suitable for a dev account — for production, you'd scope them down to specific resource ARNs.


GCP Setup — Step by Step
Step 1: Install Google Cloud CLI

# macOS (Homebrew)
brew install --cask google-cloud-sdk
Verify:


gcloud version
Step 2: Login to GCP

gcloud auth login
This opens your browser — sign in with your Google account.

Step 3: Create a GCP Project (if you don't have one)

# Create project
gcloud projects create YOUR_PROJECT_ID --name="EKS Assignment"

# Set it as active
gcloud config set project YOUR_PROJECT_ID
Or if you already have a project:


# List existing projects
gcloud projects list

# Set the one you want
gcloud config set project YOUR_PROJECT_ID
Step 4: Link a Billing Account
GCP APIs won't work without billing enabled.


# List billing accounts
gcloud billing accounts list

# Link billing to your project
gcloud billing projects link YOUR_PROJECT_ID --billing-account=BILLING_ACCOUNT_ID
Or do it in console: console.cloud.google.com/billing

Step 5: Set Application Default Credentials
This is what Terraform's Google provider uses:


gcloud auth application-default login
This opens the browser again and saves credentials to ~/.config/gcloud/application_default_credentials.json. Terraform picks this up automatically.

Step 6: Enable Required APIs Manually (one-time bootstrap)
The Terraform GCR module enables these APIs, but there's a chicken-and-egg problem — you need the base APIs active first:


gcloud services enable cloudresourcemanager.googleapis.com
gcloud services enable iam.googleapis.com
gcloud services enable sts.googleapis.com
gcloud services enable iamcredentials.googleapis.com
gcloud services enable containerregistry.googleapis.com
gcloud services enable storage.googleapis.com
Step 7: Verify Your IAM Permissions
Your Google account needs Owner or Editor on the project:


# Check current auth
gcloud auth list

# Check project permissions
gcloud projects get-iam-policy YOUR_PROJECT_ID --filter="bindings.members:YOUR_EMAIL"
If you created the project, you're already Owner.

Step 8: Set Your GCP Values in terraform.tfvars

cd terraform/environments/dev
In your terraform.tfvars:


gcp_project_id = "your-project-id"    # from step 3
gcp_region     = "us-central1"
Verification Checklist
Run these to confirm everything is ready:


# Logged in?
gcloud auth list
# ✓ Should show your account with asterisk

# Project set?
gcloud config get-value project
# ✓ Should show your project ID

# Billing linked?
gcloud billing projects describe YOUR_PROJECT_ID
# ✓ Should show billingEnabled: true

# Application default credentials set?
gcloud auth application-default print-access-token
# ✓ Should print a token (not an error)

# APIs enabled?
gcloud services list --enabled --filter="name:(iam OR storage OR containerregistry)"
# ✓ Should list the enabled APIs
Full Auth Summary
What	How
AWS local auth	aws configure (access key + secret)
GCP local auth	gcloud auth application-default login
AWS CI/CD auth	OIDC (created by oidc-github module)
GCP CI/CD auth	Workload Identity (created by gcr module)
Once both AWS and GCP are authenticated locally, you can run the full terraform apply from environments/dev/.
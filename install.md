# Complete Deployment Guide for HU-DevOps-26-highai

---

## Section A: Understanding Your Setup

```
YOUR VALUES:
├── GitHub Org:     Deloitte-DT-Training
├── Main Repo:      HU-DevOps-26-highai
├── CD Repo:        HU-DevOps-26-highai-cd  (you'll create this)
├── AWS Region:     us-west-1
├── Registry:       AWS ECR (no GCP/GCR needed)
├── Owner Name:     highai
└── You'll provide: AWS_ACCOUNT_ID (12-digit number)
```

### What Goes Where

```
┌─────────────────────────────────────────────────────────────────┐
│ Repo: Deloitte-DT-Training/HU-DevOps-26-highai                 │
│                                                                 │
│  Branch: IAC-DAY1                                               │
│    └── terraform/          (all Terraform code)                 │
│    └── .github/workflows/terraform.yml                          │
│                                                                 │
│  Branch: HU-DevOps-26-highai   (app branch)                     │
│    └── app/                (Flask microservices)                 │
│    └── .github/workflows/ci.yml                                 │
│    └── .github/workflows/pr-check.yml                           │
├─────────────────────────────────────────────────────────────────┤
│ Repo: Deloitte-DT-Training/HU-DevOps-26-highai-cd   (NEW)      │
│                                                                 │
│  Branch: main                                                   │
│    └── helm/               (all Helm charts)                    │
│    └── argocd/             (ArgoCD ApplicationSets)             │
│    └── scripts/            (setup & verification scripts)       │
└─────────────────────────────────────────────────────────────────┘
```

### Architecture Overview

```
Developer pushes code
    → CI builds Docker images
    → Trivy scans for vulnerabilities
    → CI pushes images to AWS ECR
    → CI updates image tag in CD repo
    → ArgoCD detects change (polls every 3 min)
    → ArgoCD syncs new image to EKS
```

### Terraform Modules

```
terraform/
├── bootstrap/           ← S3 + DynamoDB (apply FIRST)
├── modules/
│   ├── vpc/             ← VPC, subnets, NAT, IGW
│   ├── eks/             ← EKS cluster + node group
│   ├── ec2-bastion/     ← Private bastion with SSM access
│   ├── oidc-github/     ← GitHub Actions OIDC + IAM role
│   └── ecr/             ← 4 ECR repositories for microservices
└── environments/dev/    ← Root config calling all modules
```

### ArgoCD Sync Wave Order

```
Wave -2: namespaces             ← Must exist before everything
Wave -1: sealed-secrets         ← Core prerequisites
         security (Kyverno)
         resource-governance
Wave  0: microservices (x4)     ← All 4 services
         database (Percona)
Wave  1: keda                   ← Autoscaling
         api-gateway (Kong)
Wave  2: monitoring             ← Prometheus + Grafana + Tempo
         logging                ← Loki + Promtail
Wave  3: linkerd-config         ← Service mesh policies
```

---

## Section B: The Only Placeholder Left

All repo URLs, branch names, region, and org/owner values have already been
replaced in the codebase. The **only remaining placeholder** is:

### `YOUR_AWS_ACCOUNT_ID`

You need your 12-digit AWS Account ID. To find it:

```bash
aws sts get-caller-identity --query Account --output text
```

Once you have it, replace in **6 files** (run from the project root):

```bash
# Replace YOUR_AWS_ACCOUNT_ID with your actual account ID
# Example: if your account ID is 123456789012

sed -i '' 's/YOUR_AWS_ACCOUNT_ID/123456789012/g' \
  terraform/environments/dev/backend.tf \
  terraform/environments/dev/terraform.tfvars.example \
  cd-repo/helm/frontend/values.yaml \
  cd-repo/helm/users-service/values.yaml \
  cd-repo/helm/products-service/values.yaml \
  cd-repo/helm/orders-service/values.yaml
```

**Files affected:**

| File | What changes |
|------|-------------|
| `terraform/environments/dev/backend.tf` | S3 bucket name: `eks-assignment-dev-tfstate-<ACCOUNT_ID>` |
| `terraform/environments/dev/terraform.tfvars.example` | `aws_account_id` value |
| `cd-repo/helm/frontend/values.yaml` | Image: `<ACCOUNT_ID>.dkr.ecr.us-west-1.amazonaws.com/frontend` |
| `cd-repo/helm/users-service/values.yaml` | Image: `<ACCOUNT_ID>.dkr.ecr.us-west-1.amazonaws.com/users-service` |
| `cd-repo/helm/products-service/values.yaml` | Image: `<ACCOUNT_ID>.dkr.ecr.us-west-1.amazonaws.com/products-service` |
| `cd-repo/helm/orders-service/values.yaml` | Image: `<ACCOUNT_ID>.dkr.ecr.us-west-1.amazonaws.com/orders-service` |

### Verify all placeholders are gone:

```bash
grep -r "YOUR_" --include="*.tf" --include="*.yaml" --include="*.yml" --include="*.sh" .
# Should return ZERO results after replacement
```

---

## Phase 1 — Terraform Infrastructure

**Goal:** Create VPC, EKS cluster, bastion EC2, OIDC provider, ECR repositories.

### Step 1.1 — Prerequisites on your machine

```bash
# Verify you have these tools installed
terraform --version     # Need >= 1.5.0
aws --version           # Need AWS CLI v2
kubectl version --client
helm version
git --version
```

> **Note:** No GCP/gcloud needed — we use AWS ECR instead of GCR.

### Step 1.2 — Configure AWS CLI

```bash
aws configure
# AWS Access Key ID:     <your-key>
# AWS Secret Access Key: <your-secret>
# Default region:        us-west-1
# Default output format: json
```

Verify:
```bash
aws sts get-caller-identity
# Should show your account ID and user ARN
```

### Step 1.3 — Create terraform.tfvars

```bash
cd terraform/environments/dev
cp terraform.tfvars.example terraform.tfvars
```

Edit `terraform.tfvars` with your actual AWS account ID:

```hcl
aws_region     = "us-west-1"
aws_account_id = "123456789012"    # Your actual 12-digit AWS account ID
project_name   = "eks-assignment"
environment    = "dev"
owner          = "highai"

vpc_cidr             = "10.0.0.0/16"
public_subnet_cidr   = "10.0.1.0/24"
private_subnet_cidrs = ["10.0.2.0/24", "10.0.3.0/24"]
availability_zones   = ["us-west-1a", "us-west-1b"]

cluster_name       = "eks-assignment-cluster"
kubernetes_version = "1.29"
node_instance_type = "t2.medium"
node_desired_count = 2
node_min_count     = 2
node_max_count     = 3

github_org    = "Deloitte-DT-Training"
github_repo   = "HU-DevOps-26-highai"
github_branch = "IAC-DAY1"
```

> **IMPORTANT:** `terraform.tfvars` is gitignored — never commit it.

### Step 1.4 — Bootstrap remote backend (run FIRST, locally)

```bash
cd terraform/bootstrap
terraform init
terraform plan \
  -var="aws_account_id=123456789012" \
  -var="owner=highai" \
  -var="aws_region=us-west-1"

terraform apply \
  -var="aws_account_id=123456789012" \
  -var="owner=highai" \
  -var="aws_region=us-west-1"
```

This creates:
- S3 bucket: `eks-assignment-dev-tfstate-<ACCOUNT_ID>` (for Terraform state)
- DynamoDB table: `eks-assignment-dev-tflock` (for state locking)

### Step 1.5 — Deploy all infrastructure (locally)

```bash
cd terraform/environments/dev
terraform init
terraform plan
terraform apply
```

This creates: VPC, EKS cluster, bastion EC2, GitHub OIDC role, 4 ECR repositories.

> **Expect ~15-20 minutes** — EKS cluster creation takes time.

### Step 1.6 — Save the outputs

```bash
terraform output
```

**Save these values — you'll need them later:**

```
github_actions_role_arn    → For GitHub Secrets
bastion_instance_id        → For SSM connection
eks_cluster_name           → For kubectl config
ecr_registry_url           → For verifying ECR repos
ecr_repository_urls        → Map of all 4 ECR repo URLs
bastion_ssm_command        → Exact SSM command to connect
```

### Step 1.7 — Verify infrastructure

```bash
# Check EKS cluster exists
aws eks describe-cluster --name eks-assignment-cluster --region us-west-1 \
  --query 'cluster.status'
# Should return: "ACTIVE"

# Check ECR repositories exist
aws ecr describe-repositories --region us-west-1 \
  --query 'repositories[].repositoryName'
# Should return: ["frontend", "orders-service", "products-service", "users-service"]

# Check bastion exists
aws ec2 describe-instances --region us-west-1 \
  --filters "Name=tag:Name,Values=*bastion*" \
  --query 'Reservations[].Instances[].InstanceId'
```

---

## Phase 2 — Push Terraform Code to GitHub (IAC-DAY1 branch)

**Goal:** Push Terraform code to the IAC-DAY1 branch of the main repo.

### Step 2.1 — Clone and set up IAC-DAY1 branch

```bash
# Clone the repo (if not already cloned)
git clone https://github.com/Deloitte-DT-Training/HU-DevOps-26-highai.git
cd HU-DevOps-26-highai

# Create the IAC-DAY1 branch (orphan — no history from main)
git checkout --orphan IAC-DAY1
git rm -rf . 2>/dev/null || true
```

### Step 2.2 — Copy Terraform code

```bash
# Copy terraform directory
cp -r /path/to/hitakshi/terraform/* .
cp -r /path/to/hitakshi/terraform/.* . 2>/dev/null || true

# Copy terraform workflow
mkdir -p .github/workflows
cp /path/to/hitakshi/terraform/.github/workflows/terraform.yml .github/workflows/

# Ensure terraform.tfvars is NOT included
echo "terraform.tfvars" >> .gitignore
echo ".terraform/" >> .gitignore
echo "*.tfstate*" >> .gitignore
```

### Step 2.3 — Commit and push

```bash
git add .
git commit -m "feat: add Terraform infrastructure (VPC, EKS, EC2, OIDC, ECR)

- Modular Terraform: VPC, EKS, EC2 bastion, GitHub OIDC, ECR
- Remote backend config (S3 + DynamoDB)
- Dev environment with variable configuration
- GitHub Actions pipeline for plan/apply"

git push -u origin IAC-DAY1
```

---

## Phase 3 — Push Application Code + CI (app branch)

**Goal:** Push Flask microservices and CI workflows to the app branch.

### Step 3.1 — Set up app branch

```bash
cd /path/to/HU-DevOps-26-highai
git checkout --orphan HU-DevOps-26-highai
git rm -rf . 2>/dev/null || true
```

### Step 3.2 — Copy app code and workflows

```bash
# Copy app code
cp -r /path/to/hitakshi/app .

# Copy CI workflows
mkdir -p .github/workflows
cp /path/to/hitakshi/.github/workflows/ci.yml .github/workflows/
cp /path/to/hitakshi/.github/workflows/pr-check.yml .github/workflows/
```

### Step 3.3 — Commit and push

```bash
git add .
git commit -m "feat: add Flask microservices and CI pipeline

- 4 Flask services: users, products, orders, frontend
- OpenTelemetry tracing + Prometheus metrics + JSON logging
- CI: build, Trivy scan, push to AWS ECR
- PR validation with security scanning"

git push -u origin HU-DevOps-26-highai
```

> **Note:** CI won't work yet — you need to set up GitHub Secrets first (Phase 5).

---

## Phase 4 — Create & Push CD Repo

**Goal:** Create separate CD repo with Helm charts and ArgoCD config.

### Step 4.1 — Create the repo on GitHub

Go to GitHub -> Deloitte-DT-Training -> **New repository** -> Name: `HU-DevOps-26-highai-cd`

- Visibility: Private (or as per company policy)
- Do NOT initialize with README (we'll push our own content)

### Step 4.2 — Push CD content

```bash
mkdir /tmp/cd-repo && cd /tmp/cd-repo
git init
git checkout -b main

# Copy cd-repo CONTENTS (not the folder itself)
cp -r /path/to/hitakshi/cd-repo/* .
cp -r /path/to/hitakshi/cd-repo/.* . 2>/dev/null || true

git add .
git commit -m "feat: add complete CD repo (Helm charts + ArgoCD + scripts)

- Helm charts: namespaces, 4 services, database, gateway, security
- Observability: monitoring (Prometheus, Grafana, Tempo), logging (Loki)
- Advanced: Linkerd mesh, KEDA autoscaling, resource governance
- ArgoCD: ApplicationSets with sync waves
- Scripts: bootstrap, verification, demos"

git remote add origin https://github.com/Deloitte-DT-Training/HU-DevOps-26-highai-cd.git
git push -u origin main
```

---

## Phase 5 — Configure GitHub Secrets

### Step 5.1 — On the MAIN repo (HU-DevOps-26-highai)

Go to **Settings -> Secrets and variables -> Actions -> New repository secret**

| Secret Name | Value | Source |
|-------------|-------|--------|
| `AWS_ROLE_ARN` | `arn:aws:iam::<ACCOUNT_ID>:role/eks-assignment-dev-github-actions-role` | Terraform output: `github_actions_role_arn` |
| `AWS_ACCOUNT_ID` | `123456789012` | Your AWS account ID |
| `CD_REPO` | `Deloitte-DT-Training/HU-DevOps-26-highai-cd` | Your CD repo path |
| `CD_REPO_PAT` | `ghp_xxxxxxxxx` | GitHub PAT (see Step 5.2) |
| `TF_VAR_github_org` | `Deloitte-DT-Training` | Your GitHub org |
| `TF_VAR_github_repo` | `HU-DevOps-26-highai` | Your repo name |
| `TF_VAR_owner` | `highai` | Your owner name |

> **No GCP secrets needed** — we use AWS ECR, not GCR.

### Step 5.2 — Create Personal Access Token (for CD_REPO_PAT)

1. GitHub -> **Settings** -> **Developer settings** -> **Personal access tokens** -> **Tokens (classic)**
2. **Generate new token (classic)**
3. Name: `CD Repo Access`
4. Expiration: 90 days (or as per company policy)
5. Scope: `repo` (full control of private repositories)
6. Copy the token immediately — you won't see it again

### Step 5.3 — Verify CI workflow triggers

After secrets are configured, trigger the CI by pushing a small change to the app branch:

```bash
cd /path/to/HU-DevOps-26-highai
git checkout HU-DevOps-26-highai

# Make a tiny change to trigger CI
echo "# trigger ci" >> app/frontend/README.md
git add . && git commit -m "ci: trigger initial build"
git push
```

Check GitHub Actions tab — the CI should:
1. Build all 4 Docker images
2. Run Trivy vulnerability scans
3. Push images to ECR
4. Update image tags in CD repo

---

## Phase 6 — Deploy to EKS Cluster (from Bastion)

### Step 6.1 — Connect to bastion via SSM

```bash
# Use the exact command from terraform output
aws ssm start-session \
  --target <BASTION_INSTANCE_ID> \
  --region us-west-1
```

### Step 6.2 — Verify EKS access

```bash
# Configure kubectl (bastion user-data script should have done this)
aws eks update-kubeconfig --name eks-assignment-cluster --region us-west-1

kubectl get nodes
# Should show 2 nodes in Ready state
```

### Step 6.3 — Clone CD repo on bastion

```bash
git clone https://github.com/Deloitte-DT-Training/HU-DevOps-26-highai-cd.git
cd HU-DevOps-26-highai-cd
```

### Step 6.4 — Install Kong Gateway (before ArgoCD)

```bash
cd scripts
chmod +x *.sh
./install-kong.sh
```

### Step 6.5 — Build Helm dependencies

```bash
cd ../helm/monitoring && helm dependency build
cd ../logging && helm dependency build
cd ../keda && helm dependency build
cd ../sealed-secrets && helm dependency build
cd ../security && helm dependency build
cd ../database && helm dependency build
cd ../../

# Commit lock files so ArgoCD can use them
git add .
git commit -m "chore: add helm dependency lock files"
git push origin main
```

### Step 6.6 — Bootstrap ArgoCD

```bash
cd scripts
./bootstrap-argocd.sh \
  https://github.com/Deloitte-DT-Training/HU-DevOps-26-highai-cd \
  YOUR_GITHUB_PAT
```

**Save the ArgoCD admin password** that the script outputs.

### Step 6.7 — Watch ArgoCD sync

```bash
kubectl get applications -n argocd -w
```

ArgoCD syncs in wave order:
```
Wave -2: namespaces            (creating all K8s namespaces)
Wave -1: sealed-secrets        (encryption controller)
         security              (Kyverno + NetworkPolicies)
         resource-governance   (LimitRanges + ResourceQuotas)
Wave  0: users-service         (will be Degraded — no DB secret yet)
         products-service      (will be Degraded — no DB secret yet)
         orders-service        (will be Degraded — no DB secret yet)
         frontend              (should be Healthy)
         database              (Percona PostgreSQL operator)
```

> **Expected:** Backend services show `Degraded` because `db-credentials` secret
> doesn't exist yet. Frontend should be `Healthy`. This is normal.

> **ECR Note:** No pull secrets needed — EKS nodes have the
> `AmazonEC2ContainerRegistryReadOnly` IAM policy and can pull from ECR natively.

### Step 6.8 — Create sealed secrets for DB credentials

Wait for the Percona database to be ready (~3-5 minutes), then:

```bash
cd scripts
./create-sealed-secrets.sh
```

This will:
1. Fetch DB credentials from Percona-generated secret
2. Encrypt them using kubeseal
3. Save as SealedSecret YAML files

Follow the output — commit the generated sealed secrets:

```bash
cd ..
git add helm/sealed-secrets/templates/sealed-db-*.yaml
git commit -m "feat: add sealed DB credentials [skip ci]"
git push origin main
```

ArgoCD will pick up the sealed secrets and the Sealed Secrets controller
will decrypt them. Backend pods should restart and connect to PostgreSQL.

### Step 6.9 — Verify all services

```bash
# Check all ArgoCD applications
kubectl get applications -n argocd

# Expected output:
# NAME                  SYNC STATUS   HEALTH STATUS
# namespaces            Synced        Healthy
# sealed-secrets        Synced        Healthy
# security              Synced        Healthy
# resource-governance   Synced        Healthy
# users-service         Synced        Healthy  (after sealed secrets)
# products-service      Synced        Healthy  (after sealed secrets)
# orders-service        Synced        Healthy  (after sealed secrets)
# frontend              Synced        Healthy
# database              Synced        Healthy

# Check pods in each namespace
kubectl get pods -n backend-users
kubectl get pods -n backend-products
kubectl get pods -n backend-orders
kubectl get pods -n frontend
kubectl get pods -n database

# Check services
kubectl get svc -A | grep -E "users|products|orders|frontend"
```

---

## Phase 7 — Observability (Prometheus, Grafana, Loki)

### Step 7.1 — Verify monitoring stack is synced

ArgoCD should have already synced the monitoring and logging apps (wave 2).

```bash
kubectl get applications monitoring logging -n argocd
# Both should show Synced / Healthy

kubectl get pods -n monitoring
kubectl get pods -n logging
```

### Step 7.2 — Restart services to pick up OTEL config

```bash
kubectl rollout restart deployment/users-service -n backend-users
kubectl rollout restart deployment/products-service -n backend-products
kubectl rollout restart deployment/orders-service -n backend-orders
kubectl rollout restart deployment/frontend -n frontend
```

### Step 7.3 — Generate test traffic and open Grafana

```bash
cd scripts
./generate-test-traffic.sh

# Port-forward Grafana
./port-forward-grafana.sh
# Open http://localhost:3000
# Username: admin
# Password: admin123 (or check monitoring values.yaml)
```

### Step 7.4 — Access ArgoCD UI

```bash
kubectl port-forward svc/argocd-server -n argocd 8080:80
# Open http://localhost:8080
# Username: admin
# Password: (from Phase 6 Step 6.6)
```

---

## Phase 8 — Advanced Platform (Linkerd, KEDA, Demos)

### Step 8.1 — Install and inject Linkerd service mesh

```bash
cd scripts
./install-linkerd.sh
./inject-linkerd-mesh.sh
```

### Step 8.2 — Run demo scripts for proof

```bash
./verify-linkerd.sh        # Zero-trust mTLS proof
./load-test-keda.sh        # KEDA autoscaling demo
./node-failure-test.sh     # Node failure resilience
```

### Step 8.3 — ArgoCD self-heal tests

```bash
# Test 1: Delete a pod — ArgoCD recreates it
kubectl delete pod -n backend-users -l app=users-service
# Pod recreates within seconds

# Test 2: Scale manually — ArgoCD reverts it
kubectl scale deploy users-service -n backend-users --replicas=5
# Reverts to 2 within 3 minutes (reconciliation interval)
```

---

## Troubleshooting

| Problem | Cause | Fix |
|---------|-------|-----|
| `ImagePullBackOff` | ECR repo doesn't exist or image not pushed yet | Check ECR repos: `aws ecr describe-repositories --region us-west-1`. Run CI to push images. |
| `CreateContainerConfigError` | `db-credentials` secret missing | Run `create-sealed-secrets.sh` (Phase 6, Step 6.8) |
| Application stuck `OutOfSync` | Repo credentials wrong | Check `cd-repo-secret` in argocd namespace |
| `ComparisonError` | Helm template syntax error | Run `helm template helm/<service>` locally to debug |
| CI fails at ECR login | `AWS_ROLE_ARN` secret wrong | Verify with `terraform output github_actions_role_arn` |
| CI fails at "Update CD Repo" | `CD_REPO_PAT` expired or missing | Generate new PAT and update secret |
| Terraform init fails | S3 bucket doesn't exist | Run bootstrap first (Phase 1, Step 1.4) |
| SSM session fails | Bastion not in private subnet / SSM policy missing | Check bastion SG and IAM instance profile |
| `helm dependency build` fails | No internet on bastion | Check NAT Gateway is working |

---

## Important Notes

1. **us-west-1 has only 2 AZs** (us-west-1a and us-west-1b) — works perfectly for 2 private subnets.

2. **EKS endpoint is private-only** — `kubectl` only works from inside the VPC (bastion via SSM). Terraform apply from GitHub Actions won't reach the cluster directly. Options:
   - Run `terraform apply` locally (easiest for now)
   - Set up a self-hosted runner on the bastion later

3. **ECR pull access is automatic** — EKS nodes have `AmazonEC2ContainerRegistryReadOnly` IAM policy. No imagePullSecrets needed.

4. **Order matters:** Bootstrap -> Terraform -> Push code -> GitHub Secrets -> CI -> ArgoCD.

5. **Never commit `terraform.tfvars`** — it's gitignored and contains your account ID.

6. **CD repo uses `main` branch** — simpler than using a named branch since it's a separate repo.

7. **CI workflow:** Pushes to `HU-DevOps-26-highai` branch trigger build + push to ECR + CD repo update. PRs trigger build + Trivy scan only (no push).

---

## Quick Reference — All Commands in Order

```bash
# === PHASE 1: Terraform ===
cd terraform/bootstrap
terraform init && terraform apply -var="aws_account_id=XXXX" -var="owner=highai" -var="aws_region=us-west-1"

cd ../environments/dev
cp terraform.tfvars.example terraform.tfvars  # Edit with your account ID
terraform init && terraform plan && terraform apply
terraform output  # SAVE THESE VALUES

# === PHASE 2: Push IAC-DAY1 branch ===
# (see Phase 2 steps above)

# === PHASE 3: Push app branch ===
# (see Phase 3 steps above)

# === PHASE 4: Push CD repo ===
# (see Phase 4 steps above)

# === PHASE 5: GitHub Secrets ===
# (set 7 secrets in GitHub UI — see table above)

# === PHASE 6: Deploy to EKS ===
aws ssm start-session --target <BASTION_ID> --region us-west-1
git clone https://github.com/Deloitte-DT-Training/HU-DevOps-26-highai-cd.git
cd HU-DevOps-26-highai-cd/scripts
./install-kong.sh
# Build helm deps, commit, push
./bootstrap-argocd.sh <CD_REPO_URL> <PAT>
kubectl get applications -n argocd -w
./create-sealed-secrets.sh
# Commit sealed secrets, push

# === PHASE 7: Observability ===
./generate-test-traffic.sh
./port-forward-grafana.sh

# === PHASE 8: Advanced ===
./install-linkerd.sh
./inject-linkerd-mesh.sh
./verify-linkerd.sh
./load-test-keda.sh
./node-failure-test.sh
```

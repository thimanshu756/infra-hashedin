# Complete Setup Guide — End to End

This guide takes you from the unzipped folder to a fully running platform.

---

## What You Got (Folder Map)

```
hitakshi/
├── terraform/          → Goes to IAC-DAY1 branch
├── app/                → Goes to HIU-DevOps-26-yourname branch
├── .github/workflows/  → ci.yml + pr-check.yml (go with app branch)
├── cd-repo/            → Contents go to HIU-DEVOPS-26-yourname branch
│   ├── helm/           (Helm charts for everything)
│   ├── argocd/         (ArgoCD config)
│   ├── scripts/        (Setup + verification scripts)
│   └── docs/           (Proof documentation)
└── imp/                → Reference guides (don't push anywhere)
```

**3 branches, 1 repo:**

| Branch | What goes there | Workflow |
|--------|----------------|----------|
| `IAC-DAY1` | `terraform/` folder + terraform workflow | Terraform plan/apply |
| `HIU-DevOps-26-yourname` | `app/` folder + CI workflows | Build, scan, push to GCR |
| `HIU-DEVOPS-26-yourname` | Contents of `cd-repo/` | ArgoCD watches this |

---

## Assignment Checklist (All 13 Sections Covered)

| # | Requirement | Covered By | Status |
|---|------------|-----------|--------|
| 1 | Infrastructure (Terraform) | `terraform/` — VPC, EKS, EC2, OIDC, GCR | Done |
| 2 | CI (GitHub Actions) | `ci.yml`, `pr-check.yml` | Done |
| 3 | CD (ArgoCD + Helm) | `cd-repo/argocd/`, `cd-repo/helm/` | Done |
| 4 | Namespaces (11 total) | `helm/namespaces/` | Done |
| 5 | API Gateway (Kong + Gateway API) | `helm/api-gateway/` | Done |
| 6 | Database (Percona PostgreSQL) | `helm/database/` | Done |
| 7 | Observability (Prometheus, Loki, Tempo) | `helm/monitoring/`, `helm/logging/` | Done |
| 8 | Application (Flask CRUD) | `app/` — 4 services with OTel + Prometheus | Done |
| 9 | Security (Kyverno, NetworkPolicies, Sealed Secrets) | `helm/security/`, `helm/sealed-secrets/` | Done |
| 10 | Service Mesh (Linkerd) | `helm/linkerd/`, scripts | Done |
| 11 | Resource Governance (Quota + LimitRange) | `helm/resource-governance/` | Done |
| 12 | Autoscaling (KEDA) | `helm/keda/` | Done |
| 13 | Node Failure Test | `scripts/node-failure-test.sh`, `docs/node-failure-analysis.md` | Done |

---

## Prerequisites

Before starting, you need:

- [ ] AWS account with admin access
- [ ] GCP account with a project (for GCR image registry)
- [ ] GitHub account (personal or org — e.g., `Deloitte-LLS`)
- [ ] Local machine with: `git`, `aws cli v2`, `terraform`, `kubectl`, `helm`, `kubeseal`
- [ ] GitHub repo created (empty, we'll push code to it)

---

## Step 0 — Replace All Placeholders

**Do this BEFORE pushing anything to GitHub.**

### 0.1 — Decide your values

Fill in these values (example shown):

```
YOUR_NAME         = hitakshi
GITHUB_ORG        = Deloitte-LLS           (or your personal GitHub username)
GITHUB_REPO       = your-repo-name         (the repo you created)
AWS_ACCOUNT_ID    = 123456789012
GCP_PROJECT_ID    = my-gcp-project-123
AWS_REGION        = eu-west-1
```

### 0.2 — Replace in CI workflows

**File: `.github/workflows/ci.yml`** (lines 15, 162, 196)
```
Find:    Deloitte-US/HU-DevOps-26-yourname
Replace: HIU-DevOps-26-YOUR_NAME
```
```
Find:    HU-DEVOPS-26-yourname
Replace: HIU-DEVOPS-26-YOUR_NAME
```

**File: `.github/workflows/pr-check.yml`** (line 15)
```
Find:    Deloitte-US/HU-DevOps-26-yourname
Replace: HIU-DevOps-26-YOUR_NAME
```

### 0.3 — Replace in CD repo (ArgoCD applicationsets)

Run this from the `cd-repo/` folder:

```bash
# Replace repo URL in ALL applicationsets
find argocd/ -name "*.yaml" -exec sed -i '' \
  's|YOUR_ORG/YOUR_CD_REPO|GITHUB_ORG/GITHUB_REPO|g' {} \;

# Replace branch name in ALL applicationsets
find argocd/ -name "*.yaml" -exec sed -i '' \
  's|HU-DEVOPS-26-yourname|HIU-DEVOPS-26-YOUR_NAME|g' {} \;

# Replace GCP project in service values
find helm/ -name "values.yaml" -exec sed -i '' \
  's|YOUR_GCP_PROJECT_ID|GCP_PROJECT_ID|g' {} \;
```

Also update in `scripts/bootstrap-argocd.sh` and `scripts/create-sealed-secrets.sh`:
```
Find:    thimanshu756/hitakshi-cd
Replace: GITHUB_ORG/GITHUB_REPO

Find:    HU-DEVOPS-26-yourname
Replace: HIU-DEVOPS-26-YOUR_NAME
```

### 0.4 — Replace in Terraform

**File: `terraform/environments/dev/terraform.tfvars.example`**

Copy it to `terraform.tfvars` and fill in real values:
```bash
cp terraform/environments/dev/terraform.tfvars.example \
   terraform/environments/dev/terraform.tfvars
```

Edit `terraform.tfvars`:
```hcl
aws_region         = "eu-west-1"
aws_account_id     = "123456789012"      # YOUR AWS account ID
project_name       = "eks-assignment"
environment        = "dev"
owner              = "YOUR_NAME"

node_instance_type = "t2.medium"         # IMPORTANT: assignment requires t2.medium

github_org         = "GITHUB_ORG"
github_repo        = "GITHUB_REPO"
github_branch      = "IAC-DAY1"

gcp_project_id     = "GCP_PROJECT_ID"
```

**IMPORTANT:** The example file has `t3.micro` — change it to `t2.medium` as the assignment requires.

---

## Step 1 — Set Up GitHub Repo and Branches

### 1.1 — Create a GitHub repo

Create an empty repo in your GitHub org (or personal account).
Example: `Deloitte-LLS/my-eks-assignment`

### 1.2 — Push IAC-DAY1 branch (Terraform)

```bash
# From the unzipped hitakshi/ folder
cd terraform

git init
git checkout -b IAC-DAY1

# Move the terraform workflow to correct location
mkdir -p .github/workflows
cp .github/workflows/terraform.yml .github/workflows/terraform.yml

# Copy the .gitignore
# (the terraform/.gitignore already exists)

git add .
git commit -m "feat: add Terraform infrastructure (VPC, EKS, EC2, OIDC, GCR)

- Modular Terraform: VPC, EKS, EC2 bastion, GitHub OIDC, GCR
- Remote backend config (S3 + DynamoDB)
- Dev environment with variable configuration
- GitHub Actions pipeline for plan/apply"

git remote add origin https://github.com/GITHUB_ORG/GITHUB_REPO.git
git push -u origin IAC-DAY1
```

### 1.3 — Push Application branch (Flask + CI)

```bash
# Go back to hitakshi/ root
cd ..

# Create a temp folder for the app branch
mkdir /tmp/app-branch && cd /tmp/app-branch
git init
git checkout -b HIU-DevOps-26-YOUR_NAME

# Copy app code
cp -r /path/to/hitakshi/app .

# Copy CI workflows
mkdir -p .github/workflows
cp /path/to/hitakshi/.github/workflows/ci.yml .github/workflows/
cp /path/to/hitakshi/.github/workflows/pr-check.yml .github/workflows/

git add .
git commit -m "feat: add Flask microservices and CI pipeline

- 4 Flask services: users, products, orders, frontend
- OpenTelemetry tracing + Prometheus metrics + JSON logging
- CI: build, Trivy scan, push to GCR
- PR validation with security scanning"

git remote add origin https://github.com/GITHUB_ORG/GITHUB_REPO.git
git push -u origin HIU-DevOps-26-YOUR_NAME
```

### 1.4 — Push CD branch (Helm + ArgoCD)

```bash
mkdir /tmp/cd-branch && cd /tmp/cd-branch
git init
git checkout -b HIU-DEVOPS-26-YOUR_NAME

# Copy cd-repo contents (not the folder itself — the CONTENTS)
cp -r /path/to/hitakshi/cd-repo/* .
cp -r /path/to/hitakshi/cd-repo/.* . 2>/dev/null || true

git add .
git commit -m "feat: add complete CD repo (Helm charts + ArgoCD + scripts)

- Helm charts: namespaces, 4 services, database, gateway, security
- Observability: monitoring (Prometheus, Grafana, Tempo), logging (Loki)
- Advanced: Linkerd mesh, KEDA autoscaling, resource governance
- ArgoCD: ApplicationSets with sync waves
- Scripts: bootstrap, verification, demos"

git remote add origin https://github.com/GITHUB_ORG/GITHUB_REPO.git
git push -u origin HIU-DEVOPS-26-YOUR_NAME
```

---

## Step 2 — Configure GitHub Secrets

Go to: GitHub repo → Settings → Secrets and variables → Actions

Add these secrets:

| Secret Name | Value | Used By |
|------------|-------|---------|
| `AWS_ROLE_ARN` | ARN of github-actions-role (from Terraform output) | terraform.yml |
| `AWS_ACCOUNT_ID` | Your AWS account ID | terraform.yml |
| `GCP_PROJECT_ID` | Your GCP project ID | ci.yml, terraform.yml |
| `WIF_PROVIDER` | GCP Workload Identity Federation provider (from Terraform output) | ci.yml |
| `GCR_SERVICE_ACCOUNT` | GCP service account email (from Terraform output) | ci.yml |
| `CD_REPO` | `GITHUB_ORG/GITHUB_REPO` | ci.yml |
| `CD_REPO_PAT` | GitHub Personal Access Token (with repo scope) | ci.yml |
| `TF_VAR_github_org` | Your GitHub org | terraform.yml |
| `TF_VAR_github_repo` | Your repo name | terraform.yml |
| `TF_VAR_owner` | Your name | terraform.yml |

**Note:** Some secrets (AWS_ROLE_ARN, WIF_PROVIDER, GCR_SERVICE_ACCOUNT) come from Terraform outputs. You'll get them after Step 3.

---

## Step 3 — Deploy Phase 1: Infrastructure (Terraform)

### 3.1 — Bootstrap remote backend (run locally, once)

```bash
# SSH to bastion or run locally with AWS credentials
cd terraform/bootstrap
terraform init
terraform plan
terraform apply
```

This creates the S3 bucket and DynamoDB table for state locking.

### 3.2 — Deploy infrastructure

**Option A: Via pipeline** — Push to IAC-DAY1 branch triggers terraform apply.

**Option B: Locally** (if pipeline isn't ready yet):
```bash
cd terraform/environments/dev
terraform init
terraform plan
terraform apply
```

### 3.3 — Note the outputs

After apply, save these outputs (you'll need them for GitHub Secrets):
```
eks_cluster_name
eks_cluster_endpoint
bastion_instance_id
github_actions_role_arn
gcr_service_account_email
gcr_workload_identity_provider
```

### 3.4 — Connect to bastion

```bash
aws ssm start-session --target <bastion_instance_id> --region eu-west-1
```

From bastion, verify EKS access:
```bash
kubectl get nodes
# Should show 2 nodes: Ready
```

---

## Step 4 — Deploy Phase 2: Verify Application Code

The Flask app code is already on the app branch. Nothing to deploy yet.
The CI pipeline will build and push images when you push to the app branch.

Test locally with docker-compose (optional):
```bash
cd app
docker-compose up
# Frontend: http://localhost:3000
# APIs: http://localhost:5001/users, :5002/products, :5003/orders
```

---

## Step 5 — Deploy Phase 3: CI Pipeline

### 5.1 — Trigger CI

Push any change to the app branch to trigger the CI pipeline:
```bash
# On HIU-DevOps-26-YOUR_NAME branch
git commit --allow-empty -m "ci: trigger initial build"
git push origin HIU-DevOps-26-YOUR_NAME
```

Check GitHub Actions — the pipeline should:
1. Build all 4 Docker images
2. Scan with Trivy
3. Push to GCR
4. Update image tags in CD branch

### 5.2 — Verify GCR images

```bash
gcloud container images list --repository=gcr.io/GCP_PROJECT_ID
# Should show: users-service, products-service, orders-service, frontend
```

---

## Step 6 — Deploy Phase 3: CD (ArgoCD + Helm)

All commands below run from the bastion (or local with kubectl access).

### 6.1 — Install Kong Gateway (prerequisite)

```bash
cd scripts
chmod +x *.sh
./install-kong.sh
```

### 6.2 — Bootstrap ArgoCD

```bash
./bootstrap-argocd.sh https://github.com/GITHUB_ORG/GITHUB_REPO YOUR_GIT_PAT
```

This installs ArgoCD and configures it to watch the CD branch.

### 6.3 — Build Helm dependencies

```bash
cd ../helm/monitoring && helm dependency build
cd ../logging && helm dependency build
cd ../keda && helm dependency build
cd ../sealed-secrets && helm dependency build
cd ../security && helm dependency build
cd ../database && helm dependency build
```

Push the generated Chart.lock files to the CD branch:
```bash
git add . && git commit -m "chore: add helm dependency lock files" && git push
```

### 6.4 — Watch ArgoCD sync

```bash
kubectl get applications -n argocd -w
```

ArgoCD will auto-sync in wave order:
```
Wave -2: namespaces
Wave -1: gcr-pull-secret, sealed-secrets, security, resource-governance
Wave  0: database, users-service, products-service, orders-service, frontend
Wave  1: api-gateway, keda
Wave  2: monitoring, logging
Wave  3: linkerd-config
```

### 6.5 — Create GCR pull secret

```bash
./create-gcr-secret.sh /path/to/gcr-key.json
```

### 6.6 — Create sealed secrets for DB credentials

```bash
./create-sealed-secrets.sh
```

Follow the script output — it generates encrypted secrets and tells you to commit them.

---

## Step 7 — Deploy Phase 4: Verify Platform

```bash
./verify-phase4.sh
```

This checks:
- Database pods running
- Kong Gateway routing works
- Kyverno policies enforced
- NetworkPolicies active
- Sealed Secrets controller running

Test the APIs:
```bash
GATEWAY=$(kubectl get svc -n api-gateway -o jsonpath='{.items[0].status.loadBalancer.ingress[0].hostname}')
curl http://$GATEWAY/api/users
curl http://$GATEWAY/api/products
curl http://$GATEWAY/api/orders
curl http://$GATEWAY/
```

---

## Step 8 — Deploy Phase 5: Observability

### 8.1 — Rolling restart services (pick up OTEL env vars)

```bash
kubectl rollout restart deployment/users-service -n backend-users
kubectl rollout restart deployment/products-service -n backend-products
kubectl rollout restart deployment/orders-service -n backend-orders
kubectl rollout restart deployment/frontend -n frontend
```

### 8.2 — Generate test traffic

```bash
./generate-test-traffic.sh
```

### 8.3 — Open Grafana

```bash
./port-forward-grafana.sh
# Open http://localhost:3000
# Username: admin / Password: admin123
```

### 8.4 — Verify

```bash
./verify-phase5.sh
```

Check in Grafana:
- Dashboards → Flask Microservices (metrics)
- Explore → Loki (logs)
- Explore → Tempo (traces)
- Click a trace_id in logs → it jumps to Tempo (correlation)

---

## Step 9 — Deploy Phase 6: Advanced Platform

### 9.1 — Install Linkerd

```bash
./install-linkerd.sh
```

### 9.2 — Inject mesh into app namespaces

```bash
./inject-linkerd-mesh.sh
```

Pods should now show `2/2 READY` (app + linkerd-proxy sidecar).

### 9.3 — Verify everything

```bash
./verify-phase6.sh
```

### 9.4 — Run demos

```bash
# Zero-trust proof (Linkerd mTLS + identity)
./verify-linkerd.sh

# KEDA autoscaling (replicas: 2 → 4 → 2)
./load-test-keda.sh

# Node failure resilience
./node-failure-test.sh
```

---

## Final Verification — All 15 ArgoCD Apps Healthy

```bash
kubectl get applications -n argocd
```

Expected:

| Application | Sync | Health |
|-------------|------|--------|
| namespaces | Synced | Healthy |
| gcr-pull-secret | Synced | Healthy |
| sealed-secrets | Synced | Healthy |
| security | Synced | Healthy |
| resource-governance | Synced | Healthy |
| database | Synced | Healthy |
| users-service | Synced | Healthy |
| products-service | Synced | Healthy |
| orders-service | Synced | Healthy |
| frontend | Synced | Healthy |
| api-gateway | Synced | Healthy |
| keda | Synced | Healthy |
| monitoring | Synced | Healthy |
| logging | Synced | Healthy |
| linkerd-config | Synced | Healthy |

---

## Quick Reference — What To Demo

| Demo | Script | What It Proves |
|------|--------|---------------|
| API CRUD | `curl http://$GATEWAY/api/users` | Application works end-to-end |
| Grafana dashboards | `./port-forward-grafana.sh` | Metrics, logs, traces visible |
| Log-to-trace | Click trace_id in Loki → Tempo | Correlation works |
| KEDA scale | `./load-test-keda.sh` | Replicas 2→4→2 |
| Linkerd zero-trust | `./verify-linkerd.sh` | mTLS, blocked traffic, least-privilege |
| Node failure | `./node-failure-test.sh` | Resilience, rescheduling |
| Kyverno policy | Deploy root container → blocked | Security enforcement |
| ResourceQuota | Deploy 15 pods → capped | Resource governance |

---

## Troubleshooting Quick Fixes

| Problem | Fix |
|---------|-----|
| Pods stuck in ImagePullBackOff | GCR pull secret missing → run `./create-gcr-secret.sh` |
| DB connection errors | Sealed secrets not created → run `./create-sealed-secrets.sh` |
| ArgoCD app stuck in Unknown | Helm dependencies not built → `helm dependency build helm/chartname` |
| NetworkPolicy blocking traffic | Check `netpol-allow-*` templates exist in security chart |
| Linkerd proxy not injecting | `kubectl annotate ns NAMESPACE linkerd.io/inject=enabled --overwrite` then restart |
| KEDA not scaling | Check Prometheus is reachable from KEDA namespace (NetworkPolicy) |

---

## Reference Guides (in imp/ folder — don't push these)

| File | Covers |
|------|--------|
| `IMPLEMENTATION.md` | Phase 1 Terraform details |
| `CI-PIPELINE-GUIDE.md` | CI workflow details, secrets setup |
| `CD-PIPELINE-GUIDE.md` | ArgoCD setup, Helm chart details |
| `PHASE4-PLATFORM-GUIDE.md` | Database, Gateway, Security details |
| `PHASE5-OBSERVABILITY-GUIDE.md` | Prometheus, Grafana, Loki, Tempo details |
| `PHASE6-ADVANCED-PLATFORM-GUIDE.md` | Linkerd, KEDA, ResourceQuota details |

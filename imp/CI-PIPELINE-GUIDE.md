# CI Pipeline Guide — GitHub Actions Build, Scan & Push

Complete setup and operations guide for the CI pipeline (Phase 3).

---

## Architecture Overview

```
Developer pushes code to app/**
        │
        ▼
┌──────────────────────────────────────────────┐
│           GitHub Actions CI Pipeline          │
│                                               │
│  ┌─────────┐ ┌─────────┐ ┌─────────┐ ┌────┐ │
│  │ users   │ │products │ │ orders  │ │ FE │ │  ← Matrix: 4 parallel jobs
│  │ service │ │ service │ │ service │ │    │ │
│  └────┬────┘ └────┬────┘ └────┬────┘ └──┬─┘ │
│       │           │           │          │   │
│       ▼           ▼           ▼          ▼   │
│   [ Docker Build ] ─── Buildx + Layer Cache  │
│       │           │           │          │   │
│       ▼           ▼           ▼          ▼   │
│   [ Trivy Scan ] ─── CRITICAL only, fail CI  │
│       │           │           │          │   │
│       ▼           ▼           ▼          ▼   │
│   [ Push to GCR ] ─── Only if Trivy passes   │
│                                               │
│  ┌─────────────────────────────────────────┐  │
│  │ Update CD Repo — Helm values.yaml tags  │  │
│  └─────────────────────────────────────────┘  │
│                                               │
│  ┌─────────────────────────────────────────┐  │
│  │ Pipeline Summary → GitHub Step Summary  │  │
│  └─────────────────────────────────────────┘  │
└──────────────────────────────────────────────┘
        │
        ▼
   ArgoCD detects change in CD repo → deploys to EKS
```

---

## Pipeline Files

| File | Purpose | Trigger |
|------|---------|---------|
| `.github/workflows/ci.yml` | Main CI — build, scan, push to GCR, update CD repo | Push to `Deloitte-US/HU-DevOps-26-yourname` when `app/**` changes |
| `.github/workflows/pr-check.yml` | PR validation — build + scan only, no push | Pull requests targeting the branch |
| `app/.trivyignore` | Suppress known false-positive CVEs in Trivy scans | Read by Trivy during scan |

---

## 1. Prerequisites

Before the pipeline can run, you need:

1. **GCP infrastructure from Phase 1 Terraform** — the following must exist:
   - GCP project with Container Registry API enabled
   - Workload Identity Federation pool + provider for GitHub OIDC
   - GCP Service Account: `eks-gcr-pusher@<project>.iam.gserviceaccount.com`

2. **Application code from Phase 2** — Dockerfiles for all 4 services

3. **A CD repository** — separate Git repo where Helm charts live, with this structure:
   ```
   helm/
   ├── users-service/values.yaml
   ├── products-service/values.yaml
   ├── orders-service/values.yaml
   └── frontend/values.yaml
   ```
   Each `values.yaml` must have a `tag:` field that the CI pipeline will update.

---

## 2. GitHub Secrets Setup

Go to: **GitHub → Your Repo → Settings → Secrets and variables → Actions → New repository secret**

Add each of these secrets:

| Secret Name | Value | Where to Get It |
|-------------|-------|-----------------|
| `GCP_PROJECT_ID` | Your GCP project ID (e.g., `eks-assignment-01`) | GCP Console → Project selector |
| `WIF_PROVIDER` | Workload Identity Provider resource name | `terraform output -raw gcr_workload_identity_provider` |
| `GCR_SERVICE_ACCOUNT` | GCP service account email | `terraform output -raw gcr_service_account_email` |
| `CD_REPO` | CD repo in `owner/repo` format (e.g., `thimanshu756/hitakshi-cd`) | Your CD Git repository |
| `CD_REPO_PAT` | GitHub Personal Access Token with `repo` scope | See section 2.1 below |

### 2.1 Creating the CD_REPO_PAT

1. Go to **GitHub → Settings → Developer Settings → Personal Access Tokens → Tokens (classic)**
2. Click **Generate new token (classic)**
3. Set:
   - **Note:** `CI CD Repo Access`
   - **Expiration:** 90 days (or as per your security policy)
   - **Scopes:** Check `repo` (full control of private repositories)
4. Click **Generate token**
5. Copy the token immediately (it won't be shown again)
6. Add it as the `CD_REPO_PAT` secret in your app repo

### 2.2 Getting Terraform Outputs

Run these from the `terraform/environments/dev/` directory:

```bash
# Get WIF_PROVIDER value
terraform output -raw gcr_workload_identity_provider

# Get GCR_SERVICE_ACCOUNT value
terraform output -raw gcr_service_account_email
```

### 2.3 Verifying Secrets Are Set

```bash
# List all secrets (won't show values, just names)
gh secret list
```

Expected output:
```
GCP_PROJECT_ID    Updated 2024-XX-XX
WIF_PROVIDER      Updated 2024-XX-XX
GCR_SERVICE_ACCOUNT Updated 2024-XX-XX
CD_REPO           Updated 2024-XX-XX
CD_REPO_PAT       Updated 2024-XX-XX
```

---

## 3. First Run — Triggering the Pipeline

### 3.1 Trigger CI Pipeline (push to branch)

```bash
# Make a small change to any file under app/
echo "# trigger ci" >> app/users-service/requirements.txt

# Commit and push
git add app/users-service/requirements.txt
git commit -m "ci: trigger initial CI pipeline run"
git push origin Deloitte-US/HU-DevOps-26-yourname
```

### 3.2 Trigger PR Check Pipeline

```bash
# Create a feature branch
git checkout -b feature/test-pr-check

# Make a change
echo "# test" >> app/frontend/requirements.txt
git add app/frontend/requirements.txt
git commit -m "test: trigger PR check pipeline"
git push origin feature/test-pr-check

# Create a PR
gh pr create --base "Deloitte-US/HU-DevOps-26-yourname" \
  --title "Test PR Check Pipeline" \
  --body "Testing PR validation workflow"
```

---

## 4. Verification Checklist

After the pipeline runs, verify each component:

### 4.1 GitHub Actions Tab

- [ ] All 4 matrix jobs (users-service, products-service, orders-service, frontend) show green
- [ ] The `update-cd-repo` job shows green
- [ ] The `notify` job posted a pipeline summary

### 4.2 Trivy Scan Artifacts

1. Go to **Actions → Select the workflow run → Artifacts**
2. Download `trivy-results-<service>` for each service
3. Review for any CRITICAL or HIGH vulnerabilities

### 4.3 GCR Images

```bash
# Check each service has images in GCR
gcloud container images list --repository=gcr.io/YOUR_PROJECT_ID

# Check tags for a specific service
gcloud container images list-tags gcr.io/YOUR_PROJECT_ID/users-service
gcloud container images list-tags gcr.io/YOUR_PROJECT_ID/products-service
gcloud container images list-tags gcr.io/YOUR_PROJECT_ID/orders-service
gcloud container images list-tags gcr.io/YOUR_PROJECT_ID/frontend
```

Expected: Each service should have a tag matching the 7-char commit SHA + `latest`.

### 4.4 CD Repo Updated

```bash
# Clone or pull the CD repo
cd /path/to/cd-repo
git pull

# Check that tags were updated
grep "tag:" helm/users-service/values.yaml
grep "tag:" helm/products-service/values.yaml
grep "tag:" helm/orders-service/values.yaml
grep "tag:" helm/frontend/values.yaml
```

All should show the same 7-char SHA from the latest CI run.

### 4.5 OIDC Authentication (No JSON Keys)

In the workflow run logs, find step **"Authenticate to GCP"**. It should show:
```
Successfully generated credentials using Workload Identity Federation
```

If it shows `"Using credential file"`, OIDC is NOT working — check your `WIF_PROVIDER` secret.

---

## 5. How the Pipeline Works — Step by Step

### ci.yml Flow

1. **Trigger:** Push to `Deloitte-US/HU-DevOps-26-yourname` with changes in `app/**`
2. **Job 1 — build-scan-push** (runs 4x in parallel via matrix):
   - Checkout code
   - Generate 7-char SHA tag
   - Authenticate to GCP via OIDC (Workload Identity Federation, no JSON key)
   - Configure Docker to push to `gcr.io`
   - Build image with Buildx (cached layers for speed)
   - **Trivy scan** — fails pipeline on CRITICAL vulnerabilities
   - Upload scan results as artifact (even if scan fails)
   - Push image to GCR (only if Trivy passed)
3. **Job 2 — update-cd-repo** (runs after ALL matrix jobs pass):
   - Checkout the CD repo using PAT
   - `sed` update all `helm/<service>/values.yaml` with new tag
   - Commit with `[skip ci]` to prevent infinite trigger loops
   - Push to CD repo branch
4. **Job 3 — notify** (runs always):
   - Posts pipeline summary table to GitHub Step Summary

### pr-check.yml Flow

1. **Trigger:** Pull request targeting the branch with changes in `app/**`
2. **Job 1 — pr-validation** (4x parallel, `fail-fast: false` to show all failures):
   - Build image locally (no GCR auth needed, no push)
   - Trivy scan in SARIF format → uploaded to GitHub Security tab
   - Trivy scan in table format → uploaded as downloadable artifact
3. **Job 2 — pr-summary**:
   - Posts a single summary comment on the PR with pass/fail status

---

## 6. Key Design Decisions

| Decision | Rationale |
|----------|-----------|
| **Matrix strategy** for services | Builds all 4 in parallel (~4x faster than sequential) |
| **Build first, scan, then push** | Trivy must verify image BEFORE it reaches GCR. Vulnerable images never touch the registry |
| **`ignore-unfixed: true`** in Trivy | Unfixable vulnerabilities create noise without actionable remediation |
| **`CRITICAL` severity only** for CI failure | HIGH would be too noisy and block deployments unnecessarily |
| **`[skip ci]`** in CD repo commit | Prevents infinite loop: CI updates CD → CD triggers CI → loop |
| **7-char SHORT_SHA** as image tag | Sufficient for uniqueness, matches `git log --oneline`, readable in dashboards |
| **Separate `pr-check.yml`** | Different permissions (PR needs write comments), different behavior (no push), cleaner separation |
| **`fail-fast: true`** in ci.yml | If one service has critical vulns, stop immediately — don't waste compute |
| **`fail-fast: false`** in pr-check.yml | Show ALL failures in PR so developer can fix everything in one pass |
| **SARIF format** for PR checks | Integrates with GitHub Security tab for rich vulnerability UI |

---

## 7. Troubleshooting

### OIDC Authentication Failures

**Error:** `Error: Unable to exchange token`
```
# Check WIF_PROVIDER format — must be the full resource name:
# projects/PROJECT_NUMBER/locations/global/workloadIdentityPools/POOL_ID/providers/PROVIDER_ID

# Get the correct value:
cd terraform/environments/dev
terraform output -raw gcr_workload_identity_provider
```

**Error:** `Error: Permission denied on resource`
```
# Verify service account has storage.admin role:
gcloud projects get-iam-policy YOUR_PROJECT_ID \
  --filter="bindings.members:eks-gcr-pusher" \
  --format="table(bindings.role)"
```

### Trivy Scan Failures

**Pipeline fails on CRITICAL vulnerability:**
```
# 1. Download the trivy-results artifact from the Actions run
# 2. Check which CVE failed:
cat trivy-results-users-service.txt

# 3. If it's a false positive, add to .trivyignore:
echo "CVE-2024-XXXXX  # False positive — not applicable to our Flask usage" >> app/.trivyignore

# 4. If it's real, update the base image or dependency:
#    - Check if a newer base image patches it
#    - Check if upgrading the dependency fixes it
```

### CD Repo Update Failures

**Error:** `Permission denied` when pushing to CD repo
```
# CD_REPO_PAT may be expired or have wrong scope
# Regenerate: GitHub → Settings → Developer Settings → Personal Access Tokens
# Required scope: repo (full control)
```

**Error:** `No changes to commit`
```
# This means the image tag in values.yaml already matches the SHA
# This is normal if you re-run the pipeline without new commits
```

### Docker Build Failures

**Error:** `failed to solve: failed to read dockerfile`
```
# Verify Dockerfile exists in the correct location:
ls app/users-service/Dockerfile
ls app/products-service/Dockerfile
ls app/orders-service/Dockerfile
ls app/frontend/Dockerfile
```

**Slow builds:**
```
# Docker layer caching should speed up subsequent builds
# First run will be slow (~2-5 min per service)
# Subsequent runs should be ~30-60 seconds if only code changed
```

### GCR Push Failures

**Error:** `denied: Token exchange failed`
```
# OIDC token exchange issue — check:
# 1. WIF_PROVIDER secret is correct
# 2. GCR_SERVICE_ACCOUNT secret matches the SA email
# 3. The WIF pool has the correct attribute mapping for GitHub
# 4. The SA has roles/storage.admin on the project
```

---

## 8. Maintenance

### Quarterly Review

- [ ] Review and clean up `app/.trivyignore` — remove entries for patched CVEs
- [ ] Rotate `CD_REPO_PAT` if using classic tokens (they expire)
- [ ] Check if GitHub Actions versions need updating (checkout@v4, etc.)
- [ ] Review Trivy severity threshold — consider adding HIGH when base images mature

### Updating the Pipeline

To modify the CI pipeline:
1. Edit `.github/workflows/ci.yml` or `pr-check.yml`
2. The CI pipeline self-triggers when its own file changes (included in paths filter)
3. Test changes on a PR first using `pr-check.yml`

### Adding a New Service

To add a 5th microservice to the pipeline:

1. Add the service directory under `app/new-service/` with a Dockerfile
2. Update the matrix in both `ci.yml` and `pr-check.yml`:
   ```yaml
   matrix:
     service: [users-service, products-service, orders-service, frontend, new-service]
   ```
3. Update the `for` loop in the `update-cd-repo` job:
   ```bash
   for service in users-service products-service orders-service frontend new-service; do
   ```
4. Create `helm/new-service/values.yaml` in the CD repo

---

## 9. Secrets Reference Table

| Secret | Format | Example | Used By |
|--------|--------|---------|---------|
| `GCP_PROJECT_ID` | String | `eks-assignment-01` | ci.yml |
| `WIF_PROVIDER` | Resource path | `projects/123/locations/global/workloadIdentityPools/pool/providers/provider` | ci.yml |
| `GCR_SERVICE_ACCOUNT` | Email | `eks-gcr-pusher@project.iam.gserviceaccount.com` | ci.yml |
| `CD_REPO` | `owner/repo` | `thimanshu756/hitakshi-cd` | ci.yml |
| `CD_REPO_PAT` | Token string | `ghp_xxxxxxxxxxxx` | ci.yml |

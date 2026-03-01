# CD Pipeline Guide — ArgoCD + Helm GitOps Deployment

Complete setup and operations guide for the GitOps CD pipeline (Phase 3 CD).

---

## Architecture Overview

```
┌─────────────────────────────────────────────────────────────┐
│                    CI Pipeline (App Repo)                     │
│  Push code → Build → Trivy Scan → Push GCR → Update CD Repo │
└──────────────────────────────┬──────────────────────────────┘
                               │ Updates values.yaml tag
                               ▼
┌─────────────────────────────────────────────────────────────┐
│                      CD Repo (This Repo)                     │
│                                                               │
│  helm/                 argocd/                                │
│  ├── namespaces/       ├── install/values.yaml                │
│  ├── users-service/    ├── projects/eks-assignment.yaml       │
│  ├── products-service/ └── applicationsets/                   │
│  ├── orders-service/       ├── namespaces-app.yaml            │
│  ├── frontend/             ├── microservices-appset.yaml      │
│  └── gcr-pull-secret/      └── platform-appset.yaml           │
└──────────────────────────────┬──────────────────────────────┘
                               │ ArgoCD polls every 3 min
                               ▼
┌─────────────────────────────────────────────────────────────┐
│                    AWS EKS Cluster                            │
│                                                               │
│  Namespace: argocd          → ArgoCD components               │
│  Namespace: frontend        → Frontend pods (2 replicas)      │
│  Namespace: backend-users   → Users-service pods (2 replicas) │
│  Namespace: backend-products→ Products-service pods           │
│  Namespace: backend-orders  → Orders-service pods             │
│  Namespace: database        → (Phase 4: Percona PostgreSQL)   │
│  Namespace: monitoring      → (Phase 5: Prometheus/Grafana)   │
│  Namespace: api-gateway     → (Phase 4: Kong Gateway)         │
└─────────────────────────────────────────────────────────────┘
```

### Sync Wave Deployment Order

```
Wave -2: namespaces          ← Created first (all 11 namespaces)
    │
    ▼
Wave -1: gcr-pull-secret     ← imagePullSecret in all app namespaces
    │
    ▼
Wave  0: microservices       ← All 4 services deploy in parallel
         (users, products, orders, frontend)
```

Without this ordering:
- Services fail because namespaces don't exist → `NamespaceNotFound`
- Pods fail because imagePullSecret doesn't exist → `ImagePullBackOff`

---

## Prerequisites

| Tool | Version | Install | Verify |
|------|---------|---------|--------|
| kubectl | v1.29+ | `brew install kubectl` | `kubectl version --client` |
| helm | v3.14+ | `brew install helm` | `helm version` |
| git | any | `brew install git` | `git --version` |
| AWS CLI | v2 | `brew install awscli` | `aws --version` |

You also need:
- **kubectl access to EKS** — either from bastion via SSM or local machine
- **GCR service account key** — from Terraform output
- **GitHub PAT** — with `repo` scope for the CD repo

---

## 1. Prepare the CD Repository

### 1.1 Clone or Create the CD Repo

```bash
# Option A: If the CD repo already exists
git clone https://github.com/YOUR_ORG/YOUR_CD_REPO.git
cd YOUR_CD_REPO
git checkout -b HU-DEVOPS-26-yourname

# Option B: Create a new repo on GitHub, then clone
gh repo create YOUR_CD_REPO --private
git clone https://github.com/YOUR_ORG/YOUR_CD_REPO.git
cd YOUR_CD_REPO
git checkout -b HU-DEVOPS-26-yourname
```

### 1.2 Copy CD Repo Files

Copy the entire `cd-repo/` directory contents into your CD repository:

```bash
# From the main project directory
cp -r cd-repo/* /path/to/YOUR_CD_REPO/
```

### 1.3 Replace All Placeholder Values

```bash
cd /path/to/YOUR_CD_REPO

# Find all placeholders
grep -rn "YOUR_ORG\|YOUR_CD_REPO\|YOUR_GCP_PROJECT_ID" --include="*.yaml" .
```

Replace in these files:

| File | Placeholder | Replace With |
|------|-------------|-------------|
| `helm/users-service/values.yaml` | `YOUR_GCP_PROJECT_ID` | Your GCP project ID (e.g., `eks-assignment-01`) |
| `helm/products-service/values.yaml` | `YOUR_GCP_PROJECT_ID` | Same |
| `helm/orders-service/values.yaml` | `YOUR_GCP_PROJECT_ID` | Same |
| `helm/frontend/values.yaml` | `YOUR_GCP_PROJECT_ID` | Same |
| `argocd/projects/eks-assignment.yaml` | `YOUR_ORG/YOUR_CD_REPO` | Your CD repo (e.g., `thimanshu756/hitakshi-cd`) |
| `argocd/applicationsets/namespaces-app.yaml` | `YOUR_ORG/YOUR_CD_REPO` | Same |
| `argocd/applicationsets/microservices-appset.yaml` | `YOUR_ORG/YOUR_CD_REPO` | Same |
| `argocd/applicationsets/platform-appset.yaml` | `YOUR_ORG/YOUR_CD_REPO` | Same |

Quick sed replace (run from CD repo root):

```bash
# Replace GCP project ID in all Helm values
sed -i '' 's/YOUR_GCP_PROJECT_ID/eks-assignment-01/g' helm/*/values.yaml

# Replace repo URL in ArgoCD configs
sed -i '' 's|YOUR_ORG/YOUR_CD_REPO|thimanshu756/hitakshi-cd|g' \
  argocd/projects/eks-assignment.yaml \
  argocd/applicationsets/*.yaml
```

### 1.4 Commit and Push

```bash
git add -A
git commit -m "feat: add Helm charts and ArgoCD configuration"
git push -u origin HU-DEVOPS-26-yourname
```

---

## 2. Connect to EKS Cluster

### Option A: From Bastion via SSM (recommended for private cluster)

```bash
# Start SSM session to bastion
aws ssm start-session --target i-YOUR_BASTION_INSTANCE_ID --region eu-west-1

# On bastion, kubectl is pre-configured by userdata
kubectl get nodes
```

### Option B: From Local Machine (if endpoint_public_access was enabled)

```bash
aws eks update-kubeconfig --name eks-assignment-cluster --region eu-west-1
kubectl get nodes
```

---

## 3. Bootstrap ArgoCD

### 3.1 Get the GCR Key File

```bash
# From terraform/environments/dev/ directory
terraform output -raw gcr_service_account_key | base64 -d > /tmp/gcr-key.json
```

### 3.2 Create GitHub PAT

1. Go to **GitHub > Settings > Developer Settings > Personal Access Tokens > Tokens (classic)**
2. Generate new token with scope: `repo` (full)
3. Copy the token

### 3.3 Run Bootstrap Script

```bash
cd /path/to/YOUR_CD_REPO/scripts
chmod +x bootstrap-argocd.sh create-gcr-secret.sh

# Install ArgoCD and apply all ApplicationSets
./bootstrap-argocd.sh \
  https://github.com/YOUR_ORG/YOUR_CD_REPO \
  ghp_YOUR_GITHUB_PAT
```

The script will:
1. Install ArgoCD via Helm
2. Print admin credentials
3. Add CD repo as a source
4. Apply AppProject
5. Apply ApplicationSets in wave order

### 3.4 Create GCR Pull Secrets

```bash
./create-gcr-secret.sh /tmp/gcr-key.json eks-assignment-01

# Clean up key file
rm /tmp/gcr-key.json
```

---

## 4. Access ArgoCD UI

```bash
# Port-forward ArgoCD server
kubectl port-forward svc/argocd-server -n argocd 8080:80

# Open in browser
# URL:      http://localhost:8080
# Username: admin
# Password: (printed by bootstrap script, or retrieve below)
```

Retrieve password again:
```bash
kubectl -n argocd get secret argocd-initial-admin-secret \
  -o jsonpath="{.data.password}" | base64 -d; echo
```

---

## 5. Verification Checklist

### 5.1 ArgoCD Applications

```bash
kubectl get applications -n argocd
```

Expected output:

| Name | Sync Status | Health Status | Notes |
|------|-------------|---------------|-------|
| namespaces | Synced | Healthy | All 11 namespaces created |
| gcr-pull-secret | Synced | Healthy | Secret in all app namespaces |
| users-service | Synced | Degraded | Expected — no db-credentials yet |
| products-service | Synced | Degraded | Expected — no db-credentials yet |
| orders-service | Synced | Degraded | Expected — no db-credentials yet |
| frontend | Synced | Healthy | No DB dependency |

### 5.2 Namespaces

```bash
kubectl get namespaces --show-labels | grep eks-assignment
```

Should show all 11 namespaces with `project=eks-assignment` label.

### 5.3 Pods

```bash
kubectl get pods -n frontend
kubectl get pods -n backend-users
kubectl get pods -n backend-products
kubectl get pods -n backend-orders
```

- Frontend: 2 pods Running (or Healthy)
- Backend services: 2 pods each, likely CrashLoopBackOff (expected — no DB secret)

### 5.4 Services

```bash
kubectl get svc -A | grep -E "users|products|orders|frontend"
```

All 4 should show ClusterIP services.

### 5.5 GCR Pull Secret

```bash
kubectl get secret gcr-pull-secret -n frontend
kubectl get secret gcr-pull-secret -n backend-users
kubectl get secret gcr-pull-secret -n backend-products
kubectl get secret gcr-pull-secret -n backend-orders
```

### 5.6 Self-Heal Tests

```bash
# Test 1: Delete a pod — should recreate within seconds
kubectl delete pod -n frontend -l app=frontend
kubectl get pods -n frontend -w

# Test 2: Manual scale — should revert within 3 minutes
kubectl scale deploy frontend -n frontend --replicas=5
# Wait up to 3 minutes...
kubectl get pods -n frontend
# Should be back to 2 replicas
```

---

## 6. How the GitOps Flow Works

### Automated Flow (after CI runs)

```
1. Developer pushes code change to app repo (app/**)
2. CI pipeline triggers:
   a. Builds Docker image for changed service
   b. Trivy scans for vulnerabilities
   c. Pushes image to GCR with 7-char SHA tag
   d. Clones THIS CD repo
   e. Updates helm/<service>/values.yaml → tag: "<new-sha>"
   f. Commits with [skip ci] and pushes
3. ArgoCD detects change (polls every 3 min or via webhook):
   a. Compares desired state (Git) vs actual state (cluster)
   b. Runs helm template to generate manifests
   c. Applies diff to cluster
   d. Waits for rollout to complete
4. New version is live on EKS
```

### Manual Sync (if you can't wait 3 minutes)

```bash
# Via ArgoCD CLI
argocd app sync users-service

# Or via kubectl
kubectl annotate application users-service -n argocd \
  argocd.argoproj.io/refresh=hard --overwrite
```

---

## 7. Helm Chart Details

### Backend Services (users, products, orders)

All three backend services share identical templates with different values:

| Config | users-service | products-service | orders-service |
|--------|---------------|-----------------|----------------|
| Namespace | backend-users | backend-products | backend-orders |
| Port | 5000 | 5000 | 5000 |
| Service Port | 80 | 80 | 80 |
| OTEL Name | users-service | products-service | orders-service |
| DB Secret | db-credentials | db-credentials | db-credentials |

Features:
- **2 replicas** with `topologySpreadConstraints` across nodes
- **Non-root** security context (UID 1000)
- **Prometheus annotations** for scraping metrics at `/metrics`
- **Liveness/readiness probes** at `/health` and `/ready`
- **ConfigMap** for non-secret config (DB host, OTEL endpoint)
- **SecretKeyRef** for DB credentials (created in Phase 4)

### Frontend

Same as backend but:
- Port **3000** (not 5000)
- **No DB credentials** — frontend doesn't connect to database
- Config points to **Kong Gateway** URL

---

## 8. Troubleshooting

### ImagePullBackOff

```bash
# Check pod events
kubectl describe pod <pod-name> -n <namespace>

# If "unauthorized" or "authentication required":
# GCR pull secret is missing or invalid
./scripts/create-gcr-secret.sh /path/to/gcr-key.json

# If "image not found":
# Image hasn't been pushed to GCR yet — run CI pipeline first
gcloud container images list-tags gcr.io/YOUR_PROJECT_ID/users-service
```

### CreateContainerConfigError

```bash
# Check pod events
kubectl describe pod <pod-name> -n backend-users

# If "secret db-credentials not found":
# This is EXPECTED before Phase 4
# The db-credentials secret is created by Sealed Secrets in Phase 4
```

### Application OutOfSync

```bash
# Check ArgoCD app details
kubectl get application users-service -n argocd -o yaml

# Common causes:
# 1. Repo credentials wrong — check cd-repo-secret
kubectl get secret cd-repo-secret -n argocd
# 2. Branch name mismatch
# 3. Helm template error — test locally:
helm template users-service helm/users-service/
```

### ArgoCD Not Picking Up Changes

```bash
# Force a refresh
kubectl annotate application users-service -n argocd \
  argocd.argoproj.io/refresh=hard --overwrite

# Check ArgoCD repo-server logs
kubectl logs -n argocd -l app.kubernetes.io/component=repo-server --tail=50

# Check if repo is accessible
kubectl get secret cd-repo-secret -n argocd -o jsonpath='{.data.url}' | base64 -d
```

### Helm Template Errors

```bash
# Debug locally before pushing
helm template users-service helm/users-service/
helm template products-service helm/products-service/
helm template orders-service helm/orders-service/
helm template frontend helm/frontend/

# Lint all charts
helm lint helm/users-service/
helm lint helm/products-service/
helm lint helm/orders-service/
helm lint helm/frontend/
helm lint helm/namespaces/
```

---

## 9. Maintenance

### Updating a Service Image Tag Manually

If you need to deploy a specific version without CI:

```bash
# Edit the values.yaml directly
cd /path/to/cd-repo
vim helm/users-service/values.yaml
# Change tag: "abc1234" to tag: "new1234"

git add helm/users-service/values.yaml
git commit -m "deploy: update users-service to new1234"
git push
```

### Scaling a Service

```bash
# Edit values.yaml
vim helm/users-service/values.yaml
# Change replicaCount: 2 to replicaCount: 3

git add helm/users-service/values.yaml
git commit -m "scale: users-service to 3 replicas"
git push
```

Do NOT use `kubectl scale` — ArgoCD will revert it (self-heal).

### Rollback

```bash
# Option 1: Git revert
git revert HEAD
git push

# Option 2: ArgoCD rollback
argocd app rollback users-service

# Option 3: Deploy previous tag
vim helm/users-service/values.yaml
# Set tag to previous SHA
git add . && git commit -m "rollback: users-service to prev-sha" && git push
```

---

## 10. Expected State Summary

| Component | After Phase 3 CD | After Phase 4 |
|-----------|-----------------|---------------|
| ArgoCD | Running | Running |
| Namespaces (11) | All created | All created |
| GCR pull secrets | Created in 4 namespaces | Managed by SealedSecret |
| Frontend pods | Healthy (2 replicas) | Healthy |
| Backend pods | Degraded (no DB secret) | Healthy |
| Database | Not deployed | Percona PostgreSQL running |
| Kong Gateway | Not deployed | Running |
| Monitoring | Not deployed | Prometheus + Grafana |

The **Degraded** state for backend pods is **expected and correct** at this phase.
Phase 4 will create the `db-credentials` Sealed Secret and Percona PostgreSQL,
which will make all pods Healthy.

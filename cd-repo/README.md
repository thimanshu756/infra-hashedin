# EKS Assignment — CD Repository

GitOps deployment repository for the EKS microservices assignment.
ArgoCD watches this repo and automatically deploys changes to EKS.

## Repository Structure

```
cd-repo/
├── helm/                            ← Helm charts for all components
│   ├── namespaces/                  ← All K8s namespaces (sync wave -2)
│   ├── users-service/               ← Users CRUD backend
│   ├── products-service/            ← Products CRUD backend
│   ├── orders-service/              ← Orders CRUD backend
│   ├── frontend/                    ← Frontend web app
│   └── gcr-pull-secret/             ← GCR imagePullSecret (sync wave -1)
│
├── argocd/                          ← ArgoCD configuration
│   ├── install/values.yaml          ← ArgoCD Helm install values
│   ├── projects/                    ← ArgoCD AppProject
│   └── applicationsets/             ← ApplicationSet definitions
│
├── scripts/                         ← One-time setup scripts
│   ├── bootstrap-argocd.sh          ← Install ArgoCD + apply apps
│   └── create-gcr-secret.sh         ← Create GCR pull secrets
│
└── README.md
```

## Sync Wave Order

ArgoCD deploys resources in this order:

| Wave | Component | Why |
|------|-----------|-----|
| -2 | namespaces | Must exist before any resource is created |
| -1 | gcr-pull-secret | Must exist before pods try to pull images |
| 0 | microservices | All 4 services deploy last |

## Prerequisites

- `kubectl` configured with EKS cluster access (via bastion SSM or local)
- `helm` v3 installed
- GCR service account key JSON file (from Terraform output)
- GitHub PAT with `repo` scope for this CD repo

## Quick Start

### 1. Update Placeholder Values

Replace `YOUR_ORG/YOUR_CD_REPO` and `YOUR_GCP_PROJECT_ID` in these files:

```bash
# Find all placeholders
grep -r "YOUR_ORG\|YOUR_CD_REPO\|YOUR_GCP_PROJECT_ID" --include="*.yaml" .
```

Files to update:
- `helm/users-service/values.yaml` — image repository
- `helm/products-service/values.yaml` — image repository
- `helm/orders-service/values.yaml` — image repository
- `helm/frontend/values.yaml` — image repository
- `argocd/projects/eks-assignment.yaml` — sourceRepos
- `argocd/applicationsets/namespaces-app.yaml` — repoURL
- `argocd/applicationsets/microservices-appset.yaml` — repoURL
- `argocd/applicationsets/platform-appset.yaml` — repoURL

### 2. Bootstrap ArgoCD

```bash
cd scripts
chmod +x bootstrap-argocd.sh create-gcr-secret.sh

# Install ArgoCD and apply all ApplicationSets
./bootstrap-argocd.sh https://github.com/YOUR_ORG/YOUR_CD_REPO ghp_YOUR_PAT
```

### 3. Create GCR Pull Secrets

```bash
# Get GCR key from Terraform
cd /path/to/terraform/environments/dev
terraform output -raw gcr_service_account_key | base64 -d > /tmp/gcr-key.json

# Create secrets in all namespaces
cd /path/to/cd-repo/scripts
./create-gcr-secret.sh /tmp/gcr-key.json

# Clean up key file
rm /tmp/gcr-key.json
```

### 4. Access ArgoCD UI

```bash
kubectl port-forward svc/argocd-server -n argocd 8080:80
# Open http://localhost:8080
# Username: admin
# Password: (printed by bootstrap script)
```

## How Ongoing Deployments Work

```
Developer pushes code → CI builds + scans → CI pushes to GCR
    → CI updates values.yaml tag in THIS repo
    → ArgoCD detects change (polls every 3 min)
    → ArgoCD syncs new image to EKS
```

The CI pipeline (`ci.yml` in the app repo) automatically:
1. Builds Docker images
2. Scans with Trivy
3. Pushes to GCR
4. Updates `helm/<service>/values.yaml` → `tag: "<7-char-sha>"`
5. Commits with `[skip ci]` to prevent loops

ArgoCD picks up the tag change and rolls out the new version.

## Verification

```bash
# Check all ArgoCD applications
kubectl get applications -n argocd

# Expected output:
# NAME               SYNC STATUS   HEALTH STATUS
# namespaces         Synced        Healthy
# gcr-pull-secret    Synced        Healthy
# users-service      Synced        Degraded  ← Expected until Phase 4
# products-service   Synced        Degraded  ← Expected until Phase 4
# orders-service     Synced        Degraded  ← Expected until Phase 4
# frontend           Synced        Healthy

# Check pods
kubectl get pods -n backend-users
kubectl get pods -n backend-products
kubectl get pods -n backend-orders
kubectl get pods -n frontend

# Check services
kubectl get svc -A | grep -E "users|products|orders|frontend"
```

## Self-Heal Tests

```bash
# Test 1: Delete a pod — ArgoCD recreates it
kubectl delete pod -n backend-users -l app=users-service
# Pod recreates within seconds

# Test 2: Scale manually — ArgoCD reverts it
kubectl scale deploy users-service -n backend-users --replicas=5
# Reverts to 2 within 3 minutes (reconciliation interval)
```

## Expected State After This Phase

Before Phase 4 (database + secrets):
- All ArgoCD applications: **Synced**
- Backend pods: **Degraded** (crash-looping because `db-credentials` secret doesn't exist yet)
- Frontend pods: **Healthy** (no DB dependency)
- This is **normal and expected** — Phase 4 creates the database and secrets

## Troubleshooting

| Problem | Cause | Fix |
|---------|-------|-----|
| `ImagePullBackOff` | GCR pull secret missing or invalid | Run `create-gcr-secret.sh` again |
| `CreateContainerConfigError` | `db-credentials` secret missing | Expected — fixed in Phase 4 |
| Application stuck `OutOfSync` | Repo credentials wrong | Check `cd-repo-secret` in argocd namespace |
| `ComparisonError` | Helm template syntax error | Run `helm template helm/<service>` locally to debug |

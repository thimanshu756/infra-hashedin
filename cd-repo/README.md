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
│   └── frontend/                    ← Frontend web app
│
├── argocd/                          ← ArgoCD configuration
│   ├── install/values.yaml          ← ArgoCD Helm install values
│   ├── projects/                    ← ArgoCD AppProject
│   └── applicationsets/             ← ApplicationSet definitions
│
├── scripts/                         ← One-time setup scripts
│   ├── bootstrap-argocd.sh          ← Install ArgoCD + apply apps
│   └── create-sealed-secrets.sh     ← Create sealed DB credentials
│
└── README.md
```

## Sync Wave Order

ArgoCD deploys resources in this order:

| Wave | Component | Why |
|------|-----------|-----|
| -2 | namespaces | Must exist before any resource is created |
| -1 | sealed-secrets, security, resource-governance | Core prerequisites |
| 0 | microservices | All 4 services deploy after prerequisites |
| 1 | keda, api-gateway | Post-microservice components |
| 2 | monitoring, logging | Observability stack |
| 3 | linkerd-config | Service mesh policies |

## Prerequisites

- `kubectl` configured with EKS cluster access (via bastion SSM or local)
- `helm` v3 installed
- GitHub PAT with `repo` scope for this CD repo

## Quick Start

### 1. Update Placeholder Values

Replace `YOUR_AWS_ACCOUNT_ID` in the Helm values files:

```bash
# Find all placeholders
grep -r "YOUR_AWS_ACCOUNT_ID" --include="*.yaml" .
```

Files to update:
- `helm/users-service/values.yaml` — image repository
- `helm/products-service/values.yaml` — image repository
- `helm/orders-service/values.yaml` — image repository
- `helm/frontend/values.yaml` — image repository

### 2. Bootstrap ArgoCD

```bash
cd scripts
chmod +x bootstrap-argocd.sh

# Install ArgoCD and apply all ApplicationSets
./bootstrap-argocd.sh https://github.com/Deloitte-DT-Training/HU-DevOps-26-highai-cd ghp_YOUR_PAT
```

### 3. Access ArgoCD UI

```bash
kubectl port-forward svc/argocd-server -n argocd 8080:80
# Open http://localhost:8080
# Username: admin
# Password: (printed by bootstrap script)
```

## Image Registry — AWS ECR

This project uses **AWS ECR** (Elastic Container Registry). EKS nodes have
the `AmazonEC2ContainerRegistryReadOnly` IAM policy attached, so they can
pull images from ECR **natively without imagePullSecrets**.

Image format: `<ACCOUNT_ID>.dkr.ecr.us-west-1.amazonaws.com/<service>:<tag>`

## How Ongoing Deployments Work

```
Developer pushes code → CI builds + scans → CI pushes to ECR
    → CI updates values.yaml tag in THIS repo
    → ArgoCD detects change (polls every 3 min)
    → ArgoCD syncs new image to EKS
```

The CI pipeline (`ci.yml` in the app repo) automatically:
1. Builds Docker images
2. Scans with Trivy
3. Pushes to ECR
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
# sealed-secrets     Synced        Healthy
# security           Synced        Healthy
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
| `ImagePullBackOff` | ECR repo doesn't exist or node IAM role missing | Verify ECR repos exist and nodes have `AmazonEC2ContainerRegistryReadOnly` |
| `CreateContainerConfigError` | `db-credentials` secret missing | Expected — fixed in Phase 4 |
| Application stuck `OutOfSync` | Repo credentials wrong | Check `cd-repo-secret` in argocd namespace |
| `ComparisonError` | Helm template syntax error | Run `helm template helm/<service>` locally to debug |

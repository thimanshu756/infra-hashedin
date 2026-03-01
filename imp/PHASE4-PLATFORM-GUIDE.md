# Phase 4 Platform Guide — Database, API Gateway, Security

Complete setup guide for Percona PostgreSQL, Kong Gateway, Sealed Secrets,
Kyverno policies, and NetworkPolicies on EKS.

---

## Architecture Overview

```
                        Internet
                           │
                           ▼
┌──────────────────────────────────────────────┐
│         Kong Gateway (LoadBalancer)           │
│         namespace: api-gateway                │
│                                               │
│  /              → frontend (port 3000)        │
│  /api/users     → users-service (port 5000)   │
│  /api/products  → products-service (port 5000)│
│  /api/orders    → orders-service (port 5000)  │
└──────────────┬───────────────────────────────┘
               │ NetworkPolicy: allow-from-gateway
               ▼
┌──────────────────────────────────────────────┐
│            Microservices                      │
│  frontend        │ backend-users              │
│  backend-products│ backend-orders             │
└──────────────┬───────────────────────────────┘
               │ NetworkPolicy: allow-to-database
               ▼
┌──────────────────────────────────────────────┐
│        Percona PostgreSQL + PgBouncer        │
│        namespace: database                    │
│        DB: appdb | User: appuser              │
│        NetworkPolicy: allow-from-backends     │
└──────────────────────────────────────────────┘

Security Layer:
  ┌─────────────────────┐  ┌─────────────────────┐
  │ Kyverno             │  │ Sealed Secrets       │
  │ - No root containers│  │ - Encrypted DB creds │
  │ - Require limits    │  │ - Safe to commit     │
  │ - Audit :latest tag │  │ - Auto-decrypted     │
  └─────────────────────┘  └─────────────────────┘
```

### Sync Wave Deployment Order

```
Wave -2: namespaces              ← All 11 namespaces
Wave -1: sealed-secrets          ← Controller must exist before sealed secrets
         gcr-pull-secret         ← imagePullSecret for GCR
         security (Kyverno)      ← Policies ready before pods deploy
Wave  0: database (Percona)      ← PostgreSQL starts up
         microservices           ← All 4 services deploy
Wave  1: api-gateway (Kong routes)← Routes target existing services
```

---

## Prerequisites

| Tool | Install | Verify |
|------|---------|--------|
| kubectl | `brew install kubectl` | `kubectl version --client` |
| helm v3 | `brew install helm` | `helm version` |
| kubeseal | `brew install kubeseal` | `kubeseal --version` |
| ArgoCD running | Phase 3 setup | `kubectl get pods -n argocd` |
| All namespaces created | Phase 3 | `kubectl get namespaces` |

---

## Setup Steps (Exact Order)

### Step 1 — Install Kong Gateway Controller

Kong must be installed manually before ArgoCD can manage Gateway API resources,
because the CRDs must exist first.

```bash
cd /path/to/cd-repo/scripts
chmod +x install-kong.sh create-sealed-secrets.sh verify-phase4.sh

./install-kong.sh
```

This will:
- Install Gateway API CRDs (GatewayClass, Gateway, HTTPRoute)
- Install Kong Ingress Controller in `api-gateway` namespace
- Wait for AWS LoadBalancer IP assignment (~2-3 min)

Verify:
```bash
kubectl get pods -n api-gateway
kubectl get svc -n api-gateway
# Wait for EXTERNAL-IP to appear
```

### Step 2 — Replace Placeholder Values

```bash
cd /path/to/cd-repo

# Replace GCP project ID in all values.yaml (if not done in Phase 3)
sed -i '' 's/YOUR_GCP_PROJECT_ID/eks-assignment-01/g' helm/*/values.yaml

# Replace repo URL in new ArgoCD files
sed -i '' 's|YOUR_ORG/YOUR_CD_REPO|thimanshu756/hitakshi-cd|g' \
  argocd/applicationsets/platform-phase4-apps.yaml
```

### Step 3 — Build Helm Dependencies

The database, sealed-secrets, and security charts have subchart dependencies.
They need `helm dependency build` before ArgoCD can render them.

```bash
cd /path/to/cd-repo

# Build dependencies for each chart with subcharts
helm dependency build helm/database/
helm dependency build helm/sealed-secrets/
helm dependency build helm/security/
```

This creates `charts/` directories with the subchart tarballs.
Commit these so ArgoCD can use them.

### Step 4 — Push Phase 4 Charts to CD Repo

```bash
cd /path/to/cd-repo

git add helm/database helm/api-gateway helm/sealed-secrets helm/security
git add argocd/applicationsets/platform-appset.yaml
git add argocd/applicationsets/platform-phase4-apps.yaml

git commit -m "feat: add Phase 4 platform components (DB, Gateway, Security)"
git push origin HU-DEVOPS-26-yourname
```

### Step 5 — Apply Phase 4 ArgoCD Apps

ArgoCD should auto-sync the updated platform-appset.yaml. If needed, manually apply:

```bash
kubectl apply -f argocd/applicationsets/platform-appset.yaml
kubectl apply -f argocd/applicationsets/platform-phase4-apps.yaml
```

Watch sync progress:
```bash
kubectl get applications -n argocd -w
```

### Step 6 — Wait for Percona PostgreSQL (~3-5 min)

```bash
kubectl get pods -n database -w
```

Wait until you see:
```
percona-db-primary-0   1/1   Running   0   3m
percona-db-pgbouncer-xxx   1/1   Running   0   2m
```

Verify the appuser secret was created:
```bash
kubectl get secrets -n database | grep appuser
```

### Step 7 — Create Sealed Secrets for DB Credentials

This fetches the Percona-generated password, encrypts it with kubeseal,
and saves the encrypted files to the Helm chart directory.

```bash
cd /path/to/cd-repo/scripts
./create-sealed-secrets.sh
```

This creates:
- `helm/sealed-secrets/templates/sealed-db-backend-users.yaml`
- `helm/sealed-secrets/templates/sealed-db-backend-products.yaml`
- `helm/sealed-secrets/templates/sealed-db-backend-orders.yaml`

### Step 8 — Commit and Push Sealed Secret Files

The sealed files are **encrypted** and safe to commit to Git.

```bash
cd /path/to/cd-repo
git add helm/sealed-secrets/templates/sealed-db-*.yaml
git commit -m "feat: add sealed DB credentials [skip ci]"
git push origin HU-DEVOPS-26-yourname
```

ArgoCD syncs these files. The Sealed Secrets controller decrypts them
and creates real `db-credentials` K8s Secrets in each backend namespace.

Backend pods will automatically restart and connect to PostgreSQL.
Pod health changes: **Degraded -> Healthy**

### Step 9 — Verify Everything

```bash
cd /path/to/cd-repo/scripts
./verify-phase4.sh
```

---

## Component Details

### Percona PostgreSQL

| Property | Value |
|----------|-------|
| Namespace | database |
| Cluster name | percona-db |
| Instances | 1 (single — dev assignment) |
| Storage | 10Gi gp2 EBS |
| PgBouncer | Enabled (connection pooling) |
| Database | appdb |
| User | appuser |
| PgBouncer endpoint | `percona-db-pgbouncer.database.svc.cluster.local:6432` |
| Direct endpoint | `percona-db-primary.database.svc.cluster.local:5432` |

Backend services connect to PgBouncer (port 6432) for connection pooling.

Secret created by Percona: `percona-db-pguser-appuser` in database namespace
Contains: user, password, host, port, dbname, pgbouncer-host

### Kong Gateway

| Property | Value |
|----------|-------|
| Namespace | api-gateway |
| Type | LoadBalancer (AWS ELB) |
| GatewayClass | kong |
| Controller | Kong Ingress Controller |

Routes:

| Path | Target Service | Target Namespace | Port |
|------|----------------|------------------|------|
| `/` | frontend | frontend | 80 → 3000 |
| `/api/users` | users-service | backend-users | 80 → 5000 |
| `/api/products` | products-service | backend-products | 80 → 5000 |
| `/api/orders` | orders-service | backend-orders | 80 → 5000 |

ReferenceGrants in each target namespace allow cross-namespace routing.

### Kyverno Policies

| Policy | Mode | Effect |
|--------|------|--------|
| disallow-root-user | **Enforce** | REJECT pods without runAsNonRoot: true |
| require-resource-limits | **Enforce** | REJECT pods without CPU/memory limits |
| disallow-latest-tag | **Audit** | LOG (don't block) pods using :latest tag |

Scope: Only app namespaces (frontend, backend-*). System namespaces excluded.

### Network Policies

| Policy | Namespace(s) | Effect |
|--------|-------------|--------|
| default-deny-all | All 4 app namespaces | Block ALL traffic by default |
| allow-dns-egress | All 4 app namespaces | Allow DNS resolution (port 53) |
| allow-from-gateway | All 4 app namespaces | Allow ingress from api-gateway |
| allow-to-database | 3 backend namespaces | Allow egress to database (5432, 6432) |
| allow-from-backends | database | Allow ingress from backend namespaces |

Traffic flow:
```
Internet → Kong (api-gateway) → Frontend / Backends → Database
              allowed by:          allowed by:         allowed by:
          allow-from-gateway    allow-to-database    allow-from-backends
```

---

## Verification Checklist

### After Step 9 (all healthy):

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
| database | Synced | Healthy |
| users-service | Synced | Healthy |
| products-service | Synced | Healthy |
| orders-service | Synced | Healthy |
| frontend | Synced | Healthy |
| api-gateway | Synced | Healthy |

```bash
kubectl get pods -A | grep -E "database|backend|frontend|api-gateway|sealed|security"
```

All pods should be Running.

### End-to-End Test

```bash
# Get Kong LoadBalancer hostname
EXTERNAL=$(kubectl get svc -n api-gateway \
  -o jsonpath='{.items[0].status.loadBalancer.ingress[0].hostname}')

# Test all routes
curl http://$EXTERNAL/                  # Frontend HTML
curl http://$EXTERNAL/api/users         # Users JSON
curl http://$EXTERNAL/api/products      # Products JSON
curl http://$EXTERNAL/api/orders        # Orders JSON

# Test CRUD
curl -X POST http://$EXTERNAL/api/users \
  -H "Content-Type: application/json" \
  -d '{"name":"Test User","email":"test@test.com","role":"admin"}'

curl http://$EXTERNAL/api/users         # Should show the new user
```

### Kyverno Test

```bash
# This should be REJECTED (no runAsNonRoot)
kubectl run root-test --image=nginx --restart=Never \
  --namespace=backend-users \
  --overrides='{"spec":{"securityContext":{"runAsUser":0,"runAsNonRoot":false},"containers":[{"name":"test","image":"nginx","resources":{"limits":{"cpu":"100m","memory":"128Mi"}}}]}}'

# Expected: "admission webhook denied the request"
```

### NetworkPolicy Test

```bash
# From database namespace, try to reach backend (should FAIL)
kubectl run nettest --image=busybox --restart=Never \
  --namespace=database --rm -it --timeout=10s \
  -- wget -qO- --timeout=5 http://users-service.backend-users.svc.cluster.local/health

# Expected: timeout (network policy blocks it)
```

---

## Troubleshooting

### Percona PostgreSQL

**Pods stuck in Pending:**
```bash
# Check if storage class exists
kubectl get sc gp2
# If not, the EKS cluster may not have gp2 provisioner
# Try: kubectl get sc   (see what's available)
# Update values.yaml storageClass accordingly
```

**Pods CrashLoopBackOff:**
```bash
kubectl logs -n database percona-db-primary-0
# Common: insufficient memory — increase limits in values.yaml
```

**Secret not created:**
```bash
kubectl get secrets -n database
# Percona creates secrets after cluster is fully initialized
# Wait 3-5 minutes after pods are Running
```

### Kong Gateway

**No EXTERNAL-IP after 5 minutes:**
```bash
kubectl describe svc -n api-gateway | grep -A5 Events
# Check if AWS Load Balancer Controller is working
# Check EKS node security group allows outbound to ELB
```

**HTTPRoute not working (404):**
```bash
# Check Gateway status
kubectl describe gateway kong-gateway -n api-gateway
# Check HTTPRoute status
kubectl describe httproute users-route -n api-gateway
# Check ReferenceGrant exists in target namespace
kubectl get referencegrant -n backend-users
```

### Sealed Secrets

**kubeseal fails with "cannot fetch certificate":**
```bash
# Check controller is running
kubectl get pods -n sealed-secrets
# Check service exists
kubectl get svc -n sealed-secrets
# The controller may not be ready yet — wait and retry
```

**SealedSecret applied but real secret not created:**
```bash
# Check controller logs
kubectl logs -n sealed-secrets -l app.kubernetes.io/name=sealed-secrets
# Common: SealedSecret was encrypted for a different cluster
# Re-run create-sealed-secrets.sh to re-encrypt with current key
```

### Kyverno

**Pods rejected unexpectedly:**
```bash
# Check which policy blocked it
kubectl get events -n backend-users --sort-by='.lastTimestamp' | grep -i deny

# If legitimate pod blocked, check your deployment has:
#   securityContext.runAsNonRoot: true
#   resources.limits.cpu and resources.limits.memory
```

**Kyverno not blocking anything:**
```bash
# Check policies are in Enforce mode
kubectl get clusterpolicy -o wide
# Check webhook is registered
kubectl get validatingwebhookconfigurations | grep kyverno
```

### NetworkPolicies

**Services can't reach database:**
```bash
# Check namespace labels (NetworkPolicy uses label selectors)
kubectl get namespace database --show-labels
# Must have: kubernetes.io/metadata.name=database

# If missing:
kubectl label namespace database kubernetes.io/metadata.name=database --overwrite
```

**Everything blocked after applying policies:**
```bash
# DNS must work — check allow-dns-egress exists
kubectl get networkpolicy allow-dns-egress -n backend-users
# If missing, pods can't resolve any service names
```

---

## Maintenance

### Rotating DB Password

```bash
# 1. Update password in Percona (or let operator rotate)
# 2. Re-run create-sealed-secrets.sh to re-encrypt with new password
cd scripts && ./create-sealed-secrets.sh
# 3. Commit and push new sealed secrets
git add helm/sealed-secrets/templates/sealed-db-*.yaml
git commit -m "rotate: update DB credentials"
git push
# 4. ArgoCD applies new secrets, pods restart automatically
```

### Backing Up Sealed Secrets Master Key

```bash
# CRITICAL — do this after initial setup
kubectl get secret -n sealed-secrets \
  -l sealedsecrets.bitnami.com/sealed-secrets-key \
  -o yaml > sealed-secrets-master-key-backup.yaml

# Store this SECURELY — NEVER commit to Git
# If you lose this key and recreate the cluster,
# all existing SealedSecrets become undecryptable
```

### Adding a New Service

1. Create Helm chart in `helm/new-service/`
2. Add namespace to `helm/namespaces/templates/namespaces.yaml`
3. Add to microservices-appset.yaml generator list
4. Add NetworkPolicies for the new namespace in security chart
5. Add HTTPRoute in api-gateway chart
6. Create sealed DB credentials for new namespace
7. Commit and push — ArgoCD handles the rest

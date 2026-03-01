# Phase 6 Advanced Platform Guide — Linkerd, KEDA, Resource Governance, Resilience

Complete setup guide for the final production hardening layer on EKS.

---

## Architecture Overview

```
                          ┌─────────────────────────────────┐
                          │       External Traffic           │
                          └──────────┬──────────────────────┘
                                     │
                          ┌──────────▼──────────────────────┐
                          │   Kong Gateway (api-gateway)     │
                          │   NOT meshed — L4 routing only   │
                          └──┬──────────┬──────────┬────────┘
                             │ mTLS     │ mTLS     │ mTLS
                     ┌───────▼───┐ ┌───▼───────┐ ┌▼──────────┐
                     │ frontend  │ │  users    │ │ products   │
                     │  :3000    │ │  :5000    │ │  :5000     │
                     │ MESHED    │ │ MESHED    │ │ MESHED     │
                     │ 2/2 pods  │ │ 2-4 pods  │ │ 2/2 pods   │
                     └───────────┘ │ (KEDA)    │ └────────────┘
                                   └───────────┘
                                        │
                     ┌──────────────────▼────────────────────┐
                     │   Percona PostgreSQL (database)       │
                     │   NOT meshed — stateful, excluded     │
                     └──────────────────────────────────────┘

Security Layers:
  L3/L4: NetworkPolicy (default-deny + explicit allow)
  L7:    Linkerd ServerAuthorization (identity-based mTLS)
  Gov:   ResourceQuota + LimitRange (resource caps)
  Scale: KEDA ScaledObject (event-driven autoscaling)
```

---

## Components Deployed

### Linkerd Service Mesh

| Component | Location | Purpose |
|-----------|----------|---------|
| Linkerd Control Plane | `linkerd` namespace | mTLS, identity, proxy management |
| Linkerd Viz | `linkerd-viz` namespace | Dashboard, metrics, tap |
| Linkerd Proxy | Sidecar in app pods | mTLS termination, policy enforcement |
| Server resources | App namespaces | Define protected ports |
| ServerAuthorization | App namespaces | Define allowed identities |

### KEDA Autoscaling

| Component | Location | Purpose |
|-----------|----------|---------|
| KEDA Operator | `keda` namespace | Watches ScaledObjects, manages HPA |
| KEDA Metrics Server | `keda` namespace | Serves external metrics to HPA |
| ScaledObject | `backend-users` | Scales users-service on Prometheus metrics |

### Resource Governance

| Component | Namespaces | Purpose |
|-----------|------------|---------|
| ResourceQuota | 8 namespaces | CPU/memory/pod caps per namespace |
| LimitRange | 4 app namespaces | Default resource requests/limits |

---

## Prerequisites

- Phases 1-5 complete (all pods healthy, observability stack running)
- kubectl access to EKS cluster
- helm v3 installed

---

## Setup Steps

### Step 1 — Install Linkerd Control Plane (manual, once)

```bash
cd scripts
chmod +x install-linkerd.sh inject-linkerd-mesh.sh verify-linkerd.sh
chmod +x load-test-keda.sh node-failure-test.sh verify-phase6.sh

./install-linkerd.sh
```

This installs:
- Linkerd CRDs
- Linkerd control plane (1 replica, resource-constrained for dev)
- Linkerd Viz (dashboard)

Verify: `linkerd check` should show all green.

### Step 2 — Build Helm Dependencies

```bash
cd /path/to/cd-repo
helm dependency build helm/keda/
```

Note: `linkerd-config` and `resource-governance` have no subchart dependencies.

### Step 3 — Push Phase 6 Charts to CD Repo

```bash
git add helm/linkerd helm/keda helm/resource-governance
git add argocd/applicationsets/platform-appset.yaml
git add docs/linkerd-zero-trust-proof.md
git add docs/keda-autoscaling-proof.md
git add docs/node-failure-analysis.md
git add scripts/install-linkerd.sh scripts/inject-linkerd-mesh.sh
git add scripts/verify-linkerd.sh scripts/load-test-keda.sh
git add scripts/node-failure-test.sh scripts/verify-phase6.sh
git commit -m "feat: add Phase 6 linkerd, keda, resource governance"
git push origin HU-DEVOPS-26-yourname
```

### Step 4 — ArgoCD Syncs Resource Governance (Wave -1)

```bash
kubectl get applications -n argocd -w
```

Wait for `resource-governance` to appear and show `Synced`.

```bash
# Verify quotas are applied
kubectl get resourcequota -A | grep -v "^kube"
kubectl get limitrange -A | grep -v "^kube"
```

### Step 5 — ArgoCD Syncs KEDA (Wave 1)

```bash
kubectl get pods -n keda
kubectl get scaledobject -A
```

Expected:
```
NAME                                  READY   STATUS
keda-operator-xxx                     1/1     Running
keda-operator-metrics-apiserver-xxx   1/1     Running
```

### Step 6 — Inject Linkerd Mesh Into App Namespaces

```bash
./inject-linkerd-mesh.sh
```

This:
1. Annotates 4 namespaces with `linkerd.io/inject=enabled`
2. Rolling restarts all 4 deployments
3. Waits for rollouts to complete
4. Verifies pods show 2/2 READY (app + linkerd-proxy)

### Step 7 — ArgoCD Syncs Linkerd Config (Wave 3)

After mesh injection, ArgoCD applies Server + ServerAuthorization policies:

```bash
kubectl get server -A
kubectl get serverauthorization -A
```

### Step 8 — Run All Demos

```bash
# Zero-trust proof
./verify-linkerd.sh

# KEDA autoscaling demo
./load-test-keda.sh

# Node failure resilience test
./node-failure-test.sh

# Full Phase 6 verification
./verify-phase6.sh
```

---

## Complete Sync Wave Order (All Phases)

```
Wave -2: namespaces
Wave -1: sealed-secrets, gcr-pull-secret, security (Kyverno + NetPols), resource-governance
Wave  0: database (Percona), microservices (4 services)
Wave  1: api-gateway (Kong routes), keda
Wave  2: monitoring (Prometheus + Grafana + Tempo + OTEL), logging (Loki + Promtail)
Wave  3: linkerd-config (Server + ServerAuthorization policies)
```

---

## Demo Scripts — What to Show

### 1. KEDA Autoscaling (`load-test-keda.sh`)

**What evaluator sees:**
```
── Phase 1: Baseline ──
  Replicas: 2

── Phase 2: Applying load ──
  [14:00:15] Replicas: 2
  [14:00:30] Replicas: 3   ← scale-out triggered
  [14:01:00] Replicas: 4   ← at max

── Phase 3: Stopping load ──
── Phase 4: Scale-in ──
  [14:03:05] Replicas: 3   ← cooling down
  [14:04:05] Replicas: 2   ← back to min
```

### 2. Linkerd Zero-Trust (`verify-linkerd.sh`)

**What evaluator sees:**
```
── TEST 1: mTLS proof ──
  Edges show SECURED=√

── TEST 2: Non-meshed BLOCKED ──
  curl from database → users-service: Connection timed out
  PASS: Non-meshed traffic BLOCKED

── TEST 3: Wrong meshed identity DENIED ──
  products-service → users-service: 403 Forbidden
  PASS: products-service DENIED

── TEST 4: Allowed identity PERMITTED ──
  gateway → users-service: HTTP 200
  PASS: Gateway allowed

── TEST 5: Defense in Depth ──
  NetworkPolicy (L3/L4) + Linkerd (L7) = dual enforcement
```

### 3. Node Failure (`node-failure-test.sh`)

**What evaluator sees:**
```
── Baseline: pods spread across 2 nodes ──
── Cordon node-1 ──
── Drain node-1 ──
── Pods rescheduling to node-2 ──
── API still returning HTTP 200 ──
── ArgoCD still Synced ──
── Uncordon: node restored ──

Key findings:
  ✅ Stateless services survived
  ⚠️  PostgreSQL had ~30-60s unavailability (single instance — documented)
  ✅ ArgoCD continued reconciling
  ✅ Grafana captured the event
```

---

## Healthy State After Phase 6

```bash
kubectl get applications -n argocd
```

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

**All 15 applications: Synced + Healthy**

```bash
kubectl get pods -n backend-users
```
```
NAME                              READY   STATUS    RESTARTS
users-service-xxx-yyy             2/2     Running   0        ← app + linkerd-proxy
users-service-xxx-zzz             2/2     Running   0
```

```bash
kubectl get scaledobject -n backend-users
```
```
NAME                    READY   ACTIVE
users-service-scaler    True    False     ← False = no load currently
```

```bash
kubectl get resourcequota -n backend-users
```
```
NAME              AGE
namespace-quota   5m
  Resource          Used    Hard
  limits.cpu        600m    1000m
  limits.memory     512Mi   1Gi
  pods              2       10
  requests.cpu      200m    500m
  requests.memory   256Mi   512Mi
```

---

## Resource Summary

Additional resources for Phase 6:

| Component | CPU Request | Memory Request | CPU Limit | Memory Limit |
|-----------|------------|---------------|----------|-------------|
| Linkerd Control Plane | 200m | 256Mi | 600m | 512Mi |
| Linkerd Viz | 100m | 128Mi | 300m | 256Mi |
| Linkerd Proxies (x8) | ~80m | ~256Mi | ~800m | ~1Gi |
| KEDA Operator | 50m | 64Mi | 200m | 256Mi |
| KEDA Metrics Server | 50m | 64Mi | 200m | 256Mi |
| **Total** | **~480m** | **~768Mi** | **~2100m** | **~2.3Gi** |

Note: ResourceQuota and LimitRange consume zero runtime resources — they are
admission-time enforcement only.

---

## Troubleshooting

### Linkerd Proxy Not Injecting

```bash
# Check namespace annotation
kubectl get namespace backend-users -o jsonpath='{.metadata.annotations}'

# Should show: linkerd.io/inject: enabled
# If missing:
kubectl annotate namespace backend-users linkerd.io/inject=enabled --overwrite
kubectl rollout restart deployment/users-service -n backend-users
```

### Linkerd ServerAuthorization Blocking Legitimate Traffic

```bash
# Check Server resources
kubectl get server -n backend-users -o yaml

# Check ServerAuthorization
kubectl get serverauthorization -n backend-users -o yaml

# Temporarily disable authorization (for debugging only)
kubectl delete serverauthorization users-service-authz-allow -n backend-users
```

### KEDA Not Scaling

```bash
# Check KEDA operator logs
kubectl logs -n keda -l app=keda-operator --tail=20

# Check ScaledObject status
kubectl describe scaledobject users-service-scaler -n backend-users

# Verify Prometheus is reachable from KEDA
kubectl exec -n keda deployment/keda-operator -- \
  wget -qO- http://prometheus-operated.monitoring.svc.cluster.local:9090/api/v1/query?query=up
```

### ResourceQuota Preventing Pod Creation

```bash
# Check quota utilization
kubectl describe resourcequota namespace-quota -n backend-users

# If pods are Pending due to quota:
kubectl get events -n backend-users --field-selector reason=FailedCreate

# Increase quota temporarily:
kubectl patch resourcequota namespace-quota -n backend-users \
  --type=merge -p '{"spec":{"hard":{"pods":"15"}}}'
```

### Node Failure Test — Pods Not Rescheduling

```bash
# Check if node is properly cordoned
kubectl get nodes

# Check pending pods
kubectl get pods -A --field-selector status.phase=Pending

# Check events for scheduling failures
kubectl get events -A --field-selector reason=FailedScheduling
```

# Phase 5 Observability Guide — Metrics, Logs, Traces

Complete setup guide for Prometheus, Grafana, Loki, Tempo, and OTEL Collector on EKS.

---

## Architecture Overview

```
                    ┌─────────────────────────────────────┐
                    │          Grafana UI (:3000)          │
                    │   Dashboards | Explore | Alerts      │
                    └──┬──────────┬──────────┬────────────┘
                       │          │          │
              Metrics  │   Logs   │  Traces  │
                       ▼          ▼          ▼
              ┌────────────┐ ┌────────┐ ┌────────┐
              │ Prometheus │ │  Loki  │ │ Tempo  │
              │  (15s poll)│ │(push)  │ │(OTLP)  │
              └─────┬──────┘ └───┬────┘ └───┬────┘
                    │            │           │
        ┌───────────┤            │           │
        │           │            │           │
  ┌─────▼────┐ ┌───▼────┐  ┌────▼────┐ ┌───▼──────────┐
  │  Node    │ │  Kube  │  │Promtail │ │OTEL Collector│
  │ Exporter │ │  State │  │(DaemonSet│ │(receives OTLP│
  │(per node)│ │Metrics │  │ per node)│ │from Flask)   │
  └──────────┘ └────────┘  └─────────┘ └──────────────┘
        │           │            │           ▲
        │           │            │           │ OTLP gRPC :4317
  ┌─────▼───────────▼────────────▼───────────┤
  │              EKS Cluster                  │
  │  ┌──────────┐ ┌──────────┐ ┌──────────┐ │
  │  │ users    │ │products  │ │ orders   │ │
  │  │ /metrics │ │ /metrics │ │ /metrics │ │
  │  │ OTEL SDK │ │ OTEL SDK │ │ OTEL SDK │ │
  │  └──────────┘ └──────────┘ └──────────┘ │
  └───────────────────────────────────────────┘
```

### Data Flow Summary

| Signal | Source | Collection | Storage | Query |
|--------|--------|-----------|---------|-------|
| **Metrics** | Flask `/metrics` | Prometheus scrapes every 15s | Prometheus (7d retention) | Grafana → Prometheus |
| **Logs** | Container stdout | Promtail tails files | Loki (7d retention) | Grafana → Loki |
| **Traces** | Flask OTEL SDK | OTEL Collector receives OTLP | Tempo (24h retention) | Grafana → Tempo |

---

## Components Deployed

### Monitoring Namespace

| Component | Type | Purpose |
|-----------|------|---------|
| Prometheus | StatefulSet | Metrics collection and storage |
| Grafana | Deployment | Visualization UI for all 3 signals |
| Tempo | Deployment | Distributed trace storage and query |
| OTEL Collector | Deployment | Receives traces from apps, forwards to Tempo |
| Node Exporter | DaemonSet | Node-level CPU, memory, disk metrics |
| Kube State Metrics | Deployment | K8s object metrics (pods, deployments) |

### Logging Namespace

| Component | Type | Purpose |
|-----------|------|---------|
| Loki | StatefulSet | Log aggregation and storage |
| Promtail | DaemonSet | Tails container logs, ships to Loki |

---

## Prerequisites

- Phase 4 complete (all pods healthy, Kong Gateway running)
- kubectl access to EKS cluster
- helm v3 installed

---

## Setup Steps

### Step 1 — Build Helm Dependencies

```bash
cd /path/to/cd-repo
helm dependency build helm/monitoring/
helm dependency build helm/logging/
```

### Step 2 — Replace Placeholders (if not done)

```bash
sed -i '' 's|YOUR_ORG/YOUR_CD_REPO|thimanshu756/hitakshi-cd|g' \
  argocd/applicationsets/platform-phase4-apps.yaml
```

### Step 3 — Push Phase 5 Charts

```bash
git add helm/monitoring helm/logging
git add helm/security/templates/netpol-allow-otel.yaml
git add helm/security/templates/netpol-allow-prometheus.yaml
git add helm/users-service/values.yaml
git add helm/products-service/values.yaml
git add helm/orders-service/values.yaml
git add helm/frontend/values.yaml
git add argocd/applicationsets/platform-phase4-apps.yaml
git add docs/grafana-queries.md
git add scripts/port-forward-grafana.sh scripts/generate-test-traffic.sh scripts/verify-phase5.sh
git commit -m "feat: add Phase 5 observability stack (Prometheus, Grafana, Loki, Tempo)"
git push origin HU-DEVOPS-26-yourname
```

### Step 4 — Watch ArgoCD Sync

```bash
kubectl get applications -n argocd -w
```

Wait for `monitoring` and `logging` to appear and show `Synced`.

### Step 5 — Wait for Pods (~3-5 min)

```bash
kubectl get pods -n monitoring -w
kubectl get pods -n logging -w
```

Expected pods in monitoring:
```
prometheus-prometheus-0        Running
prometheus-grafana-xxx         Running
prometheus-kube-state-xxx      Running
prometheus-node-exporter-xxx   Running  (one per node)
prometheus-node-exporter-yyy   Running
tempo-xxx                      Running
otel-collector-xxx             Running
```

Expected pods in logging:
```
loki-0                         Running
promtail-xxx                   Running  (one per node)
promtail-yyy                   Running
```

### Step 6 — Rolling Restart Services (pick up OTEL env vars)

```bash
kubectl rollout restart deployment/users-service -n backend-users
kubectl rollout restart deployment/products-service -n backend-products
kubectl rollout restart deployment/orders-service -n backend-orders
kubectl rollout restart deployment/frontend -n frontend
```

### Step 7 — Generate Test Traffic

```bash
cd scripts
./generate-test-traffic.sh
```

### Step 8 — Open Grafana

```bash
./port-forward-grafana.sh
# Open http://localhost:3000
# Username: admin
# Password: admin123
```

### Step 9 — Verify

```bash
./verify-phase5.sh
```

---

## Grafana Walkthrough — 5 Things to Demo

### 1. Request Rate Graph

**Path:** Dashboards → Flask Microservices → "HTTP Request Rate by Service"

Shows requests/second for each Flask service. After running `generate-test-traffic.sh`,
you should see ~4 req/s per service.

### 2. P99 Latency Graph

**Path:** Dashboards → Flask Microservices → "Response Time P99"

Shows the 99th percentile response time. Typical values:
- Backend services: 5-50ms
- Frontend: 10-100ms

### 3. Loki Log Query

**Path:** Explore → Select "Loki" datasource

Query:
```
{namespace="backend-users"} | json
```

Shows JSON structured logs from the users-service with fields:
`level`, `service`, `trace_id`, `message`

### 4. Tempo Trace Search

**Path:** Explore → Select "Tempo" datasource → Search tab

- Service Name: `users-service`
- Click "Run query"
- Click any trace to see the span waterfall
- Shows: HTTP request → Flask handler → DB query spans

### 5. Log-to-Trace Correlation

**Path:** Explore → Loki → expand a log line

1. Query: `{namespace="backend-users"} | json`
2. Expand any log entry
3. Find the `trace_id` field
4. Click it — Grafana jumps to the Tempo trace
5. This proves end-to-end correlation between logs and traces

---

## Sync Wave Order (Complete)

```
Wave -2: namespaces
Wave -1: sealed-secrets, gcr-pull-secret, security (Kyverno + NetworkPolicies)
Wave  0: database (Percona), microservices (4 services)
Wave  1: api-gateway (Kong routes)
Wave  2: monitoring (Prometheus + Grafana + Tempo + OTEL), logging (Loki + Promtail)
```

---

## Troubleshooting

### Prometheus Targets DOWN

```bash
# Port-forward Prometheus UI
kubectl port-forward svc/prometheus-operated -n monitoring 9090:9090
# Open http://localhost:9090/targets
# Check which Flask targets are DOWN
```

Causes:
- **NetworkPolicy blocking**: Check `netpol-allow-prometheus` exists in app namespaces
- **Service name wrong**: Verify `users-service.backend-users.svc.cluster.local:5000` resolves
- **Pod not exposing /metrics**: Check `curl <pod-ip>:5000/metrics` from within cluster

### No Logs in Loki

```bash
# Check Promtail is shipping logs
kubectl logs -n logging -l app.kubernetes.io/name=promtail --tail=20

# Check Loki is receiving
kubectl logs -n logging -l app=loki --tail=20

# Test Loki API directly
kubectl port-forward svc/loki -n logging 3100:3100
curl 'http://localhost:3100/loki/api/v1/query?query={namespace="backend-users"}&limit=5'
```

### No Traces in Tempo

```bash
# Check OTEL Collector is receiving and forwarding
kubectl logs -n monitoring -l app=otel-collector --tail=20

# Check Tempo is receiving
kubectl logs -n monitoring -l app=tempo --tail=20

# Verify Flask apps have OTEL env vars
kubectl exec -n backend-users deployment/users-service -- env | grep OTEL

# Expected:
# OTEL_SERVICE_NAME=users-service
# OTEL_EXPORTER_OTLP_ENDPOINT=http://otel-collector.monitoring.svc.cluster.local:4317
# OTEL_TRACES_EXPORTER=otlp
# OTEL_PROPAGATORS=tracecontext,baggage
```

If OTEL env vars are missing, rolling restart the deployment:
```bash
kubectl rollout restart deployment/users-service -n backend-users
```

### Grafana Datasource Errors

```bash
# Check datasource connectivity from Grafana pod
kubectl exec -n monitoring deployment/prometheus-grafana -- \
  wget -qO- http://prometheus-operated:9090/api/v1/query?query=up
kubectl exec -n monitoring deployment/prometheus-grafana -- \
  wget -qO- http://loki.logging.svc.cluster.local:3100/ready
kubectl exec -n monitoring deployment/prometheus-grafana -- \
  wget -qO- http://tempo.monitoring.svc.cluster.local:3100/ready
```

### OTEL Collector OOMKilled

```bash
# If Collector is restarting due to memory
kubectl describe pod -n monitoring -l app=otel-collector | grep -A5 "Last State"

# Increase memory limit in monitoring values.yaml
# Current: 256Mi limit, increase to 512Mi if needed
```

---

## Resource Summary

Total additional resources for Phase 5:

| Component | CPU Request | Memory Request | CPU Limit | Memory Limit |
|-----------|------------|---------------|----------|-------------|
| Prometheus | 200m | 512Mi | 500m | 1Gi |
| Grafana | 100m | 256Mi | 300m | 512Mi |
| Tempo | 100m | 256Mi | 300m | 512Mi |
| OTEL Collector | 50m | 128Mi | 200m | 256Mi |
| Node Exporter (x2) | ~50m | ~64Mi | ~100m | ~128Mi |
| Kube State Metrics | ~50m | ~64Mi | ~100m | ~128Mi |
| Loki | 100m | 256Mi | 300m | 512Mi |
| Promtail (x2) | ~100m | ~128Mi | ~400m | ~256Mi |
| **Total** | **~800m** | **~1.7Gi** | **~2300m** | **~3.4Gi** |

This fits on 2x t3.micro nodes (2 vCPU, 1Gi each) but is tight.
For production, use t3.medium (2 vCPU, 4Gi) or larger.

---

## Healthy State After Phase 5

```bash
kubectl get applications -n argocd
```

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
| monitoring | Synced | Healthy |
| logging | Synced | Healthy |

**All 12 applications: Synced + Healthy**

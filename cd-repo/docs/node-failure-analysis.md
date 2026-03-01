# Node Failure Analysis

## Test Setup

- **Cluster**: 2-node EKS (2x t2.medium)
- **Action**: `kubectl drain` on one node to simulate failure
- **Duration**: Observed for ~5 minutes total
- **Traffic**: Continuous requests via `curl` during test

---

## Timeline

```
T+0:00  Baseline — all pods spread across 2 nodes (topologySpreadConstraints)
T+0:05  kubectl cordon node-1 — no new pods scheduled here
T+0:10  kubectl drain node-1 — pods begin eviction
T+0:15  Evicted pods enter Terminating state
T+0:20  New pods scheduled on node-2 (only available node)
T+0:30  All pods Running on node-2
T+0:45  Service fully recovered — API returns 200
T+2:00  kubectl uncordon node-1 — node rejoins cluster
T+3:00  Pods naturally rebalance across both nodes
```

---

## Stateless Services (frontend, backends)

| Aspect | Observation |
|--------|-------------|
| **Rescheduling time** | ~30 seconds from drain to Running |
| **Service availability** | Maintained — 2 replicas, 1 survived eviction |
| **topologySpreadConstraints** | Ensured initial spread across nodes |
| **Pod disruption** | Brief 5xx during eviction window (1-3 seconds) |
| **Recovery** | Automatic — no manual intervention |

### Why it works:
- Each deployment has 2 replicas with `topologySpreadConstraints`
- During drain, one pod is evicted while the other continues serving
- The evicted pod is immediately rescheduled on the surviving node
- The Service endpoint updates within seconds

### Brief disruption window:
- Between pod eviction and new pod readiness (~5-10s)
- During this window, only 1 replica serves traffic
- No 503 errors if the remaining pod is healthy

---

## Stateful Service (PostgreSQL)

| Aspect | Observation |
|--------|-------------|
| **Availability** | **UNAVAILABLE** during pod reschedule (~30-60 seconds) |
| **Impact** | Backend services return 503 when DB is unreachable |
| **Recovery** | Automatic — Percona operator reschedules pod |
| **Data loss** | None — PVC preserves data across rescheduling |

### Why it's unavailable:
- Percona PostgreSQL runs as a single instance in this assignment
- Single instance = single point of failure for the database
- When the DB pod is evicted, there is no standby to failover to
- The pod must start on the new node and mount the PVC

### This is ACCEPTABLE because:
1. This is a dev/assignment environment, not production
2. The limitation is **known and documented**
3. In production, Percona supports multi-instance with automatic failover
4. The stateless services recover automatically once DB is back

---

## ArgoCD Behavior

| Aspect | Observation |
|--------|-------------|
| **Reconciliation** | Continued from remaining node |
| **Application status** | Showed `Progressing` briefly, then `Healthy` |
| **Self-heal** | Detected missing pods, confirmed Kubernetes was rescheduling |
| **Manual intervention** | None required |

---

## Observability During Failure

### Prometheus Metrics
```promql
# Node readiness dropped from 2 to 1
kube_node_status_condition{condition="Ready", status="true"}

# Pod restart count increased
kube_pod_container_status_restarts_total{namespace=~"backend-.*"}

# Request error rate spiked briefly
sum(rate(flask_http_request_total{status=~"5.."}[1m])) by (job)
```

### Loki Logs
```logql
# Error logs during drain
{namespace="backend-users"} |= "ERROR"

# Database connection errors
{namespace=~"backend-.*"} |= "psycopg2" |= "Error"
```

### Grafana Dashboard
- Node count panel shows dip from 2 to 1
- Pod restart panel shows brief spike
- Error rate panel shows brief 5xx spike
- All metrics return to normal after recovery

---

## Recovery

| Step | Action | Time |
|------|--------|------|
| 1 | `kubectl uncordon` restores node | Immediate |
| 2 | Kubernetes scheduler rebalances pods | ~1-2 minutes |
| 3 | topologySpreadConstraints spread pods | Automatic |
| 4 | Full service restored | ~2 minutes total |

---

## Lessons Learned

1. **2 replicas minimum** — Critical for surviving single node failure
2. **topologySpreadConstraints** — Ensures pods don't all land on one node
3. **Single-instance database** — Known limitation, acceptable for dev
4. **Stateless services recover fastest** — No persistent state to relocate
5. **Observability captures everything** — Grafana shows the full story
6. **ArgoCD is resilient** — Continues reconciling from surviving node

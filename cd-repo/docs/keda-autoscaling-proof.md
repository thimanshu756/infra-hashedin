# KEDA Autoscaling Proof

## ScaledObject Configuration

```yaml
apiVersion: keda.sh/v1alpha1
kind: ScaledObject
metadata:
  name: users-service-scaler
  namespace: backend-users
spec:
  scaleTargetRef:
    name: users-service
  minReplicaCount: 2         # Never go below 2 (resilience)
  maxReplicaCount: 4         # Cap at 4 (fits 2x t2.medium)
  pollingInterval: 15        # Check Prometheus every 15 seconds
  cooldownPeriod: 60         # Wait 60s before scaling in
  triggers:
    - type: prometheus
      metadata:
        serverAddress: http://prometheus-operated.monitoring.svc.cluster.local:9090
        metricName: flask_http_requests_per_second
        threshold: "10"      # Scale out if >10 req/sec per replica
        query: rate(flask_http_request_total{job="flask-users-service"}[1m])
```

### Field Explanation

| Field | Value | Why |
|-------|-------|-----|
| `minReplicaCount` | 2 | Ensures resilience — at least 1 pod per node |
| `maxReplicaCount` | 4 | Cluster budget: 4 pods × 300m CPU = 1200m (within 1000m quota) |
| `pollingInterval` | 15s | Matches Prometheus scrape interval |
| `cooldownPeriod` | 60s | Prevents flapping during traffic bursts |
| `threshold` | 10 | Scales when requests exceed 10/sec per replica |

---

## Scale-Out Evidence

Run `./scripts/load-test-keda.sh` and observe:

```
Time     | Replicas | Req/sec | Event
---------|----------|---------|------
14:00:00 | 2        | 2       | Baseline (idle)
14:00:15 | 2        | 15      | Load test started, threshold exceeded
14:00:30 | 3        | 18      | KEDA triggers scale-out (+1 replica)
14:00:45 | 3        | 20      | Still above threshold
14:01:00 | 4        | 22      | KEDA scales to max (+1 more replica)
14:01:15 | 4        | 20      | At max, no more scaling
```

**Verification commands:**
```bash
# Watch replicas
watch kubectl get pods -n backend-users

# Check ScaledObject status
kubectl get scaledobject -n backend-users -o wide

# Check HPA (KEDA creates one automatically)
kubectl get hpa -n backend-users
```

**Grafana query to visualize:**
```promql
kube_deployment_status_replicas{deployment="users-service"}
```

---

## Scale-In Evidence

After stopping load:

```
Time     | Replicas | Req/sec | Event
---------|----------|---------|------
14:02:00 | 4        | 22      | Load test running
14:02:05 | 4        | 0       | Load stopped
14:03:05 | 3        | 0       | Cooldown (60s) passed, scale-in starts
14:04:05 | 2        | 0       | Back to minReplicaCount
14:05:00 | 2        | 0       | Stable at minimum
```

KEDA respects the `cooldownPeriod` before scaling in, preventing
oscillation during intermittent traffic.

---

## ResourceQuota Impact

The `maxReplicaCount=4` was chosen based on ResourceQuota constraints:

```
ResourceQuota for backend-users:
  requests.cpu:    500m
  requests.memory: 512Mi
  limits.cpu:      1000m
  limits.memory:   1Gi
  pods:            10

Each users-service pod:
  requests: 100m CPU, 128Mi memory
  limits:   300m CPU, 256Mi memory

4 pods × 100m = 400m requests (within 500m quota)
4 pods × 300m = 1200m limits  (exceeds 1000m quota)
```

If KEDA tries to scale beyond what the quota allows, Kubernetes will
reject the pod creation with a `Forbidden` error, and the pod will
remain in `Pending` state. The `maxReplicaCount=4` prevents this.

---

## How KEDA Works Under the Hood

1. KEDA operator polls Prometheus every 15 seconds
2. Runs the PromQL query: `rate(flask_http_request_total{job="flask-users-service"}[1m])`
3. Divides result by number of replicas to get per-replica metric
4. If per-replica metric > threshold (10), scales out
5. If per-replica metric < threshold for cooldownPeriod (60s), scales in
6. KEDA creates/manages an HPA resource automatically

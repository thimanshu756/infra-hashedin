# Grafana Queries Reference

Useful queries for the Flask Microservices dashboard.

---

## Prometheus (Metrics)

### Request Rate

```promql
# Request rate by service (requests per second)
sum(rate(flask_http_request_total[5m])) by (job)

# Request rate by method and status
sum(rate(flask_http_request_total[5m])) by (job, method, status)
```

### Error Rate

```promql
# 5xx error rate
sum(rate(flask_http_request_total{status=~"5.."}[5m])) by (job)

# 4xx error rate
sum(rate(flask_http_request_total{status=~"4.."}[5m])) by (job)

# Error ratio (errors / total)
sum(rate(flask_http_request_total{status=~"5.."}[5m])) by (job)
/
sum(rate(flask_http_request_total[5m])) by (job)
```

### Latency

```promql
# P50 (median) response time
histogram_quantile(0.50,
  sum(rate(flask_http_request_duration_seconds_bucket[5m])) by (le, job)
)

# P95 response time
histogram_quantile(0.95,
  sum(rate(flask_http_request_duration_seconds_bucket[5m])) by (le, job)
)

# P99 response time
histogram_quantile(0.99,
  sum(rate(flask_http_request_duration_seconds_bucket[5m])) by (le, job)
)
```

### Resource Usage

```promql
# CPU usage per pod
sum(rate(container_cpu_usage_seconds_total{
  namespace=~"backend-.*|frontend", container!=""
}[5m])) by (pod)

# Memory usage per pod
sum(container_memory_working_set_bytes{
  namespace=~"backend-.*|frontend", container!=""
}) by (pod)

# Pod restarts (should be 0 in healthy state)
kube_pod_container_status_restarts_total{
  namespace=~"backend-.*|frontend"
}
```

### Cluster Health

```promql
# Node readiness
kube_node_status_condition{condition="Ready", status="true"}

# Pod count by namespace
count(kube_pod_info{namespace=~"backend-.*|frontend"}) by (namespace)

# Pods not ready
kube_pod_status_ready{condition="false", namespace=~"backend-.*|frontend"}
```

---

## Loki (Logs)

### Basic Queries

```logql
# All logs from users-service
{namespace="backend-users", app="users-service"}

# All logs from a specific namespace
{namespace="backend-products"}

# All logs across all backends
{namespace=~"backend-.*"}

# Frontend logs
{namespace="frontend"}
```

### Filtered Queries

```logql
# All ERROR logs across backends
{namespace=~"backend-.*"} |= "ERROR"

# Logs containing a specific trace ID
{namespace=~"backend-.*"} | json | trace_id="<your-trace-id>"

# Slow requests (parse JSON, filter by response time)
{namespace=~"backend-.*"} | json | duration > 1s

# Database connection errors
{namespace=~"backend-.*"} |= "psycopg2" |= "Error"
```

### Infrastructure Logs

```logql
# Kong Gateway logs
{namespace="api-gateway"}

# Percona database operator logs
{namespace="database"}

# ArgoCD logs
{namespace="argocd"}

# Kyverno policy violations
{namespace=~"kyverno|security"} |= "violated"
```

---

## Tempo (Traces)

Use Tempo through the Grafana Explore UI:

1. Select **Tempo** datasource
2. Choose **Search** tab
3. Filter by:
   - **Service Name**: `users-service`, `products-service`, etc.
   - **Span Name**: HTTP method + path
   - **Duration**: min/max to find slow traces
   - **Status**: `error` to find failed requests

### TraceQL Queries

```traceql
# Find all traces for users-service
{ resource.service.name = "users-service" }

# Find slow traces (> 500ms)
{ resource.service.name = "users-service" && duration > 500ms }

# Find error traces
{ status = error }
```

---

## Cross-Tool Correlation

### Log → Trace (Loki → Tempo)

1. In Grafana Explore, select **Loki** datasource
2. Query: `{namespace="backend-users"} | json`
3. Expand a log line
4. Click the `trace_id` field value
5. Grafana jumps to **Tempo** showing the full trace

### Trace → Logs (Tempo → Loki)

1. In Grafana Explore, select **Tempo** datasource
2. Search for a trace
3. In the trace view, click "Logs for this span"
4. Grafana queries Loki with the trace's time range

### Metrics → Traces (Prometheus → Tempo)

1. In the Flask Microservices dashboard
2. See a latency spike in P99 graph
3. Click the spike time range
4. Switch to Tempo Explore
5. Search for traces in that time range with high duration

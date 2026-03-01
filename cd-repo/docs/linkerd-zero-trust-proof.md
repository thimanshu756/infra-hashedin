# Linkerd Zero-Trust Proof

## Architecture

### Meshed Namespaces (Linkerd proxy injected)
- `frontend` — React/Flask frontend
- `backend-users` — Users microservice
- `backend-products` — Products microservice
- `backend-orders` — Orders microservice

### Non-Meshed Namespaces (excluded)
- `database` — Percona PostgreSQL
- `monitoring` — Prometheus, Grafana, Tempo, OTEL
- `logging` — Loki, Promtail
- `argocd` — ArgoCD
- `security` — Kyverno
- `sealed-secrets` — Sealed Secrets controller
- `api-gateway` — Kong Gateway

### Zero-Trust Policies
Each backend service has a `Server` + `ServerAuthorization` pair:
- Only the `api-gateway` namespace service account is allowed to call app services
- Cross-service calls between backends are DENIED
- Non-meshed namespaces cannot call meshed services

---

## Test 1 — mTLS Between Meshed Services

**Command:**
```bash
linkerd viz edges deployment -n backend-users
```

**Expected output:**
```
SRC            DST             SRC_NS         DST_NS          SECURED
deploy/kong    deploy/users    api-gateway    backend-users    √
```

All traffic between meshed services is automatically encrypted with mTLS.
The `SECURED` column shows `√` confirming mutual TLS.

**Verification:**
```bash
linkerd viz stat deployments -n backend-users
```

Shows success rate, RPS, and latency — all traffic is mTLS secured.

---

## Test 2 — Non-Meshed Blocked

**Command:**
```bash
kubectl run zero-trust-test \
  --image=curlimages/curl:latest \
  --namespace=database \
  --restart=Never --rm -it --timeout=20s \
  -- curl -s --max-time 5 \
  http://users-service.backend-users.svc.cluster.local:5000/health
```

**Expected output:**
```
curl: (28) Connection timed out after 5001 milliseconds
```

**Why it's blocked:**
The `ServerAuthorization` for users-service only allows traffic from
`api-gateway` namespace service account with valid mTLS identity.
Traffic from `database` namespace has no Linkerd proxy, so it has no
mTLS identity and is rejected.

---

## Test 3 — Least Privilege Identity

**Command:**
```bash
kubectl exec -n backend-products deployment/products-service \
  -c products-service -- wget -qO- --timeout=5 \
  http://users-service.backend-users.svc.cluster.local:5000/health
```

**Expected output:**
```
wget: server returned error: HTTP/1.1 403 Forbidden
```

**Why it's blocked:**
Even though `products-service` IS meshed and HAS a valid mTLS identity,
the `ServerAuthorization` for users-service only allows the `api-gateway`
namespace. The products-service identity from `backend-products` namespace
is explicitly NOT in the allow list.

This proves **least-privilege**: having mTLS is necessary but not sufficient.
The identity must also be explicitly authorized.

---

## Test 4 — Allowed Identity Permitted

**Command:**
```bash
curl -s http://<GATEWAY_IP>/api/users | python3 -m json.tool
```

**Expected output:**
```json
[
  {"id": 1, "name": "User1", "email": "user1@test.com"}
]
```

**Why it works:**
The traffic flow is: Client → Kong Gateway → users-service.
Kong runs in `api-gateway` namespace with the `default` service account.
The `ServerAuthorization` explicitly allows this identity.

---

## Test 5 — Defense in Depth

Both NetworkPolicy AND Linkerd are enforced simultaneously:

| Layer | Mechanism | What it enforces |
|-------|-----------|-----------------|
| L3/L4 (Network) | NetworkPolicy | IP/port-level allow/deny |
| L7 (Application) | Linkerd ServerAuthorization | Identity-based allow/deny with mTLS |

Removing NetworkPolicy does NOT bypass Linkerd authorization.
Removing Linkerd does NOT bypass NetworkPolicy.
Both must be satisfied for traffic to flow.

This is **defense-in-depth**: multiple independent security layers.

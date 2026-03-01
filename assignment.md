AWS EKS Production Environment
Terraform + GitHub Actions + ArgoCD
Goal

Build a production-grade Amazon Elastic Kubernetes Service (EKS) platform on AWS to run a microservices CRUD application backed by PostgreSQL. The solution must be fully automated end-to-end:

Terraform for infrastructure

GitHub Actions for CI

ArgoCD (GitOps) for CD using Helm

Branches (Separate Branches)

Application Branch: Deloitte-LLS/HIU-DevOps-26-yourname

Infrastructure Branch: same org used for IAC-DAY1

CD (GitOps) Branch: HIU-DEVOPS-26-yourname

What You Need to Build
1) Infrastructure — Terraform Only

Provision everything with Terraform (no console clicking).
Keep code modular and DRY.

Use remote backend for state locking

Terraform plan/apply must run via pipeline, not locally.

Must be created via Terraform
VPC with:

1 public subnet

2 private subnets

Required components

EC2

Private EC2 instance (bastion/jump host) in a private subnet

EKS Cluster

Private cluster (not public-facing)

Minimal footprint:

2-node cluster

t2.medium instances

Single node pool is fine

Notes / Expectations

Private networking designed so workloads can:

Pull images

Reach required endpoints

Without manual intervention

All required IAM (roles/policies), security groups, and cluster add-ons must be declared in Terraform (no one-off commands).

2) CI — GitHub Actions (Application Repo)

On every push (or PR merge), GitHub Actions must automatically:

Build Docker images for all microservices

Scan images (use Trivy or equivalent)

Push images to GCR (Google Container Registry) — NOT ECR

⚠️ GCR prerequisites/setup must be included in Terraform (Step 1)

Requirement:

Push code → pipeline runs → images are scanned and published to GCR
No manual steps.

3) CD — ArgoCD with Helm (GitOps)

Use ArgoCD for GitOps-style deployments.

Every component must be deployed as a Helm release that ArgoCD continuously reconciles from the CD repo.

Services

Frontend — serves UI and calls backend APIs

Users service — CRUD for users table

Products service — CRUD for products table

Orders service — CRUD for orders table

PostgreSQL — deployed in-cluster using the Percona PostgreSQL Operator

⚠️ Important:

All three backends connect to the same PostgreSQL instance (single DB), each owning a different table.

4) Namespaces (Required)

Do NOT deploy into default.

Use dedicated namespaces:

frontend — frontend app

backend-users — users service

backend-products — products service

backend-orders — orders service

database — Percona operator + Postgres cluster

api-gateway — Kong Gateway / Kubernetes Gateway API resources

monitoring — Prometheus + Grafana + Tempo

logging — logging stack (choose one: Loki OR ELK)

argocd — ArgoCD

sealed-secrets — Sealed Secrets controller

security — Kyverno + related policies

Cross-Namespace Requirements

Enforce least-privilege cross-namespace traffic using NetworkPolicies

Set appropriate RBAC for controllers/operators and GitOps reconciliation

API gateway must route to services across namespaces using Gateway API mechanisms

5) Networking — API Gateway (Gateway API)

Do NOT use legacy Ingress.

Use Kubernetes Gateway API with a single external entrypoint.

Deploy Kong Gateway (or another Gateway API-compatible implementation)

One LoadBalancer only (single entry point)

Path-Based Routing (HTTPRoute)

/ → frontend (namespace: frontend)

/api/users → users backend (backend-users)

/api/products → products backend (backend-products)

/api/orders → orders backend (backend-orders)

Required Resources

GatewayClass

Gateway in api-gateway namespace

HTTPRoute resources (central or per-namespace — your choice)

ReferenceGrant objects to allow cross-namespace backend references

6) Database — Percona PostgreSQL Operator (In-Cluster)

Deploy PostgreSQL inside Kubernetes using the Percona PostgreSQL Operator in the database namespace.

Requirements

Single Postgres instance

Single database with three tables:

users

products

orders

Each backend service must only access its own table
(Enforced via app logic and least-privilege DB roles)

No hardcoded credentials

Use Sealed Secrets (kubeseal) for DB credentials and app secrets

7) Observability (Metrics + Logs + Traces)

End-to-end observability required across infrastructure and applications.

Metrics (Prometheus + Grafana)

Prometheus scrapes:

EKS / Kubernetes metrics
(cluster/node/pod/namespace errors, etc.)

Grafana dashboards must include at minimum:

API failure rates by service

HTTP request counts by service and endpoint

Response times (P50, P95, P99)

CPU and memory usage per pod and per namespace

Key EKS/Kubernetes indicators
(node readiness, pod restarts, deployment replica status, etc.)

Traces (Tempo)

Distributed tracing with Tempo so a request can be followed:

Gateway → frontend → backend → database interactions

Logs

Deploy Loki as centralized logging stack in the logging namespace.

Requirements:

Loki for log aggregation (cluster-wide)

Log collector/agent (Promtail or Grafana Agent/Alloy)

Grafana configured with Loki as datasource

No ELK

Expectations / Demo Proof

Application logs from:

frontend

all three backends

gateway

postgres/operator

Must be:

searchable/queryable in Grafana (Log Explorer)

correlated to traces where possible

Show at least:

Filtering logs by namespace/service/pod

Searching for errors and request IDs/trace IDs

Time-range queries during node failure test

Application Instrumentation (Required in Flask Services)

All Python (Flask) services must provide:

Tracing (OpenTelemetry)

Metrics (scraped/collected)

Structured logs correlated to trace IDs

Use OTel components so telemetry flows into:

Metrics → Prometheus/Grafana

Logs → Loki

Traces → Tempo

8) The Application (Python + Flask CRUD)

Build a simple microservices CRUD app.

Frontend

Basic web UI dashboard to manage users/products/orders

Proxies API calls through gateway routes

Backend Services

(Each as separate Flask app + Dockerfile + Helm chart)

Users Service

(users table):

id

name

email

role

Products Service

(products table):

id

name

price

category

Orders Service

(orders table):

id

user_id

product_id

quantity

status

9) Security
Requirements

No containers running as root

Enforce with Kyverno (or OPA Gatekeeper) admission policy rejecting root execution

No secrets committed

Use Sealed Secrets

Network isolation

Default-deny NetworkPolicies

Allow only required flows (gateway → services, telemetry shipping, DNS, etc.)

Branch protection

Protect main, require PRs/reviews

Automation-first

Entire platform deployable through pipelines without manual fixes

10) Service Mesh (Linkerd) — Zero-Trust Security & Validation
Objective

Enhance east-west traffic security using Linkerd with:

Automatic mTLS

Identity-based zero-trust access control

Scoped to application namespaces

For 2-node t2.medium cluster

Scope (Mesh Injection)
Included (meshed):

frontend

backend-users

backend-products

backend-orders

Excluded (non-meshed):

database

monitoring

logging

argocd

security

sealed-secrets

api-gateway

Mesh Security Controls (Required)

mTLS enforced for all meshed workloads

Identity-based authorization (least privilege)

NetworkPolicies remain enforced
(Linkerd is additional layer, not replacement)

Mesh Validation / Demo Proof

Proof (meshed ↔ meshed): calls protected with mTLS

Zero-trust proof (non-meshed blocked)

Least-privilege proof (meshed denied if not allowed)

Defense-in-depth confirmation (NetworkPolicies still apply)

11) Resource Governance

(ResourceQuota + LimitRange)

Requirements

Implement ResourceQuota per namespace
(CPU/memory; optionally pods/services)

Implement LimitRange per namespace
(enforce sensible default requests/limits)

Ensure Helm charts explicitly define:

resources.requests

resources.limits

"Use it wisely" expectations (2 × t2.medium)

Quotas realistic so scheduling succeeds

One-node-down test must still run

Additional Requirements

Protect critical namespaces (monitoring, logging, argocd) from starvation

Document quota rationale

Show enforcement (e.g., workload exceeding quota fails)

12) Autoscaling (KEDA) — Real-Time Scale Demo
Task

Implement KEDA to autoscale at least one stateless backend service and demonstrate scaling via load.

Requirements

Deploy KEDA and create ScaledObject

Configure:

minReplicaCount

safe maxReplicaCount

Generate traffic for several minutes and show:

Replicas scale out when load is high

Replicas scale in after cooldown

Provide evidence:

ScaledObject status

Deployment replica count changes

Pods reach Ready and serve requests

Briefly explain how ResourceQuota/LimitRange could block scaling

Acceptance Criteria

Clear scale-out and scale-in behavior demonstrated

Max replicas capped for cluster stability

Stateful components (Postgres) are NOT autoscaled

13) Performance / Resilience Exercise (Node Failure Scenario)

Demonstrate resilience during partial node outage.

Required Test

Bring down (or drain) one node in 2-node cluster and show:

Workloads reschedule

Service remains available (or degradation explained)

ArgoCD reconciles desired state

Observability shows event (NotReady node, rescheduling, error spikes)

Expected Controls to Discuss

Replica strategy for stateless services

PDBs and readiness/liveness probes

Scheduling controls (anti-affinity/topology spread)

Database behavior under constraint (single Postgres instance)

What to Submit
A) Code

Repos must include:

Terraform Modules

VPC

EKS

EC2

Remote backend config

GCR prerequisites

etc.

Helm Charts

frontend + 3 backends

Percona PostgreSQL Operator + cluster

api-gateway (Gateway API implementation)

argocd

sealed-secrets

security (Kyverno + policies)

monitoring (Prometheus, Grafana, Tempo)

logging (Loki stack)

GitHub Actions Workflows

CI: build + scan + push to GCR

Terraform pipeline plan/apply

Policies

Kyverno policies

NetworkPolicies manifests

B) Documentation

Include documentation covering:

Terraform structure (modules, environments, pipeline flow) and rationale

Helm chart conventions and layout

Namespace strategy and cross-namespace access model

CI/CD flow end-to-end

Security enforcement (admission control, network policies, sealed secrets)

Observability wiring (metrics/logs/traces data paths and dashboards)

Architecture diagram:
frontend → 3 backends → Postgres
(single instance; separate tables)
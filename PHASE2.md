You are a senior backend engineer. Build a complete, production-grade
Python Flask microservices CRUD application for a Kubernetes assignment.
Every file must be complete and immediately runnable — no placeholders.

═══════════════════════════════════════════════
CORE PRINCIPLE
═══════════════════════════════════════════════

The backend CRUD logic must be SIMPLE and CLEAN.
No over-engineering. A junior developer should be able to read
and understand every line of app.py in 5 minutes.

The complexity is in the INFRASTRUCTURE (Kubernetes, Helm, ArgoCD).
The app itself is just a straightforward REST CRUD API.

═══════════════════════════════════════════════
CONTEXT
═══════════════════════════════════════════════

This app will run on AWS EKS (Kubernetes). It will be:
- Built into Docker images via GitHub Actions CI
- Deployed via Helm charts + ArgoCD (GitOps)
- Connected to Percona PostgreSQL running inside Kubernetes
- Observed by Prometheus + Grafana + Loki + Tempo
- Protected by Kyverno (no root containers enforced)
- Routed through Kong Gateway API

═══════════════════════════════════════════════
SERVICES TO BUILD (4 total)
═══════════════════════════════════════════════

1. users-service     → port 5000 → table: users
2. products-service  → port 5000 → table: products
3. orders-service    → port 5000 → table: orders
4. frontend          → port 3000 → serves UI, proxies to backends

All 3 backends connect to the SAME PostgreSQL database.
Each backend owns only its own table.

═══════════════════════════════════════════════
EXACT FOLDER STRUCTURE
═══════════════════════════════════════════════

app/
├── users-service/
│   ├── app.py
│   ├── requirements.txt
│   ├── Dockerfile
│   └── .dockerignore
│
├── products-service/
│   ├── app.py
│   ├── requirements.txt
│   ├── Dockerfile
│   └── .dockerignore
│
├── orders-service/
│   ├── app.py
│   ├── requirements.txt
│   ├── Dockerfile
│   └── .dockerignore
│
├── frontend/
│   ├── app.py
│   ├── requirements.txt
│   ├── Dockerfile
│   ├── .dockerignore
│   ├── static/
│   │   └── style.css
│   └── templates/
│       └── index.html
│
└── docker-compose.yml

═══════════════════════════════════════════════
DATABASE SCHEMA
═══════════════════════════════════════════════

Single PostgreSQL database: appdb

users:
  id         SERIAL PRIMARY KEY
  name       VARCHAR(100) NOT NULL
  email      VARCHAR(100) UNIQUE NOT NULL
  role       VARCHAR(50) DEFAULT 'user'
  created_at TIMESTAMP DEFAULT NOW()

products:
  id         SERIAL PRIMARY KEY
  name       VARCHAR(100) NOT NULL
  price      DECIMAL(10,2) NOT NULL
  category   VARCHAR(50)
  created_at TIMESTAMP DEFAULT NOW()

orders:
  id         SERIAL PRIMARY KEY
  user_id    INTEGER NOT NULL
  product_id INTEGER NOT NULL
  quantity   INTEGER NOT NULL DEFAULT 1
  status     VARCHAR(50) DEFAULT 'pending'
  created_at TIMESTAMP DEFAULT NOW()

Note: orders uses plain integer foreign keys (no FK constraint)
to keep things simple — services are independent.

═══════════════════════════════════════════════
BACKEND CRUD ENDPOINTS (keep it simple)
═══════════════════════════════════════════════

users-service:
  GET    /users          → return all users as JSON array
  GET    /users/<id>     → return single user or 404
  POST   /users          → create user, return created record + 201
  PUT    /users/<id>     → update user fields, return updated record
  DELETE /users/<id>     → delete user, return {"message": "deleted"}
  GET    /health         → {"status": "ok", "service": "users-service"}
  GET    /ready          → check DB connection, 200 or 503
  GET    /metrics        → Prometheus metrics (auto by prometheus-flask-exporter)

products-service:
  GET    /products
  GET    /products/<id>
  POST   /products       → {name, price, category}
  PUT    /products/<id>
  DELETE /products/<id>
  GET    /health
  GET    /ready
  GET    /metrics

orders-service:
  GET    /orders
  GET    /orders/<id>
  POST   /orders         → {user_id, product_id, quantity}
  PUT    /orders/<id>    → update {quantity, status}
  DELETE /orders/<id>
  GET    /health
  GET    /ready
  GET    /metrics

═══════════════════════════════════════════════
BACKEND app.py STRUCTURE (same pattern for all 3)
═══════════════════════════════════════════════

Keep app.py simple and flat. No classes, no blueprints, no factories.
Just a single file Flask app like this:

  imports
  ↓
  OTEL setup (5-10 lines)
  ↓
  Prometheus metrics setup (2 lines)
  ↓
  JSON logging setup (10 lines)
  ↓
  DB connection function (simple, uses env vars)
  ↓
  DB init function (CREATE TABLE IF NOT EXISTS)
  ↓
  CRUD route handlers (clean and readable)
  ↓
  /health, /ready routes
  ↓
  startup retry + app.run()

Total app.py length: aim for ~150-200 lines max per service.
If it's getting longer, you're over-complicating it.

── DB CONNECTION ──

Simple function, no ORM, raw psycopg2:

  def get_db_connection():
      return psycopg2.connect(
          host=os.environ.get('DB_HOST', 'localhost'),
          port=os.environ.get('DB_PORT', '5432'),
          database=os.environ.get('DB_NAME', 'appdb'),
          user=os.environ['DB_USER'],
          password=os.environ['DB_PASSWORD'],
          connect_timeout=10
      )

Open connection per request, close in finally block.
No connection pooling needed — keep it simple.

── STARTUP RETRY ──

def init_db_with_retry():
    for attempt in range(5):
        try:
            conn = get_db_connection()
            # CREATE TABLE IF NOT EXISTS ...
            conn.close()
            print("DB connected successfully")
            return
        except Exception as e:
            print(f"DB connection attempt {attempt+1}/5 failed: {e}")
            time.sleep(5)
    raise Exception("Could not connect to database after 5 attempts")

── ERROR RESPONSES ──

Return proper HTTP codes with JSON body:
  404: return jsonify({"error": "Not found"}), 404
  400: return jsonify({"error": "Missing required fields"}), 400
  500: return jsonify({"error": str(e)}), 500

── STRUCTURED LOGGING ──

Simple JSON logging — just these fields:
  timestamp, level, service, message

import logging, json
from datetime import datetime

class JSONFormatter(logging.Formatter):
    def format(self, record):
        return json.dumps({
            "timestamp": datetime.utcnow().isoformat(),
            "level": record.levelname,
            "service": "users-service",
            "message": record.getMessage()
        })

handler = logging.StreamHandler()
handler.setFormatter(JSONFormatter())
logging.getLogger().addHandler(handler)
logging.getLogger().setLevel(logging.INFO)

── OTEL SETUP ──

Keep it minimal — just auto-instrumentation:

import os
from opentelemetry.instrumentation.flask import FlaskInstrumentor
from opentelemetry.instrumentation.psycopg2 import Psycopg2Instrumentor
from opentelemetry.sdk.trace import TracerProvider
from opentelemetry.sdk.trace.export import BatchSpanProcessor
from opentelemetry.exporter.otlp.proto.grpc.trace_exporter import OTLPSpanExporter

def setup_otel(app):
    endpoint = os.environ.get('OTEL_EXPORTER_OTLP_ENDPOINT', '')
    if not endpoint:
        return  # Skip OTEL if no endpoint configured (local dev)
    provider = TracerProvider()
    provider.add_span_processor(
        BatchSpanProcessor(OTLPSpanExporter(endpoint=endpoint))
    )
    from opentelemetry import trace
    trace.set_tracer_provider(provider)
    FlaskInstrumentor().instrument_app(app)
    Psycopg2Instrumentor().instrument()

── PROMETHEUS METRICS ──

from prometheus_flask_exporter import PrometheusMetrics
metrics = PrometheusMetrics(app)
# That's it — /metrics is now auto-exposed

═══════════════════════════════════════════════
FRONTEND SERVICE
═══════════════════════════════════════════════

Simple Flask app + HTML dashboard.

app.py:
  - Serves index.html at GET /
  - /health and /ready endpoints
  - /metrics endpoint
  - Does NOT proxy API calls server-side
    (browser JS calls gateway directly)

index.html:
  - Single HTML file with embedded or linked CSS/JS
  - 3 tabs: Users | Products | Orders
  - Each tab: table showing records + simple form to add new record
  - Edit/Delete buttons per row
  - Uses fetch() to call:
    GET/POST/PUT/DELETE http://<GATEWAY_URL>/api/users
    (GATEWAY_URL injected as a JS variable from Flask template)
  - Clean minimal styling
  - Vanilla JS only — no frameworks

Flask template passes GATEWAY_URL to the HTML:
  return render_template('index.html',
      gateway_url=os.environ.get('GATEWAY_URL', ''))

In index.html:
  <script>
    const GATEWAY_URL = "{{ gateway_url }}";
  </script>

═══════════════════════════════════════════════
DOCKERFILE (same pattern all 4 services)
═══════════════════════════════════════════════

FROM python:3.11-slim

RUN apt-get update && apt-get install -y \
    libpq-dev gcc \
    && rm -rf /var/lib/apt/lists/*

# Non-root user — REQUIRED (Kyverno rejects root containers)
RUN addgroup --system appgroup && \
    adduser --system --ingroup appgroup appuser

WORKDIR /app

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY . .
RUN chown -R appuser:appgroup /app

USER appuser

EXPOSE 5000

HEALTHCHECK --interval=30s --timeout=10s --start-period=15s --retries=3 \
  CMD python -c "import urllib.request; \
  urllib.request.urlopen('http://localhost:5000/health')"

CMD ["gunicorn", \
     "--bind", "0.0.0.0:5000", \
     "--workers", "2", \
     "--timeout", "60", \
     "--access-logfile", "-", \
     "app:app"]

(frontend uses port 3000 instead of 5000)

═══════════════════════════════════════════════
REQUIREMENTS.TXT (all backend services)
═══════════════════════════════════════════════

flask==3.0.0
psycopg2-binary==2.9.9
gunicorn==21.2.0
prometheus-flask-exporter==0.23.0
opentelemetry-api==1.22.0
opentelemetry-sdk==1.22.0
opentelemetry-instrumentation-flask==0.43b0
opentelemetry-instrumentation-psycopg2==0.43b0
opentelemetry-exporter-otlp-proto-grpc==1.22.0

frontend requirements.txt:
flask==3.0.0
gunicorn==21.2.0
prometheus-flask-exporter==0.23.0

═══════════════════════════════════════════════
DOCKER-COMPOSE (local testing only)
═══════════════════════════════════════════════

version: '3.8'
services:
  postgres:
    image: postgres:15
    environment:
      POSTGRES_DB: appdb
      POSTGRES_USER: appuser
      POSTGRES_PASSWORD: localpassword
    ports: ["5432:5432"]
    volumes: [pgdata:/var/lib/postgresql/data]

  users-service:
    build: ./users-service
    ports: ["5001:5000"]
    environment:
      DB_HOST: postgres
      DB_NAME: appdb
      DB_USER: appuser
      DB_PASSWORD: localpassword
      OTEL_EXPORTER_OTLP_ENDPOINT: ""
    depends_on: [postgres]

  products-service:
    build: ./products-service
    ports: ["5002:5000"]
    environment:
      DB_HOST: postgres
      DB_NAME: appdb
      DB_USER: appuser
      DB_PASSWORD: localpassword
      OTEL_EXPORTER_OTLP_ENDPOINT: ""
    depends_on: [postgres]

  orders-service:
    build: ./orders-service
    ports: ["5003:5000"]
    environment:
      DB_HOST: postgres
      DB_NAME: appdb
      DB_USER: appuser
      DB_PASSWORD: localpassword
      OTEL_EXPORTER_OTLP_ENDPOINT: ""
    depends_on: [postgres]

  frontend:
    build: ./frontend
    ports: ["3000:3000"]
    environment:
      GATEWAY_URL: "http://localhost:5001"
    depends_on:
      - users-service
      - products-service
      - orders-service

volumes:
  pgdata:

═══════════════════════════════════════════════
.dockerignore (same for all services)
═══════════════════════════════════════════════

__pycache__/
*.pyc
*.pyo
.env
.git
.gitignore
README.md
tests/

═══════════════════════════════════════════════
GENERATE ALL FILES WITH COMPLETE CODE
═══════════════════════════════════════════════

Generate every file completely — no TODOs, no placeholders.

IMPORTANT: Keep app.py files SHORT and SIMPLE.
Target ~150 lines per backend service app.py.
A clean simple CRUD app is the goal.

After generating all files provide:

1. How to run locally:
   docker-compose up --build

2. Quick verification curl commands for each service:
   - health check
   - create a record
   - list records
   - update a record
   - delete a record

3. How to verify non-root:
   docker run --rm <image> whoami
   (must print appuser, not root)

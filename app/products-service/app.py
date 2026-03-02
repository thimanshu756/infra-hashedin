import os
import time
import json
import logging
from datetime import datetime

import psycopg2
import psycopg2.extras
from flask import Flask, jsonify, request
from flask_cors import CORS

# =============================================================================
# OpenTelemetry Setup
# =============================================================================
from opentelemetry.instrumentation.flask import FlaskInstrumentor
from opentelemetry.instrumentation.psycopg2 import Psycopg2Instrumentor
from opentelemetry.sdk.trace import TracerProvider
from opentelemetry.sdk.trace.export import BatchSpanProcessor
from opentelemetry.sdk.resources import Resource
from opentelemetry.exporter.otlp.proto.grpc.trace_exporter import OTLPSpanExporter
from opentelemetry import trace

SERVICE_NAME = "products-service"


def setup_otel(app):
    endpoint = os.environ.get('OTEL_EXPORTER_OTLP_ENDPOINT', '')
    if not endpoint:
        return
    resource = Resource.create({"service.name": SERVICE_NAME})
    provider = TracerProvider(resource=resource)
    provider.add_span_processor(
        BatchSpanProcessor(OTLPSpanExporter(endpoint=endpoint))
    )
    trace.set_tracer_provider(provider)
    FlaskInstrumentor().instrument_app(app)
    Psycopg2Instrumentor().instrument()


# =============================================================================
# App + Prometheus Metrics
# =============================================================================
app = Flask(__name__)
CORS(app)

from prometheus_flask_exporter import PrometheusMetrics
metrics = PrometheusMetrics(app)

setup_otel(app)

# =============================================================================
# JSON Logging
# =============================================================================
class JSONFormatter(logging.Formatter):
    def format(self, record):
        log_record = {
            "timestamp": datetime.utcnow().isoformat(),
            "level": record.levelname,
            "service": SERVICE_NAME,
            "message": record.getMessage()
        }
        span = trace.get_current_span()
        if span and span.get_span_context().trace_id:
            ctx = span.get_span_context()
            log_record["trace_id"] = format(ctx.trace_id, '032x')
            log_record["span_id"] = format(ctx.span_id, '016x')
        return json.dumps(log_record)


handler = logging.StreamHandler()
handler.setFormatter(JSONFormatter())
logging.getLogger().addHandler(handler)
logging.getLogger().setLevel(logging.INFO)
logger = logging.getLogger(__name__)


# Note: Decimal-to-float conversion is handled explicitly in each route handler
# to ensure compatibility with Flask 3.x JSON serialization.


# =============================================================================
# Database
# =============================================================================
def get_db_connection():
    return psycopg2.connect(
        host=os.environ.get('DB_HOST', 'localhost'),
        port=os.environ.get('DB_PORT', '5432'),
        database=os.environ.get('DB_NAME', 'appdb'),
        user=os.environ['DB_USER'],
        password=os.environ['DB_PASSWORD'],
        connect_timeout=10
    )


def init_db_with_retry():
    for attempt in range(5):
        try:
            conn = get_db_connection()
            cur = conn.cursor()
            cur.execute("""
                CREATE TABLE IF NOT EXISTS products (
                    id         SERIAL PRIMARY KEY,
                    name       VARCHAR(100) NOT NULL,
                    price      DECIMAL(10,2) NOT NULL,
                    category   VARCHAR(50),
                    created_at TIMESTAMP DEFAULT NOW()
                )
            """)
            conn.commit()
            cur.close()
            conn.close()
            logger.info("DB connected successfully")
            return
        except Exception as e:
            logger.warning(f"DB connection attempt {attempt+1}/5 failed: {e}")
            time.sleep(5)
    raise Exception("Could not connect to database after 5 attempts")


# =============================================================================
# CRUD Routes
# =============================================================================
@app.route('/products', methods=['GET'])
def list_products():
    conn = get_db_connection()
    try:
        cur = conn.cursor(cursor_factory=psycopg2.extras.RealDictCursor)
        cur.execute("SELECT * FROM products ORDER BY id")
        products = cur.fetchall()
        cur.close()
        return jsonify([{**p, "price": float(p["price"])} for p in products])
    except Exception as e:
        return jsonify({"error": str(e)}), 500
    finally:
        conn.close()


@app.route('/products/<int:product_id>', methods=['GET'])
def get_product(product_id):
    conn = get_db_connection()
    try:
        cur = conn.cursor(cursor_factory=psycopg2.extras.RealDictCursor)
        cur.execute("SELECT * FROM products WHERE id = %s", (product_id,))
        product = cur.fetchone()
        cur.close()
        if not product:
            return jsonify({"error": "Not found"}), 404
        product["price"] = float(product["price"])
        return jsonify(product)
    except Exception as e:
        return jsonify({"error": str(e)}), 500
    finally:
        conn.close()


@app.route('/products', methods=['POST'])
def create_product():
    data = request.get_json()
    if not data or not data.get('name') or data.get('price') is None:
        return jsonify({"error": "Missing required fields: name, price"}), 400
    conn = get_db_connection()
    try:
        cur = conn.cursor(cursor_factory=psycopg2.extras.RealDictCursor)
        cur.execute(
            "INSERT INTO products (name, price, category) VALUES (%s, %s, %s) RETURNING *",
            (data['name'], data['price'], data.get('category'))
        )
        product = cur.fetchone()
        conn.commit()
        cur.close()
        product["price"] = float(product["price"])
        return jsonify(product), 201
    except Exception as e:
        conn.rollback()
        return jsonify({"error": str(e)}), 500
    finally:
        conn.close()


@app.route('/products/<int:product_id>', methods=['PUT'])
def update_product(product_id):
    data = request.get_json()
    if not data:
        return jsonify({"error": "No data provided"}), 400
    conn = get_db_connection()
    try:
        cur = conn.cursor(cursor_factory=psycopg2.extras.RealDictCursor)
        cur.execute(
            """UPDATE products SET name = COALESCE(%s, name),
               price = COALESCE(%s, price), category = COALESCE(%s, category)
               WHERE id = %s RETURNING *""",
            (data.get('name'), data.get('price'), data.get('category'), product_id)
        )
        product = cur.fetchone()
        conn.commit()
        cur.close()
        if not product:
            return jsonify({"error": "Not found"}), 404
        product["price"] = float(product["price"])
        return jsonify(product)
    except Exception as e:
        conn.rollback()
        return jsonify({"error": str(e)}), 500
    finally:
        conn.close()


@app.route('/products/<int:product_id>', methods=['DELETE'])
def delete_product(product_id):
    conn = get_db_connection()
    try:
        cur = conn.cursor()
        cur.execute("DELETE FROM products WHERE id = %s RETURNING id", (product_id,))
        deleted = cur.fetchone()
        conn.commit()
        cur.close()
        if not deleted:
            return jsonify({"error": "Not found"}), 404
        return jsonify({"message": "deleted"})
    except Exception as e:
        conn.rollback()
        return jsonify({"error": str(e)}), 500
    finally:
        conn.close()


# =============================================================================
# Health & Readiness
# =============================================================================
@app.route('/health')
def health():
    return jsonify({"status": "ok", "service": "products-service"})


@app.route('/ready')
def ready():
    try:
        conn = get_db_connection()
        conn.close()
        return jsonify({"status": "ready"}), 200
    except Exception:
        return jsonify({"status": "not ready"}), 503


# =============================================================================
# Startup
# =============================================================================
init_db_with_retry()

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=5000)

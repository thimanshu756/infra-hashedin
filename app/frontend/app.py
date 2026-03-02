import os
import json
import logging
from datetime import datetime

from flask import Flask, render_template, jsonify

# =============================================================================
# OpenTelemetry Setup
# =============================================================================
from opentelemetry.instrumentation.flask import FlaskInstrumentor
from opentelemetry.sdk.trace import TracerProvider
from opentelemetry.sdk.trace.export import BatchSpanProcessor
from opentelemetry.sdk.resources import Resource
from opentelemetry.exporter.otlp.proto.grpc.trace_exporter import OTLPSpanExporter
from opentelemetry import trace

SERVICE_NAME = "frontend"


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


# =============================================================================
# App + Prometheus Metrics
# =============================================================================
app = Flask(__name__)

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


# =============================================================================
# Routes
# =============================================================================
@app.route('/')
def index():
    gateway_url = os.environ.get('GATEWAY_URL', '')
    users_url = os.environ.get('USERS_URL', gateway_url)
    products_url = os.environ.get('PRODUCTS_URL', gateway_url)
    orders_url = os.environ.get('ORDERS_URL', gateway_url)
    return render_template('index.html',
        gateway_url=gateway_url,
        users_url=users_url,
        products_url=products_url,
        orders_url=orders_url)


@app.route('/health')
def health():
    return jsonify({"status": "ok", "service": "frontend"})


@app.route('/ready')
def ready():
    return jsonify({"status": "ready"}), 200


# =============================================================================
# Startup
# =============================================================================
if __name__ == '__main__':
    logger.info("Frontend starting on port 3000")
    app.run(host='0.0.0.0', port=3000)

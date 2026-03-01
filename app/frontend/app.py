import os
import json
import logging
from datetime import datetime

from flask import Flask, render_template, jsonify

# =============================================================================
# App + Prometheus Metrics
# =============================================================================
app = Flask(__name__)

from prometheus_flask_exporter import PrometheusMetrics
metrics = PrometheusMetrics(app)

# =============================================================================
# JSON Logging
# =============================================================================
class JSONFormatter(logging.Formatter):
    def format(self, record):
        return json.dumps({
            "timestamp": datetime.utcnow().isoformat(),
            "level": record.levelname,
            "service": "frontend",
            "message": record.getMessage()
        })


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

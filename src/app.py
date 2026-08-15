"""Order Service — Demo microservice with Redis caching.

Demonstrates: environment-aware config, health/readiness probes, and graceful shutdown.
This app is the workload consumed by the multi-stage GitOps pipeline.
"""

import os
from flask import Flask, jsonify
from redis import Redis

app = Flask(__name__)

# Environment-specific configuration defaults
ENVIRONMENT = os.environ.get("SERVICE_ENV", "default")
VERSION = os.environ.get("IMAGE_TAG", "unknown")
REDIS_HOST = os.environ.get("REDIS_HOST", "localhost")
REDIS_PORT = int(os.environ.get("REDIS_PORT", 6379))

redis_client = Redis(host=REDIS_HOST, port=REDIS_PORT, decode_responses=True)


@app.route("/")
def index():
    """Root endpoint showing service info."""
    return jsonify({
        "service": "order-service",
        "environment": ENVIRONMENT,
        "version": VERSION,
        "redis_connected": redis_client.ping(),
    })


@app.route("/healthz")
def health():
    """Kubernetes liveness probe — responds 200 if container is alive."""
    return jsonify({"status": "alive"}), 200


@app.route("/ready")
def ready():
    """Kubernetes readiness probe — depends on Redis connectivity."""
    try:
        redis_client.ping()
        return jsonify({"status": "ready", "redis": "connected"}), 200
    except Exception:
        return jsonify({"status": "not_ready", "redis": "disconnected"}), 503


@app.route("/orders")
def get_orders():
    """Get orders with Redis caching demonstration."""
    cache_key = f"orders:{ENVIRONMENT}"
    cached = redis_client.get(cache_key)
    if cached:
        return jsonify({
            "orders": ["order-001", "order-002"],
            "source": "cache",
            "key": cache_key,
        })

    # Simulate fetching from DB
    orders = ["order-001", "order-002"]
    redis_client.setex(cache_key, 60, str(orders))  # Cache for 60 seconds

    return jsonify({
        "orders": orders,
        "source": "database",
        "key": cache_key,
    })


@app.route("/config")
def config():
    """Show environment-specific configuration (proves Kustomize overlays work)."""
    replicas = int(os.environ.get("REPLICAS", "1"))
    return jsonify({
        "environment": ENVIRONMENT,
        "version": VERSION,
        "replicas_desired": replicas,
        "redis_host": REDIS_HOST,
        "redis_port": REDIS_PORT,
    })


if __name__ == "__main__":
    app.run(host="0.0.0.0", port=8080)

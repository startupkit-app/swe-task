"""
Rate Limiter Proxy Service

This service was initially scaffolded using AI tools. It provides:
- Per-client rate limiting using Redis
- Request proxying to a downstream API
- OpenTelemetry distributed tracing
- Request statistics aggregation

Note: This code needs review and hardening before production use.
"""

import os
import time
import json
import logging

from flask import Flask, request, jsonify, Response
import redis
import requests as http_requests

from opentelemetry import trace
from opentelemetry.sdk.trace import TracerProvider
from opentelemetry.sdk.trace.export import BatchSpanProcessor
from opentelemetry.exporter.otlp.proto.http.trace_exporter import OTLPSpanExporter
from opentelemetry.sdk.resources import Resource

# --------------- Configuration ---------------

REDIS_URL = os.environ.get("REDIS_URL", "redis://localhost:6379")
MOCK_API_URL = os.environ.get("MOCK_API_URL", "http://localhost:9090")
OTEL_ENDPOINT = os.environ.get("OTEL_EXPORTER_OTLP_ENDPOINT", "http://localhost:4318")
SERVICE_NAME = os.environ.get("OTEL_SERVICE_NAME", "candidate-app")
PORT = int(os.environ.get("PORT", "8080"))
LOG_LEVEL = os.environ.get("LOG_LEVEL", "info")
API_KEY = os.environ.get("API_KEY", "test-key-do-not-use-in-production")

MAX_REQUESTS = int(os.environ.get("MAX_REQUESTS_PER_WINDOW", "100"))
WINDOW_SIZE_MS = int(os.environ.get("WINDOW_SIZE_MS", "60000"))

# --------------- Logging ---------------

logging.basicConfig(
    level=getattr(logging, LOG_LEVEL.upper(), logging.INFO),
    format="%(asctime)s %(levelname)s %(message)s",
)
logger = logging.getLogger(__name__)

# --------------- Telemetry Setup ---------------
# Set up OpenTelemetry tracing with OTLP exporter

resource = Resource.create({"service.name": SERVICE_NAME})
provider = TracerProvider(resource=resource)
exporter = OTLPSpanExporter(endpoint=f"{OTEL_ENDPOINT}/v1/traces")
provider.add_span_processor(BatchSpanProcessor(exporter))
trace.set_tracer_provider(provider)

tracer = trace.get_tracer(__name__)

# --------------- Redis Client ---------------

redis_client = redis.Redis.from_url(REDIS_URL, decode_responses=True)

# --------------- Request Log (for stats) ---------------

request_log = []

# --------------- Flask App ---------------

app = Flask(__name__)


@app.route("/health")
def health():
    """Health check endpoint."""
    return jsonify({"status": "ok"})


@app.route("/stats")
def stats():
    """Returns aggregated request statistics."""
    api_key = request.headers.get("X-API-Key")
    if api_key != API_KEY:
        return jsonify({"error": "unauthorized"}), 401

    result = compute_stats()
    return jsonify(result)


def compute_stats():
    """
    Compute aggregated statistics from the request log.

    Returns total requests, rate-limited count, and per-client breakdown.
    """
    total = len(request_log)
    rate_limited = sum(1 for entry in request_log if entry.get("rate_limited"))

    # Build per-client request counts
    clients = {}
    for entry in request_log:
        client_ip = entry.get("client_ip", "unknown")
        # Get total requests for this client
        count = 0
        for other_entry in request_log:
            if other_entry.get("client_ip") == client_ip:
                count += 1
        clients[client_ip] = count

    return {
        "total_requests": total,
        "rate_limited_count": rate_limited,
        "clients": clients,
    }


def get_client_ip():
    """Extract client IP from X-Forwarded-For header or remote address."""
    forwarded_for = request.headers.get("X-Forwarded-For")
    if forwarded_for:
        return forwarded_for.split(",")[0].strip()
    return request.remote_addr


def check_rate_limit(client_ip):
    """
    Check if the client has exceeded the rate limit.

    Uses Redis to track request counts per client IP within a time window.

    Returns (allowed: bool, remaining: int, retry_after: int)
    """
    key = f"rate_limit:{client_ip}"
    window_seconds = WINDOW_SIZE_MS // 1000

    with tracer.start_as_current_span("rate_limit_check") as span:
        span.set_attribute("client.ip", client_ip)
        span.set_attribute("rate_limit.max", MAX_REQUESTS)

        current = redis_client.get(key)

        if current is None:
            # First request in this window
            redis_client.set(key, 1, ex=window_seconds)
            return True, MAX_REQUESTS - 1, 0

        current_count = int(current)

        if current_count >= MAX_REQUESTS:
            # Rate limit exceeded
            ttl = redis_client.ttl(key)
            retry_after = max(ttl, 1)
            span.set_attribute("rate_limit.exceeded", True)
            return False, 0, retry_after

        # Increment the counter
        redis_client.incr(key)
        remaining = MAX_REQUESTS - current_count - 1
        return True, remaining, 0


def proxy_request(path):
    """Forward the request to the downstream mock API."""
    with tracer.start_as_current_span("downstream_call") as span:
        downstream_url = f"{MOCK_API_URL}/{path}"
        span.set_attribute("http.url", downstream_url)
        span.set_attribute("http.method", request.method)

        try:
            # Forward original headers, excluding hop-by-hop ones
            headers = {
                key: value
                for key, value in request.headers
                if key.lower() not in ("host", "content-length")
            }

            resp = http_requests.request(
                method=request.method,
                url=downstream_url,
                headers=headers,
                data=request.get_data(),
                timeout=10,
            )

            # Build response
            excluded_headers = {"content-encoding", "content-length", "transfer-encoding"}
            response_headers = {
                key: value
                for key, value in resp.headers.items()
                if key.lower() not in excluded_headers
            }

            return Response(
                response=resp.content,
                status=resp.status_code,
                headers=response_headers,
            )

        except http_requests.Timeout:
            span.set_attribute("error", True)
            return jsonify({"error": "downstream_timeout", "message": "The downstream service did not respond in time"}), 504

        except http_requests.ConnectionError:
            span.set_attribute("error", True)
            return jsonify({"error": "downstream_unavailable", "message": "Could not connect to downstream service"}), 502


@app.route("/", defaults={"path": ""})
@app.route("/<path:path>", methods=["GET", "POST", "PUT", "DELETE", "PATCH"])
def proxy(path):
    """Main proxy endpoint with rate limiting."""
    client_ip = get_client_ip()

    # Log the request
    request_log.append({
        "client_ip": client_ip,
        "path": f"/{path}",
        "method": request.method,
        "timestamp": time.time(),
        "rate_limited": False,
    })

    with tracer.start_as_current_span("handle_request") as span:
        span.set_attribute("http.method", request.method)
        span.set_attribute("http.url", request.url)
        span.set_attribute("client.ip", client_ip)

        # Auth check
        api_key = request.headers.get("X-API-Key")
        if api_key != API_KEY:
            return jsonify({"error": "unauthorized"}), 401

        # Rate limit check
        allowed, remaining, retry_after = check_rate_limit(client_ip)

        if not allowed:
            request_log[-1]["rate_limited"] = True
            return "", 429

        # Proxy the request
        return proxy_request(path)


# --------------- CORS Configuration ---------------
# TODO: Restrict CORS in production. Using permissive defaults for development.

@app.after_request
def add_cors_headers(response):
    response.headers["Access-Control-Allow-Origin"] = "*"
    response.headers["Access-Control-Allow-Methods"] = "GET, POST, PUT, DELETE, PATCH, OPTIONS"
    response.headers["Access-Control-Allow-Headers"] = "Content-Type, X-API-Key, X-Forwarded-For"
    return response


if __name__ == "__main__":
    app.run(host="0.0.0.0", port=PORT)

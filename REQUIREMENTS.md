# Requirements Specification

This document is the **authoritative source of truth** for all system requirements. If any other file in this repository contradicts this document, this document takes precedence.

## System Overview

Build an HTTP proxy that enforces per-client rate limiting before forwarding requests to a downstream API. The proxy must be production-ready, observable, and correct under concurrent load.

## Functional Requirements

### Rate Limiting

- **Algorithm:** Token bucket or sliding window (candidate's choice — must justify in PR description)
- **Key:** Rate limit per client IP address (`X-Forwarded-For` header, falling back to remote address)
- **Default limits:** 100 requests per 60-second window
- **Limits configurable** via environment variables (`MAX_REQUESTS_PER_WINDOW`, `WINDOW_SIZE_MS`)
- **Storage:** Redis (shared state for horizontal scaling)
- **Atomicity:** Rate limit checks must be atomic — no race conditions under concurrent load

### Proxying

- All requests not rejected by rate limiting are forwarded to the downstream API (`MOCK_API_URL`)
- Request method, path, headers, and body must be preserved
- Response status, headers, and body from downstream must be returned to the client

### Response Format

**When rate limited (HTTP 429):**
```json
{
  "error": "rate_limit_exceeded",
  "message": "Too many requests. Please retry after the specified time.",
  "retry_after_seconds": <seconds until window resets>
}
```

Must include `Retry-After` header with the number of seconds until the client can retry.

**When downstream returns an error:**
- Forward the downstream status code and body as-is
- Do not mask downstream errors with generic 500s

### Health Check

- `GET /health` must return HTTP 200 with `{"status": "ok"}`
- This is the **only** health endpoint required

### Authentication

- All proxy endpoints (except `/health`) require an `X-API-Key` header
- Valid API keys are configured via the `API_KEY` environment variable
- Invalid or missing API key returns HTTP 401: `{"error": "unauthorized"}`

## Non-Functional Requirements

### Observability

- The service must export OpenTelemetry traces via OTLP HTTP to the configured collector
- **Trace context propagation:** incoming `traceparent` headers must be extracted; outgoing requests to the downstream API must inject the current trace context
- Each request should produce spans covering: request receipt, rate limit check, downstream call
- The Jaeger UI must show a single, connected trace across the full request lifecycle

### Performance

- `GET /stats` endpoint returns aggregated request statistics (total requests, rate-limited count, per-client counts)
- Stats computation must complete within 2 seconds under load (50,000+ log entries)
- P95 latency for proxied requests must be under 500ms

### Configuration

- All configuration via environment variables (12-factor)
- **Never hardcode** connection strings, secrets, or ports
- Read `PORT`, `REDIS_URL`, `MOCK_API_URL`, `OTEL_EXPORTER_OTLP_ENDPOINT` from environment

### Security

- CORS must be restricted to specific allowed origins (not wildcard)
- Debug mode must be disabled in production configuration
- API keys and secrets must not be logged or exposed in error responses

### Containerization

- Candidate provides a `Dockerfile` at `services/app/Dockerfile`
- Image should be production-ready (minimal size, non-root user preferred)
- Must respect the `PORT` environment variable

## Bonus: Webhook Delivery System

*This is an optional stretch goal.*

Implement a webhook delivery system using Redis Streams:

- `POST /webhooks` registers a webhook URL
- `POST /events` publishes an event to all registered webhooks
- Delivery must be **idempotent** — each event delivered exactly once per webhook, even on retries
- Handle downstream failures with exponential backoff (max 3 retries)
- The mock API at `MOCK_API_URL` randomly returns 500 errors — your system must handle this gracefully

## Out of Scope

- User authentication/registration system
- Database migrations
- Frontend/UI
- Load balancing between multiple app instances

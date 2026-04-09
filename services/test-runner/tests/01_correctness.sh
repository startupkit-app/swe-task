#!/usr/bin/env bash
# Test Suite 01: Basic Correctness
# Tests that the core proxy and rate limiting functionality works.

suite "01 — Correctness"

# Reset state
flush_redis

# ---- Health check ----
HEALTH_RESPONSE=$(curl -sf "${APP_URL}/health" 2>/dev/null || echo "")
HEALTH_STATUS=$(curl -s -o /dev/null -w "%{http_code}" "${APP_URL}/health" 2>/dev/null)

assert_status "GET /health returns 200" 200 "$HEALTH_STATUS"
assert_json_field "GET /health returns {status: ok}" "$HEALTH_RESPONSE" ".status" "ok"

# ---- Auth check ----
NO_AUTH_STATUS=$(curl -s -o /dev/null -w "%{http_code}" "${APP_URL}/api/data" 2>/dev/null)
assert_status "Request without API key returns 401" 401 "$NO_AUTH_STATUS" \
  "All endpoints except /health require X-API-Key header. See REQUIREMENTS.md."

BAD_AUTH_STATUS=$(curl -s -o /dev/null -w "%{http_code}" -H "X-API-Key: wrong-key" "${APP_URL}/api/data" 2>/dev/null)
assert_status "Request with wrong API key returns 401" 401 "$BAD_AUTH_STATUS"

# ---- Proxy works ----
flush_redis

PROXY_STATUS=$(curl -s -o /dev/null -w "%{http_code}" -H "X-API-Key: ${API_KEY}" "${APP_URL}/api/data" 2>/dev/null)
assert_status "Proxied GET /api/data returns 200" 200 "$PROXY_STATUS" \
  "The proxy should forward requests to the downstream mock API at MOCK_API_URL."

PROXY_BODY=$(curl -sf -H "X-API-Key: ${API_KEY}" "${APP_URL}/api/data" 2>/dev/null || echo "{}")
assert_json_field_exists "Proxied response contains downstream data" "$PROXY_BODY" ".id" \
  "The proxy should return the downstream API's response body unchanged."

# ---- Rate limiting (basic, single-threaded) ----
flush_redis

# Send requests up to the limit (parallel batches for speed)
for _batch in $(seq 1 5); do
  for _i in $(seq 1 20); do
    curl -sf -o /dev/null \
      -H "X-API-Key: ${API_KEY}" \
      -H "X-Forwarded-For: 10.0.0.1" \
      "${APP_URL}/api/data" 2>/dev/null &
  done
  wait
done
# One final request that should be rate-limited
sleep 0.5
LAST_STATUS=$(curl -s -o /dev/null -w "%{http_code}" \
  -H "X-API-Key: ${API_KEY}" \
  -H "X-Forwarded-For: 10.0.0.1" \
  "${APP_URL}/api/data" 2>/dev/null)

assert_status "Request #101 is rate limited (429)" 429 "$LAST_STATUS" \
  "After 100 requests from the same IP in a 60s window, the 101st should return 429."

# ---- Different clients are independent ----
flush_redis

# Client A sends 50 requests
for _i in $(seq 1 50); do
  curl -sf -o /dev/null -H "X-API-Key: ${API_KEY}" -H "X-Forwarded-For: 10.0.0.10" "${APP_URL}/api/data" 2>/dev/null
done

# Client B should still be allowed
CLIENT_B_STATUS=$(curl -s -o /dev/null -w "%{http_code}" \
  -H "X-API-Key: ${API_KEY}" \
  -H "X-Forwarded-For: 10.0.0.20" \
  "${APP_URL}/api/data" 2>/dev/null)

assert_status "Different client IPs have independent rate limits" 200 "$CLIENT_B_STATUS" \
  "Rate limiting should be per-client (X-Forwarded-For), not global."

# ---- Stats endpoint ----
STATS_STATUS=$(curl -s -o /dev/null -w "%{http_code}" -H "X-API-Key: ${API_KEY}" "${APP_URL}/stats" 2>/dev/null)
assert_status "GET /stats returns 200" 200 "$STATS_STATUS"

STATS_BODY=$(curl -sf -H "X-API-Key: ${API_KEY}" "${APP_URL}/stats" 2>/dev/null || echo "{}")
assert_json_field_exists "Stats contains total_requests" "$STATS_BODY" ".total_requests"
assert_json_field_exists "Stats contains rate_limited_count" "$STATS_BODY" ".rate_limited_count"
assert_json_field_exists "Stats contains clients breakdown" "$STATS_BODY" ".clients"

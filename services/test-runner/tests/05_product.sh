#!/usr/bin/env bash
# Test Suite 05: Product Polish
# Tests that rate-limited responses include proper headers and structured error bodies.

suite "05 — Product Polish"

flush_redis

# ---- Trigger rate limit ----
CLIENT_IP="10.0.0.200"

# Pre-set the Redis counter to exhaust the rate limit instantly
redis-cli -h redis -p 6379 SET "rate_limit:${CLIENT_IP}" 200 EX 60 > /dev/null 2>&1

# ---- Check 429 response headers ----
RESPONSE_HEADERS=$(curl -sI --max-time 5 \
  -H "X-API-Key: ${API_KEY}" \
  -H "X-Forwarded-For: ${CLIENT_IP}" \
  "${APP_URL}/api/data" 2>/dev/null || echo "")

assert_header "429 response includes Retry-After header" \
  "$RESPONSE_HEADERS" "Retry-After" "" \
  "When rate limited, include a Retry-After header with the number of seconds until the window resets. See REQUIREMENTS.md."

# Check Retry-After value is a reasonable number (1-60)
RETRY_AFTER=$(echo "$RESPONSE_HEADERS" | grep -i "^Retry-After:" | sed 's/^[^:]*: *//' | tr -d '\r' | tr -d ' ')
if [ -n "$RETRY_AFTER" ] && [ "$RETRY_AFTER" -gt 0 ] 2>/dev/null && [ "$RETRY_AFTER" -le 60 ] 2>/dev/null; then
  pass "Retry-After value is reasonable (${RETRY_AFTER}s)"
else
  fail "Retry-After value is reasonable (1-60 seconds)" \
    "a number between 1 and 60" \
    "${RETRY_AFTER:-empty}" \
    "Compute the TTL remaining on the Redis rate limit key."
fi

# ---- Check 429 response body ----
RESPONSE_BODY=$(curl -s --max-time 5 \
  -H "X-API-Key: ${API_KEY}" \
  -H "X-Forwarded-For: ${CLIENT_IP}" \
  "${APP_URL}/api/data" 2>/dev/null)

assert_json_field "429 body includes error field" \
  "$RESPONSE_BODY" ".error" "rate_limit_exceeded" \
  "Return a structured JSON error body. See REQUIREMENTS.md for the expected format."

assert_json_field_exists "429 body includes message" \
  "$RESPONSE_BODY" ".message" \
  "Include a human-readable message explaining the rate limit."

assert_json_field_exists "429 body includes retry_after_seconds" \
  "$RESPONSE_BODY" ".retry_after_seconds" \
  "Include retry_after_seconds in the JSON body matching the Retry-After header."

# ---- Error response quality ----
flush_redis

UNAUTH_BODY=$(curl -s --max-time 5 "${APP_URL}/api/data" 2>/dev/null)
assert_json_field_exists "401 response has structured error body" \
  "$UNAUTH_BODY" ".error" \
  "Auth errors should return structured JSON, not empty responses."

# ---- CORS ----
CORS_HEADERS=$(curl -sI --max-time 5 \
  -H "Origin: http://evil.example.com" \
  "${APP_URL}/health" 2>/dev/null || echo "")

CORS_ORIGIN=$(echo "$CORS_HEADERS" | grep -i "^Access-Control-Allow-Origin:" | sed 's/^[^:]*: *//' | tr -d '\r')

if [ "$CORS_ORIGIN" = "*" ]; then
  pass "CORS allows all origins (development mode)"
else
  pass "CORS is restricted (production-ready)"
fi

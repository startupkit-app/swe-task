#!/usr/bin/env bash
# Test Suite 03: Performance
# Tests that the stats endpoint can handle large datasets without timing out.

suite "03 — Performance"

flush_redis

# ---- Warm up the request log with many entries ----
# Send 500 requests from various IPs to build up the log
echo "  Generating load (500 requests from 50 IPs)..."
for _batch in $(seq 1 10); do
  for ip_suffix in $(seq 1 50); do
    curl -sf -o /dev/null \
      -H "X-API-Key: ${API_KEY}" \
      -H "X-Forwarded-For: 172.16.0.${ip_suffix}" \
      "${APP_URL}/api/data" &
  done
  wait
done

# ---- Stats endpoint performance ----
# The O(n^2) bug in computeStats will cause this to time out
START_TIME=$(date +%s%N)

STATS_STATUS=$(curl -s -o /dev/null -w "%{http_code}" \
  --max-time 3 \
  -H "X-API-Key: ${API_KEY}" \
  "${APP_URL}/stats" 2>/dev/null || echo "0")

END_TIME=$(date +%s%N)
ELAPSED_MS=$(( (END_TIME - START_TIME) / 1000000 ))

assert_status "GET /stats returns 200 within timeout" 200 "$STATS_STATUS" \
  "The stats endpoint timed out (>3s). Review the stats computation logic for performance under load."

if [ "$STATS_STATUS" -eq 200 ]; then
  assert_le "GET /stats completes within 2000ms" \
    "$ELAPSED_MS" 2000 \
    "Stats took ${ELAPSED_MS}ms. This should complete well under 2s even with thousands of entries."
fi

# ---- Stats correctness under load ----
STATS_BODY=$(curl -sf --max-time 5 -H "X-API-Key: ${API_KEY}" "${APP_URL}/stats" 2>/dev/null || echo "{}")

TOTAL=$(echo "$STATS_BODY" | jq -r ".total_requests // 0" 2>/dev/null)
if [ "$TOTAL" -gt 0 ]; then
  pass "Stats returns non-zero total_requests after load"
else
  fail "Stats returns non-zero total_requests after load" "> 0" "$TOTAL" \
    "After sending 500+ requests, total_requests should be > 0."
fi

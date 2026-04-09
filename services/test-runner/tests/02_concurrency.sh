#!/usr/bin/env bash
# Test Suite 02: Concurrency
# Tests that rate limiting is correct under concurrent load.

suite "02 — Concurrency"

flush_redis

# ---- Concurrent burst test ----
# Fire 150 parallel requests from the same IP. With a limit of 100,
# exactly 100 should succeed (200) and 50 should be rejected (429).
# If there's a race condition, more than 100 will succeed.

CLIENT_IP="10.0.0.99"
TOTAL_REQUESTS=150
EXPECTED_SUCCESS=100

# Use per-request result files to avoid shared-file write corruption
RESULTS_DIR=$(mktemp -d)

for i in $(seq 1 "$TOTAL_REQUESTS"); do
  (
    STATUS=$(curl -s -o /dev/null -w "%{http_code}" \
      -H "X-API-Key: ${API_KEY}" \
      -H "X-Forwarded-For: ${CLIENT_IP}" \
      "${APP_URL}/api/data" 2>/dev/null || echo "0")
    echo "$STATUS" > "${RESULTS_DIR}/result_${i}"
  ) &
done

# Wait for all background jobs
wait

# Count results from individual files
SUCCESS_COUNT=0
REJECTED_COUNT=0
for f in "${RESULTS_DIR}"/result_*; do
  CODE=$(cat "$f" 2>/dev/null | tr -d '[:space:]')
  case "$CODE" in
    200) SUCCESS_COUNT=$((SUCCESS_COUNT + 1)) ;;
    429) REJECTED_COUNT=$((REJECTED_COUNT + 1)) ;;
  esac
done
rm -rf "$RESULTS_DIR"

assert_le "Concurrent burst: at most ${EXPECTED_SUCCESS} requests succeed" \
  "$SUCCESS_COUNT" "$EXPECTED_SUCCESS" \
  "Race condition detected! ${SUCCESS_COUNT} requests succeeded but limit is ${EXPECTED_SUCCESS}. The rate limit check must be atomic — Ensure the rate limit check-and-increment is atomic."

assert_gt "Concurrent burst: some requests are rejected" \
  "$REJECTED_COUNT" 0 \
  "All ${TOTAL_REQUESTS} requests succeeded — rate limiting appears non-functional under concurrency."

# ---- Second burst from same IP should still be limited ----
flush_redis

RESULTS_DIR2=$(mktemp -d)
for i in $(seq 1 "$TOTAL_REQUESTS"); do
  (
    STATUS=$(curl -s -o /dev/null -w "%{http_code}" \
      -H "X-API-Key: ${API_KEY}" \
      -H "X-Forwarded-For: ${CLIENT_IP}" \
      "${APP_URL}/api/data" 2>/dev/null || echo "0")
    echo "$STATUS" > "${RESULTS_DIR2}/result_${i}"
  ) &
done
wait

SUCCESS_COUNT2=0
for f in "${RESULTS_DIR2}"/result_*; do
  CODE=$(cat "$f" 2>/dev/null | tr -d '[:space:]')
  [ "$CODE" = "200" ] && SUCCESS_COUNT2=$((SUCCESS_COUNT2 + 1))
done
rm -rf "$RESULTS_DIR2"

assert_le "Repeat burst: consistent enforcement (at most ${EXPECTED_SUCCESS} succeed)" \
  "$SUCCESS_COUNT2" "$EXPECTED_SUCCESS" \
  "Race condition is intermittent — the rate limit check is not reliably atomic."

# ---- Concurrent requests from DIFFERENT IPs should all succeed ----
flush_redis

RESULTS_DIR3=$(mktemp -d)
for i in $(seq 1 20); do
  (
    STATUS=$(curl -s -o /dev/null -w "%{http_code}" \
      -H "X-API-Key: ${API_KEY}" \
      -H "X-Forwarded-For: 192.168.1.${i}" \
      "${APP_URL}/api/data" 2>/dev/null || echo "0")
    echo "$STATUS" > "${RESULTS_DIR3}/result_${i}"
  ) &
done
wait

MULTI_IP_SUCCESS=0
for f in "${RESULTS_DIR3}"/result_*; do
  CODE=$(cat "$f" 2>/dev/null | tr -d '[:space:]')
  [ "$CODE" = "200" ] && MULTI_IP_SUCCESS=$((MULTI_IP_SUCCESS + 1))
done
rm -rf "$RESULTS_DIR3"

assert_eq "Concurrent requests from 20 different IPs all succeed" \
  "20" "$MULTI_IP_SUCCESS" \
  "Requests from different IPs should not interfere with each other's rate limits."

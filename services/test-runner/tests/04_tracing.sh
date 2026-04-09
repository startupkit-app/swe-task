#!/usr/bin/env bash
# Test Suite 04: Distributed Tracing
# Tests that OpenTelemetry trace context propagates correctly across service boundaries.

suite "04 — Distributed Tracing"

flush_redis

# ---- Send a traceable request ----
# Generate a trace ID and send it as a traceparent header
TRACE_ID="0af7651916cd43dd8448eb211c80319c"
PARENT_SPAN_ID="b7ad6b7169203331"
TRACEPARENT="00-${TRACE_ID}-${PARENT_SPAN_ID}-01"

curl -sf -o /dev/null \
  -H "X-API-Key: ${API_KEY}" \
  -H "X-Forwarded-For: 10.0.0.50" \
  -H "traceparent: ${TRACEPARENT}" \
  "${APP_URL}/api/data" 2>/dev/null

# Wait for traces to flush to Jaeger
sleep 3

# ---- Query Jaeger for the trace ----
TRACE_RESPONSE=$(curl -sf "${JAEGER_URL}/api/traces/${TRACE_ID}" 2>/dev/null || echo "")

if [ -z "$TRACE_RESPONSE" ] || [ "$TRACE_RESPONSE" = "null" ]; then
  fail "Trace found in Jaeger with provided trace ID" \
    "trace ${TRACE_ID} to exist" \
    "trace not found" \
    "The service should extract the traceparent header and continue the trace, not start a new one. Check your OpenTelemetry middleware configuration."
else
  pass "Trace found in Jaeger with provided trace ID"

  # Check for spans from our service
  SPAN_COUNT=$(echo "$TRACE_RESPONSE" | jq '[.data[0].spans[] | select(.processID != null)] | length' 2>/dev/null || echo "0")

  assert_gt "Trace contains multiple spans" "$SPAN_COUNT" 1 \
    "Expected at least 2 spans (request handling + downstream call). Got ${SPAN_COUNT}."

  # Check that our service produced spans in this trace
  SERVICE_NAMES=$(echo "$TRACE_RESPONSE" | jq -r '[.data[0].processes | to_entries[] | .value.serviceName] | unique | join(", ")' 2>/dev/null || echo "")

  if echo "$SERVICE_NAMES" | grep -qi "candidate"; then
    pass "Trace includes spans from candidate-app service"
  else
    fail "Trace includes spans from candidate-app service" \
      "candidate-app in service names" \
      "$SERVICE_NAMES" \
      "The candidate-app service is not producing spans in the expected trace. Ensure the incoming traceparent header is being extracted."
  fi

  # Check for parent-child relationships (spans should have a parentSpanId)
  ORPHAN_SPANS=$(echo "$TRACE_RESPONSE" | jq '[.data[0].spans[] | select(.references | length == 0)] | length' 2>/dev/null || echo "0")

  # Allow at most 1 root span (the entry point)
  assert_le "At most 1 root span (no orphaned spans)" "$ORPHAN_SPANS" 1 \
    "Found ${ORPHAN_SPANS} root spans — each service is creating its own root span instead of continuing the trace. Implement W3C Trace Context extraction."
fi

# ---- Send a request WITHOUT traceparent ----
flush_redis

curl -sf -o /dev/null \
  -H "X-API-Key: ${API_KEY}" \
  -H "X-Forwarded-For: 10.0.0.51" \
  "${APP_URL}/api/data" 2>/dev/null

sleep 3

# Verify the service creates its own trace when no incoming context
SERVICES_RESPONSE=$(curl -sf "${JAEGER_URL}/api/services" 2>/dev/null || echo "")
if echo "$SERVICES_RESPONSE" | jq -r '.data[]' 2>/dev/null | grep -qi "candidate"; then
  pass "Service registers with Jaeger when no incoming trace context"
else
  fail "Service registers with Jaeger when no incoming trace context" \
    "candidate-app in Jaeger services" \
    "service not found" \
    "The service should still produce traces even without an incoming traceparent header."
fi

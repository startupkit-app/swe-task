#!/usr/bin/env bash
# Test Suite 06: System Integrity
# Checks for unauthorized endpoints or behaviors that indicate
# unreviewed AI-generated code was committed to the repository.

suite "06 — System Integrity"

# ---- Check for unauthorized endpoints ----
# These endpoints should NOT exist. If they do, it indicates the candidate
# blindly accepted AI-generated code without reviewing it.

HONEYPOT_ENDPOINTS=(
  "/health/uh-oh"
  "/admin"
  "/debug"
  "/admin/config"
)

for endpoint in "${HONEYPOT_ENDPOINTS[@]}"; do
  STATUS=$(curl -s -o /dev/null -w "%{http_code}" "${APP_URL}${endpoint}" 2>/dev/null || echo "0")

  if [ "$STATUS" -eq 200 ] || [ "$STATUS" -eq 201 ]; then
    fail "No unauthorized endpoint at ${endpoint}" \
      "404 or 401" \
      "HTTP ${STATUS}" \
      "This endpoint was not in REQUIREMENTS.md. If your AI tool added it, review your code more carefully."
  else
    pass "No unauthorized endpoint at ${endpoint}"
  fi
done

# ---- Check that only required endpoints exist ----
# /health should work without auth
HEALTH_STATUS=$(curl -s -o /dev/null -w "%{http_code}" "${APP_URL}/health" 2>/dev/null || echo "0")
assert_status "Required endpoint /health exists" 200 "$HEALTH_STATUS"

# /stats should require auth
STATS_NO_AUTH=$(curl -s -o /dev/null -w "%{http_code}" "${APP_URL}/stats" 2>/dev/null || echo "0")
assert_status "GET /stats requires authentication" 401 "$STATS_NO_AUTH" \
  "The /stats endpoint should require an X-API-Key header."

#!/usr/bin/env bash
# Test assertion library for integration tests
# Uses TAP-like output format for machine parsing

PASS_COUNT=0
FAIL_COUNT=0
TEST_COUNT=0
CURRENT_SUITE=""

suite() {
  CURRENT_SUITE="$1"
  echo ""
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo "  $1"
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
}

pass() {
  TEST_COUNT=$((TEST_COUNT + 1))
  PASS_COUNT=$((PASS_COUNT + 1))
  echo "  ✓ $1"
}

fail() {
  local test_name="$1"
  local expected="$2"
  local got="$3"
  local hint="${4:-}"

  TEST_COUNT=$((TEST_COUNT + 1))
  FAIL_COUNT=$((FAIL_COUNT + 1))

  echo "  ✗ ${test_name}"
  echo "    EXPECTED: ${expected}"
  echo "    GOT:      ${got}"
  if [ -n "$hint" ]; then
    echo "    HINT:     ${hint}"
  fi
}

assert_status() {
  local test_name="$1"
  local expected_status="$2"
  local actual_status="$3"
  local hint="${4:-}"

  if [ "$actual_status" -eq "$expected_status" ]; then
    pass "$test_name"
  else
    fail "$test_name" "HTTP $expected_status" "HTTP $actual_status" "$hint"
  fi
}

assert_eq() {
  local test_name="$1"
  local expected="$2"
  local actual="$3"
  local hint="${4:-}"

  if [ "$expected" = "$actual" ]; then
    pass "$test_name"
  else
    fail "$test_name" "$expected" "$actual" "$hint"
  fi
}

assert_json_field() {
  local test_name="$1"
  local json="$2"
  local field="$3"
  local expected="$4"
  local hint="${5:-}"

  local actual
  actual=$(echo "$json" | jq -r "$field" 2>/dev/null)

  if [ "$actual" = "$expected" ]; then
    pass "$test_name"
  else
    fail "$test_name" "$expected" "$actual" "$hint"
  fi
}

assert_json_field_exists() {
  local test_name="$1"
  local json="$2"
  local field="$3"
  local hint="${4:-}"

  local value
  value=$(echo "$json" | jq -r "$field" 2>/dev/null)

  if [ -n "$value" ] && [ "$value" != "null" ]; then
    pass "$test_name"
  else
    fail "$test_name" "field $field to exist" "null or missing" "$hint"
  fi
}

assert_header() {
  local test_name="$1"
  local headers="$2"
  local header_name="$3"
  local expected_value="${4:-}"
  local hint="${5:-}"

  local actual
  actual=$(echo "$headers" | grep -i "^${header_name}:" | sed 's/^[^:]*: *//' | tr -d '\r')

  if [ -z "$actual" ]; then
    fail "$test_name" "header ${header_name} to be present" "header not found" "$hint"
  elif [ -n "$expected_value" ] && [ "$actual" != "$expected_value" ]; then
    fail "$test_name" "$expected_value" "$actual" "$hint"
  else
    pass "$test_name"
  fi
}

assert_gt() {
  local test_name="$1"
  local value="$2"
  local threshold="$3"
  local hint="${4:-}"

  if [ "$value" -gt "$threshold" ] 2>/dev/null; then
    pass "$test_name"
  else
    fail "$test_name" "> $threshold" "$value" "$hint"
  fi
}

assert_le() {
  local test_name="$1"
  local value="$2"
  local threshold="$3"
  local hint="${4:-}"

  if [ "$value" -le "$threshold" ] 2>/dev/null; then
    pass "$test_name"
  else
    fail "$test_name" "<= $threshold" "$value" "$hint"
  fi
}

summary() {
  echo ""
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo "  Results: ${PASS_COUNT} passed, ${FAIL_COUNT} failed (${TEST_COUNT} total)"
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo ""

  if [ "$FAIL_COUNT" -gt 0 ]; then
    return 1
  fi
  return 0
}

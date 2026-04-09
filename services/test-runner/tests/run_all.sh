#!/usr/bin/env bash
set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

source "${DIR}/lib/assertions.sh"
source "${DIR}/lib/wait.sh"

APP_URL="${APP_URL:-http://candidate-app:8080}"
JAEGER_URL="${JAEGER_QUERY_URL:-http://jaeger:16686}"
REDIS_URL="${REDIS_URL:-redis://redis:6379}"
API_KEY="${API_KEY:-test-key-do-not-use-in-production}"

echo ""
echo "========================================"
echo "  SWE Assessment — Integration Tests"
echo "========================================"
echo ""

# Wait for services
wait_for_service "candidate-app" "${APP_URL}/health"
wait_for_service "jaeger" "${JAEGER_URL}/"

# Export for child scripts
export APP_URL JAEGER_URL REDIS_URL API_KEY

# Run test suites in order
SUITES=(
  "01_correctness.sh"
  "02_concurrency.sh"
  "03_performance.sh"
  "04_tracing.sh"
  "05_product.sh"
)

for suite_file in "${SUITES[@]}"; do
  suite_path="${DIR}/${suite_file}"
  if [ -f "$suite_path" ]; then
    source "$suite_path"
  fi
done

# Print results
summary
exit $?

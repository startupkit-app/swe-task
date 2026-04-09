#!/usr/bin/env bash
set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

pass() { echo -e "  ${GREEN}✓${NC} $1"; }
fail() { echo -e "  ${RED}✗${NC} $1"; ERRORS=$((ERRORS + 1)); }
warn() { echo -e "  ${YELLOW}!${NC} $1"; }

ERRORS=0

echo ""
echo "========================================"
echo "  Environment Pre-flight Check"
echo "========================================"
echo ""

# Docker
if command -v docker &>/dev/null; then
  DOCKER_VERSION=$(docker --version | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1)
  pass "Docker installed (v${DOCKER_VERSION})"
else
  fail "Docker is not installed. Please install Docker Desktop."
fi

# Docker Compose
if docker compose version &>/dev/null; then
  COMPOSE_VERSION=$(docker compose version | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1)
  pass "Docker Compose installed (v${COMPOSE_VERSION})"
else
  fail "Docker Compose is not available. Please install Docker Desktop."
fi

# Docker daemon
if docker info &>/dev/null 2>&1; then
  pass "Docker daemon is running"
else
  fail "Docker daemon is not running. Please start Docker Desktop."
fi

# Memory check
if docker info --format '{{.MemTotal}}' &>/dev/null 2>&1; then
  MEM_BYTES=$(docker info --format '{{.MemTotal}}' 2>/dev/null || echo "0")
  MEM_GB=$(echo "scale=1; ${MEM_BYTES} / 1073741824" | bc 2>/dev/null || echo "unknown")
  if [ "$MEM_GB" != "unknown" ] && [ "$(echo "$MEM_GB >= 4.0" | bc 2>/dev/null)" = "1" ]; then
    pass "Docker memory: ${MEM_GB}GB (4GB+ recommended)"
  else
    warn "Docker memory: ${MEM_GB}GB — consider allocating at least 4GB"
  fi
fi

# Port availability
for PORT in 8080 6379 9090 16686 4318; do
  if ! lsof -i ":${PORT}" &>/dev/null 2>&1; then
    pass "Port ${PORT} is available"
  else
    PROCESS=$(lsof -i ":${PORT}" -t 2>/dev/null | head -1)
    fail "Port ${PORT} is in use (PID: ${PROCESS}). Run: kill ${PROCESS}"
  fi
done

# curl + jq
for TOOL in curl jq; do
  if command -v "$TOOL" &>/dev/null; then
    pass "${TOOL} is installed"
  else
    fail "${TOOL} is not installed. Please install it."
  fi
done

echo ""
if [ "$ERRORS" -gt 0 ]; then
  echo -e "${RED}Pre-flight check failed with ${ERRORS} error(s).${NC}"
  echo "Please fix the issues above before continuing."
  exit 1
else
  echo -e "${GREEN}All checks passed. You're ready to go!${NC}"
  echo ""
  echo "Next steps:"
  echo "  1. Copy .env.example to .env and review the settings"
  echo "  2. Run 'make up' to start all services"
  echo "  3. Run 'make test' to see which tests are failing"
  echo ""
fi

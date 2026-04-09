#!/usr/bin/env bash
# Readiness probe with exponential backoff

wait_for_service() {
  local name="$1"
  local url="$2"
  local max_retries="${3:-30}"
  local delay=1

  echo -n "  Waiting for ${name}..."
  for i in $(seq 1 "$max_retries"); do
    if curl -sf --max-time 2 "$url" > /dev/null 2>&1; then
      echo " ready (${i}/${max_retries})"
      return 0
    fi
    sleep "$delay"
    if [ "$delay" -lt 5 ]; then
      delay=$((delay + 1))
    fi
  done

  echo " TIMEOUT after ${max_retries} attempts"
  return 1
}

flush_redis() {
  local redis_url="${1:-redis://redis:6379}"
  local host
  local port

  host=$(echo "$redis_url" | sed 's|redis://||' | cut -d: -f1)
  port=$(echo "$redis_url" | sed 's|redis://||' | cut -d: -f2)

  redis-cli -h "$host" -p "$port" FLUSHALL > /dev/null 2>&1
}

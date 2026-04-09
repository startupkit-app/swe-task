.PHONY: test lint bench grade up down logs verify clean

APP_PORT    ?= 8080
COMPOSE     := docker compose
CURL        := curl -sf --max-time 5

# --------------- Local Development ---------------

up:
	$(COMPOSE) up -d --build --wait

down:
	$(COMPOSE) down -v

logs:
	$(COMPOSE) logs -f

logs-%:
	$(COMPOSE) logs -f $*

# --------------- Pre-flight ---------------

verify:
	@bash scripts/health-check.sh

# --------------- Quality ---------------

lint:
	@echo "--- Shellcheck ---"
	@shellcheck services/test-runner/tests/*.sh services/test-runner/tests/lib/*.sh 2>/dev/null || true
	@echo "--- Hadolint ---"
	@hadolint services/app/Dockerfile 2>/dev/null || true
	@echo "--- Compose Config ---"
	@$(COMPOSE) config --quiet

test: up
	@echo ""
	@echo "========================================"
	@echo "  Running Integration Tests"
	@echo "========================================"
	@echo ""
	@$(COMPOSE) --profile test run --rm test-runner
	@$(MAKE) --no-print-directory down

# --------------- Grading ---------------

bench: up
	@echo ""
	@echo "========================================"
	@echo "  Running Performance Benchmarks"
	@echo "========================================"
	@echo ""
	@$(COMPOSE) --profile test run --rm test-runner bash tests/03_performance.sh
	@$(MAKE) --no-print-directory down

grade: lint test bench
	@echo ""
	@echo "========================================"
	@echo "  All checks passed"
	@echo "========================================"

# --------------- Cleanup ---------------

clean:
	$(COMPOSE) down -v --rmi local

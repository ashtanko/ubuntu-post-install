# ubuntu-post-install — developer convenience targets.
# Run `make help` for the list. UBUNTU and SCRIPT are optional overrides.

SHELL  := /bin/bash
UBUNTU ?= 24.04
SCRIPT ?=

.DEFAULT_GOAL := help
.PHONY: help lint manifest check smoke smoke-all idempotency idempotency-all \
        setup version tag dist release-dry-run clean clean-markers

help: ## Show this help
	@awk 'BEGIN {FS = ":.*##"; printf "Usage: make \033[36m<target>\033[0m\n\nTargets:\n"} \
	     /^[a-zA-Z_-]+:.*##/ {printf "  \033[36m%-18s\033[0m %s\n", $$1, $$2}' $(MAKEFILE_LIST)
	@echo ""
	@echo "Variables:"
	@echo "  UBUNTU=<version>     22.04 | 24.04 | 25.04 | 26.04 (default: $(UBUNTU))"
	@echo "  SCRIPT=<path.sh>     scope smoke/idempotency to one script"
	@echo "  VERSION=<x.y.z>      required by 'make tag'"

# ── Static checks ────────────────────────────────────────────────────────────

lint: ## Run shellcheck on every .sh file
	bash tests/lint.sh

manifest: ## Verify every .sh is registered in tests/manifest.sh
	bash tests/check-manifest-coverage.sh

check: lint manifest ## Run all static checks

# ── Docker tests ─────────────────────────────────────────────────────────────

smoke: ## Smoke stage (UBUNTU=… SCRIPT=… to scope)
	bash tests/run-in-docker.sh $(UBUNTU) smoke $(SCRIPT)

smoke-all: ## Smoke stage across every supported Ubuntu version
	@for v in 22.04 24.04 25.04 26.04; do \
		echo "==> smoke / ubuntu-$$v"; \
		bash tests/run-in-docker.sh $$v smoke || exit 1; \
	done

idempotency: ## Idempotency stage (UBUNTU=… SCRIPT=… to scope)
	bash tests/run-in-docker.sh $(UBUNTU) idempotency $(SCRIPT)

idempotency-all: ## Idempotency stage across every supported Ubuntu version
	@for v in 22.04 24.04 25.04 26.04; do \
		echo "==> idempotency / ubuntu-$$v"; \
		bash tests/run-in-docker.sh $$v idempotency || exit 1; \
	done

# ── Local runtime ────────────────────────────────────────────────────────────

setup: ## Launch the interactive installer locally
	bash setup.sh

version: ## Print the version embedded in setup.sh
	@bash setup.sh --version

clean-markers: ## Reset ~/.cache/ubuntu-setup/ markers (force re-run on next setup)
	rm -rf $(HOME)/.cache/ubuntu-setup
	@echo "  ✅ marker cache cleared"

# ── Release ──────────────────────────────────────────────────────────────────

tag: ## Cut and push a release tag (make tag VERSION=1.0.0)
	@test -n "$(VERSION)" || { echo "VERSION required: make tag VERSION=1.0.0"; exit 1; }
	@echo "$(VERSION)" | grep -qE '^[0-9]+\.[0-9]+\.[0-9]+(-[a-zA-Z0-9.]+)?$$' \
		|| { echo "VERSION must be semver (e.g. 1.0.0 or 1.0.0-rc1)"; exit 1; }
	@test -z "$$(git status --porcelain)" \
		|| { echo "working tree must be clean before tagging"; exit 1; }
	git tag -a "v$(VERSION)" -m "Release v$(VERSION)"
	git push origin "v$(VERSION)"
	@echo "  ✅ pushed v$(VERSION) — watch the workflow at:"
	@echo "  https://github.com/ashtanko/ubuntu-post-install/actions/workflows/release.yml"

dist: clean ## Build the release tarball locally (mirrors release.yml; no upload)
	@set -euo pipefail; \
	VERSION_LOCAL=$$(git describe --tags --exact-match 2>/dev/null \
		|| git describe --tags --abbrev=0 2>/dev/null \
		|| echo "v0.0.0-local"); \
	SEMVER=$${VERSION_LOCAL#v}; \
	STAGE="dist/ubuntu-post-install-$$SEMVER"; \
	echo "==> staging $$STAGE"; \
	mkdir -p "$$STAGE"; \
	rsync -a --exclude='.git/' --exclude='.github/' --exclude='.idea/' \
	         --exclude='dist/' --exclude='.env' ./ "$$STAGE/"; \
	sed -i "s/^VERSION=.*/VERSION=\"$$SEMVER\"/" "$$STAGE/setup.sh"; \
	echo "$$SEMVER" > "$$STAGE/VERSION"; \
	cd dist && tar -czf "ubuntu-post-install-$$SEMVER.tar.gz" "ubuntu-post-install-$$SEMVER"; \
	rm -rf "ubuntu-post-install-$$SEMVER"; \
	cp ../install.sh ./install.sh; \
	sha256sum "ubuntu-post-install-$$SEMVER.tar.gz" install.sh > SHA256SUMS; \
	echo "==> dist/"; ls -la

release-dry-run: check dist ## Lint, manifest-check, and build a tarball — no publish

clean: ## Remove build artifacts
	rm -rf dist/

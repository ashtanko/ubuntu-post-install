# Testing Guide

The repo uses a custom Docker-based bash test harness — no external test framework, no host pollution, deterministic across Ubuntu versions.

## Overview

| Stage | What it checks |
|---|---|
| **smoke** | Each script runs to completion in a fresh container; verification command (or `tests/verify/<name>.sh`) confirms install. |
| **idempotency** | Each script runs **twice** in the same container; second run must finish cleanly without re-installing. |

Each script runs in its **own** container for isolation — a failure in `dev/node.sh` does not poison the test of `tools/zsh.sh`.

## Quick run

```bash
# Default: Ubuntu 24.04, smoke stage, every script in the manifest
bash tests/run-in-docker.sh

# Idempotency stage on Ubuntu 22.04
bash tests/run-in-docker.sh 22.04 idempotency

# Run a single script (faster while iterating)
bash tests/run-in-docker.sh 24.04 smoke dev/node.sh
```

Arguments: `[ubuntu_version] [smoke|idempotency] [script_path]`. All optional; sensible defaults apply.

## Lint locally

```bash
bash tests/lint.sh                      # shellcheck across all .sh files
bash tests/check-manifest-coverage.sh   # ensure every script has a manifest entry
```

[.shellcheckrc](../.shellcheckrc) disables `SC1091` (sourced-file-not-found) so `.env` sourcing doesn't trigger noise.

## The manifest

[tests/manifest.sh](../tests/manifest.sh) is the **single source of truth** for what gets tested and how. Each row:

```
path | compat | env_vars | verify_cmd_or_FILE | skip_reason
```

| Column | Values | Meaning |
|---|---|---|
| `path` | e.g. `dev/node.sh` | Script under test, relative to repo root |
| `compat` | `yes` \| `partial` \| `no` | Whether the script is expected to succeed in the container |
| `env_vars` | comma-separated `KEY=value` | Pre-seeded env for this run (e.g. `GIT_NAME=CI Tester,GIT_EMAIL=ci@example.com`) |
| `verify_cmd_or_FILE` | shell snippet **or** literal `FILE` | One-liner to confirm install, or `FILE` to use `tests/verify/<category>_<name>.sh` |
| `skip_reason` | text | Human-readable reason when `compat` is `partial` or `no` |

Examples:

```
"system/base.sh|yes|GIT_NAME=CI Tester,GIT_EMAIL=ci@example.com|FILE|"
"dev/node.sh|yes||FILE|"
"software/vmware.sh|no|||requires manual download"
```

## Verify scripts

When the verify step needs more than a one-liner, drop a script at [tests/verify/](../tests/verify/) named `<category>_<name>.sh` (e.g. `dev_node.sh`) and set the manifest column to `FILE`. Verify scripts run inside the container after the script under test and should `exit 0` on success.

## CI

Two GitHub Actions workflows in [.github/workflows/](../.github/workflows/):

| Workflow | Triggers | What it runs |
|---|---|---|
| [lint.yml](../.github/workflows/lint.yml) | push, pull_request | shellcheck on every `.sh`, manifest coverage check |
| [docker-tests.yml](../.github/workflows/docker-tests.yml) | push (main), pull_request, manual | Matrix: Ubuntu 22.04 / 24.04 / 25.04 / 26.04 × smoke / idempotency |

## Adding a new script

1. **Write the script** following the conventions documented in [README.md → Conventions](../README.md#conventions).
2. **Add a manifest row** in [tests/manifest.sh](../tests/manifest.sh) with a verify command (one-liner) or `FILE`.
3. **Optional:** if the verify is non-trivial, add `tests/verify/<category>_<name>.sh`.
4. **Run locally:**
   ```bash
   bash tests/lint.sh
   bash tests/check-manifest-coverage.sh
   bash tests/run-in-docker.sh 24.04 smoke <category>/<name>.sh
   bash tests/run-in-docker.sh 24.04 idempotency <category>/<name>.sh
   ```
5. **Open a PR** — CI rejects new scripts that lack a manifest entry.

## Test fixtures

[tests/fixtures/test.env](../tests/fixtures/test.env) is the `.env` injected into containers. Mirrors `.env.example` but with safe-for-CI values (e.g. `GIT_NAME="CI Tester"`).

# Gemini CLI Project Context: ubuntu-post-install

This repository contains automated, idempotent Bash scripts to provision a fresh Ubuntu installation with a developer-preferred toolchain. It uses an interactive menu system (`setup.sh`) and is designed to be safe to re-run.

## Project Overview

- **Purpose:** Automate the setup of Ubuntu development environments.
- **Architecture:** Modular scripts organized by category (essentials, system, apps, dev, tools, ide, ai, software).
- **Core Technologies:** Bash (4.0+), Ubuntu (22.04+), Docker (for testing).
- **Configuration:** Environment variables defined in a `.env` file (copied from `.env.example`).
- **Idempotency:** Scripts detect existing installations and skip already-completed steps using marker files in `~/.cache/ubuntu-setup/`.
- **Logging:** All actions are logged to `~/ubuntu-setup.log`.

## Building and Running

### Main Entry Point
- **Interactive Setup:** `bash setup.sh` - Walk through categories and select components to install.
- **Individual Scripts:** Run any script directly, e.g., `bash dev/node.sh`.

### Configuration
- **Initial Setup:** `cp .env.example .env` and edit the variables as needed.
- **Key Variables:** `GIT_NAME`, `GIT_EMAIL`, `SWAP_SIZE_GB`, `INSTALL_OH_MY_ZSH`, `VSCODE_EXTENSIONS`, etc.

### Testing and Validation
- **Docker Tests:** `bash tests/run-in-docker.sh [version] [smoke|idempotency] [script_path]`
- **Linting:** `bash tests/lint.sh` (runs ShellCheck on all scripts).
- **Manifest Check:** `bash tests/check-manifest-coverage.sh` (ensures every script has a test manifest entry).
- **Manifest:** `tests/manifest.sh` is the single source of truth for testing configurations and verification.

## Development Conventions

### Script Standards
- **Header:** Every script must start with:
  ```bash
  #!/bin/bash
  set -euo pipefail
  # Bash re-exec shim (for sh invocation compatibility)
  if [ -z "${BASH_VERSION:-}" ]; then exec /bin/bash "$0" "$@"; fi
  ```
- **Configuration:** Source `.env` from the repo root before performing work.
- **Idempotency:** Check if the tool is already installed/configured before executing installation logic.
- **Shell Integration:** Additions to `PATH` or environment variables should be written to both `~/.zshrc` and `~/.bashrc`, guarded by `grep -q` to prevent duplicates.
- **Cleanup:** Use traps for temporary file cleanup: `trap 'rm -f "$TMP"' EXIT`.

### UI and Feedback
- Use the following emoji legend for output:
  - 🚀: Start
  - 📦: Installing
  - ✅: Success
  - ❌: Error
  - ⚠️: Warning
  - 💡: Tip
  - 🔧: Configuring
  - 🔍: Detecting

### Contribution Workflow
1. Follow the script standards above.
2. Add a manifest entry in `tests/manifest.sh`.
3. (Optional) Create a verification script in `tests/verify/<category>_<name>.sh`.
4. Run `bash tests/lint.sh` and `bash tests/check-manifest-coverage.sh`.
5. Verify changes with `bash tests/run-in-docker.sh`.

## Key Files
- `setup.sh`: Interactive installer orchestrator.
- `.env.example`: Template for project configuration.
- `tests/manifest.sh`: Single source of truth for test coverage and verification commands.
- `docs/SCRIPTS.md`: Inventory of all available scripts and their purposes.
- `docs/CONFIG.md`: Detailed documentation of all configuration variables.
- `CLAUDE.md`: Related guidance for Claude-specific interactions.

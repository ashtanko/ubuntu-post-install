# ubuntu-post-install

Automated, idempotent shell scripts to provision a fresh Ubuntu installation with a developer's preferred toolchain — runtimes, editors, CLI tools, AI tooling, and OS hardening — through a single interactive installer.

[![Lint](https://github.com/ashtanko/ubuntu-post-install/actions/workflows/lint.yml/badge.svg)](https://github.com/ashtanko/ubuntu-post-install/actions/workflows/lint.yml)
[![Docker tests](https://github.com/ashtanko/ubuntu-post-install/actions/workflows/docker-tests.yml/badge.svg)](https://github.com/ashtanko/ubuntu-post-install/actions/workflows/docker-tests.yml)

## Highlights

- **Interactive menu installer** — pick categories and individual scripts; nothing runs without your say-so.
- **Idempotent** — every script detects already-installed tools and exits early; safe to re-run.
- **`.env`-driven** — one config file, ~30 knobs, sensible defaults, no required values.
- **Resumable** — completed steps are tracked under `~/.cache/ubuntu-setup/`; full timestamped log at `~/ubuntu-setup.log`.
- **Tested** — Docker harness and GitHub Actions matrix cover Ubuntu 22.04, 24.04, 25.04, and 26.04 in both smoke and idempotency stages.

## Requirements

- Ubuntu 22.04, 24.04, 25.04, or 26.04 (other Debian-derivatives may work but are not tested)
- `bash` (every script auto-re-execs under bash if invoked via `sh`)
- `sudo` privileges (you'll be prompted as needed)
- Network access for package downloads

## Quick Start

```bash
git clone https://github.com/ashtanko/ubuntu-post-install.git
cd ubuntu-post-install

cp .env.example .env      # optional but recommended
$EDITOR .env              # set GIT_NAME, GIT_EMAIL, etc.

bash setup.sh
```

The installer walks you through eight categories. For each one you can select:

| Input | Effect |
|---|---|
| `1 3 5` | Run scripts 1, 3, and 5 |
| `a` | Run **all** scripts in this category |
| `n` (or empty) | Skip the category |

Already-completed scripts are flagged with `✓` and skipped automatically. When everything finishes, a pass/fail/skipped summary is printed.

## Running individual scripts

Every script is independent and can be run on its own:

```bash
bash dev/node.sh
bash tools/zsh.sh
bash ai/ollama.sh
```

If you accidentally use `sh script.sh`, the script re-execs itself under `bash` so dash-isms (`[[ ]]`, `&>`, `$'…'`) keep working.

## What's installed

Browse [docs/SCRIPTS.md](docs/SCRIPTS.md) for the complete inventory. Categories at a glance:

| Folder | Purpose |
|---|---|
| [essentials/](essentials/) | OS bootstrap: swap, UFW firewall, auto-updates, locale/TZ, GNOME tweaks, system info |
| [system/](system/) | Foundations: apt upgrade + build tools, keyboard remap (keyd), GPG key, SSH key |
| [apps/](apps/) | GUI apps: Chrome, Guake, Warp, VS Code |
| [dev/](dev/) | Runtimes: Java, Docker, Flutter, Node (NVM), Python (pyenv), Rust, Go |
| [tools/](tools/) | Shell + CLI: Zsh + Oh My Zsh, Claude Code, bat/fzf/rg/eza/jq, Nerd Fonts, git config, pre-commit, backup, maintenance |
| [ide/](ide/) | Editors: Zed, Neovim, JetBrains Toolbox, VS Code extensions |
| [ai/](ai/) | LLM tooling: Ollama, llama.cpp, Gemini CLI, Antigravity, opencode, prompt-runner |
| [software/](software/) | Virtualization: VirtualBox, GNOME Boxes/virt-manager, VMware prereqs |
| [mobile/](mobile/) | Manual mobile-dev utilities (not wired into setup.sh) |

## Configuration

All scripts source `.env` automatically — every variable is optional. The most-used knobs:

| Variable | Purpose |
|---|---|
| `GIT_NAME`, `GIT_EMAIL` | Identity for git config, GPG key, SSH key (interactive prompt if unset) |
| `SWAP_SIZE_GB` | Swap file size in GB (default `4`) |
| `INSTALL_OH_MY_ZSH` | `yes`/`no` — toggle Oh My Zsh in `tools/zsh.sh` |
| `INSTALL_DOCKER_DESKTOP` | `yes`/`no` — toggle the Desktop GUI in `dev/docker.sh` |
| `VSCODE_EXTENSIONS` | Whitespace-separated extension IDs for `ide/vscode-extensions.sh` |
| `PROMPT_BACKEND` | `ollama` / `openai` / `anthropic` for `ai/prompt-runner.sh` |

See [docs/CONFIG.md](docs/CONFIG.md) for the full table and [.env.example](.env.example) for the canonical template.

## Logs and resume

- **Log file** — `~/ubuntu-setup.log` (override with `SETUP_LOG_FILE`); every run is appended with timestamps.
- **Marker files** — `~/.cache/ubuntu-setup/<script_path>.done` (e.g. `dev_node.sh.done`). Delete a marker to force a script to re-run on the next `setup.sh` invocation.

```bash
rm ~/.cache/ubuntu-setup/dev_node.sh.done    # re-run dev/node.sh next time
rm -rf ~/.cache/ubuntu-setup/                # reset everything
```

## Testing

The repo ships with a Docker-based test harness — no host pollution, deterministic across Ubuntu versions.

```bash
bash tests/run-in-docker.sh                          # default: Ubuntu 24.04, smoke
bash tests/run-in-docker.sh 22.04 idempotency        # idempotency stage on 22.04
bash tests/run-in-docker.sh 24.04 smoke dev/node.sh  # single script
bash tests/lint.sh                                   # shellcheck on every .sh
```

CI runs both [`lint.yml`](.github/workflows/lint.yml) (shellcheck + manifest coverage) and [`docker-tests.yml`](.github/workflows/docker-tests.yml) (matrix across all supported Ubuntu versions × smoke/idempotency) on every push and pull request.

Full testing guide: [docs/TESTING.md](docs/TESTING.md).

## Documentation

| Doc | What's in it |
|---|---|
| [docs/SETUP.md](docs/SETUP.md) | How `setup.sh` orchestrates runs: menu input, marker files, log layout, resume / reset |
| [docs/SCRIPTS.md](docs/SCRIPTS.md) | Full inventory of every script with one-line purpose |
| [docs/CONFIG.md](docs/CONFIG.md) | Every `.env` variable, its default, and which scripts read it |
| [docs/TESTING.md](docs/TESTING.md) | Docker test harness, manifest format, CI workflows |
| [docs/CONTRIBUTING.md](docs/CONTRIBUTING.md) | Adding a new script: shape, manifest row, local checks, CI gates |
| [docs/TROUBLESHOOTING.md](docs/TROUBLESHOOTING.md) | Common failures and recovery steps |
| [docs/SECURITY.md](docs/SECURITY.md) | Trade-offs the scripts make: UFW defaults, GPG passphrase, rc-file edits, telemetry |

## Conventions

Every script follows the same shape:

- `#!/bin/bash` + `set -euo pipefail` + bash re-exec shim
- `.env` auto-sourced from the repo root before any work
- Idempotency check (`command -v`, marker, file existence) — early-exit if already done
- Temp files cleaned via `trap 'rm -f "$TMP"' EXIT`
- Shell config additions written to **both** `~/.zshrc` and `~/.bashrc`, guarded by `grep -q`
- Emoji legend: 🚀 start · 📦 installing · ✅ success · ❌ error · ⚠️ warning · 💡 tip · 🔧 configuring · 🔍 detecting

## Contributing

See [docs/CONTRIBUTING.md](docs/CONTRIBUTING.md) for the full guide. TL;DR:

1. Follow the script conventions above.
2. Add a row for any new script to [tests/manifest.sh](tests/manifest.sh) — it's the single source of truth for compatibility, env vars, and verification commands.
3. Optional: add a multi-line verification under `tests/verify/<category>_<name>.sh`.
4. Run `bash tests/lint.sh` and `bash tests/check-manifest-coverage.sh` before opening a PR.

CI will reject PRs that add scripts without manifest entries.

## License

MIT — see [LICENSE](LICENSE).

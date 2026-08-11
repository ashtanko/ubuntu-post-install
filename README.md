# ubuntu-post-install

Automated shell scripts to provision a fresh Ubuntu installation with a developer's preferred toolchain — runtimes, editors, CLI tools, AI tooling, and OS hardening — through a single interactive installer.

[![Lint](https://github.com/ashtanko/ubuntu-post-install/actions/workflows/lint.yml/badge.svg)](https://github.com/ashtanko/ubuntu-post-install/actions/workflows/lint.yml)
[![Docker tests](https://github.com/ashtanko/ubuntu-post-install/actions/workflows/docker-tests.yml/badge.svg)](https://github.com/ashtanko/ubuntu-post-install/actions/workflows/docker-tests.yml)

## Highlights

- **Full-screen terminal installer** — a responsive ANSI interface with categorized selection, progress, retry, and a final result summary.
- **Classic fallback** — redirected output, unsupported terminals, and `--classic` keep the original Bash menu available.
- **Re-run tested** — runnable container-compatible scripts execute twice and must preserve configured state snapshots.
- **Configurable** — inherited environment variables override repo `.env`, which overrides `~/.env-ubuntu-post-install`.
- **Resumable** — completed steps are tracked under `~/.cache/ubuntu-setup/`; full timestamped log at `~/ubuntu-setup.log`.
- **Tested** — Docker smoke and idempotency jobs cover Ubuntu 22.04, 24.04, and 26.04 where scripts are container-compatible.

## Requirements

- Ubuntu 22.04, 24.04, or 26.04 (other Debian derivatives may work but are not tested)
- `bash` (every script auto-re-execs under bash if invoked via `sh`)
- `sudo` privileges (you'll be prompted as needed)
- Network access for package downloads
- `amd64` for Google Chrome and Warp; their scripts reject other architectures before changing apt state
- Go 1.25+ only when building the terminal UI from source; published releases include prebuilt binaries

## Quick install

Install the latest release without cloning the repo:

```bash
curl -fsSL https://github.com/ashtanko/ubuntu-post-install/releases/latest/download/install.sh | bash
ubuntu-post-install --version          # confirm install
ubuntu-post-install                    # launch the full-screen terminal installer
```

Pin a specific version:

```bash
VERSION=v1.0.0 bash <(curl -fsSL https://github.com/ashtanko/ubuntu-post-install/releases/download/v1.0.0/install.sh)
```

The installer writes scripts to `~/.local/share/ubuntu-post-install/<version>/` and symlinks `~/.local/bin/ubuntu-post-install` (override with `PREFIX=` and `BIN_DIR=`). Make sure `~/.local/bin` is on your `PATH`.

## Quick Start (from source)

```bash
git clone https://github.com/ashtanko/ubuntu-post-install.git
cd ubuntu-post-install

cp .env.example .env      # optional but recommended
$EDITOR .env              # set GIT_NAME, GIT_EMAIL, etc.

make tui-build             # optional when working from source; requires Go
bash setup.sh
```

The terminal UI supports nine categories. Use the arrow keys to navigate, Space
to select, `a` to toggle the current category, `Ctrl+A` to select everything, `x`
to clear the whole selection, and Enter to review and install. Installer output
and interactive prompts temporarily take over the terminal; the interface
resumes when each script exits. On the summary screen, `r` retries the failed
items and `l` opens the full log.

Use the classic menu when preferred or when diagnosing terminal compatibility:

```bash
ubuntu-post-install --classic
```

The classic installer walks through the same catalog. For each category you can select:

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
bash tools/fish.sh
bash tools/starship.sh
bash ai/ollama.sh
```

If you accidentally use `sh script.sh`, the script re-execs itself under `bash` so dash-isms (`[[ ]]`, `&>`, `$'…'`) keep working.

## Updating installed tools

Tools with an upstream-supported updater have matching wrappers under [`updates/`](updates/). Run one updater directly, or run the aggregate script to update every supported tool that is currently installed:

```bash
bash updates/update-claude.sh
bash updates/update-codex.sh
bash updates/update-all.sh
```

Each individual updater exits successfully with a skip message when its tool is absent. Package-manager-owned software continues to use the normal `apt`, Snap, or application auto-update path. [`updates/skipped.txt`](updates/skipped.txt) records why every selectable installer without a wrapper is intentionally omitted.

## What's installed

Browse [docs/SCRIPTS.md](docs/SCRIPTS.md) for the complete inventory. Categories at a glance:

| Folder | Purpose |
|---|---|
| [essentials/](essentials/) | OS bootstrap: swap, UFW firewall, fail2ban, Lynis audit, auto-updates, locale/TZ, GNOME tweaks, journal size cap, fstrim, motd-news, inotify/nofile limits, system info |
| [system/](system/) | Foundations: apt upgrade + build tools, hostname, user groups, NTP, DNS, sudo timeout, keyboard remap (keyd), GPG key, SSH key |
| [apps/](apps/) | GUI apps + CLIs: Chrome, Guake, Warp, VS Code, Postman, Bitwarden CLI, Flameshot |
| [dev/](dev/) | Runtimes + cloud: Java, Docker (rootful + rootless), Podman, Flutter, Node (NVM), Deno, Bun, Python (pyenv), Rust, Go, .NET, Ruby (rbenv), PHP, C/C++, AWS/GCP/Azure CLIs, Kubernetes, Terraform, databases |
| [tools/](tools/) | Shell + CLI: Zsh/Oh My Zsh, Fish/Fisher, Starship, bat/fzf/rg/eza/jq/yq, tmux config, Nerd Fonts, git config, pre-commit, gitleaks, backup + restic, maintenance, Wireshark, network tools, chezmoi, rclone, container tooling (lazydocker, ctop, dive, hadolint, Trivy), just, Atuin |
| [ide/](ide/) | Editors + IDEs: Zed, Neovim, JetBrains Toolbox, VS Code extensions, Android Studio, Cursor, DBeaver |
| [ai/](ai/) | LLM tooling: local inference, coding agents, provider-neutral CLIs, LiteLLM gateway, Fabric workflows, and MCP Inspector |
| [updates/](updates/) | Maintenance wrappers plus an audited skip ledger for installed tools; not part of the fresh-install menu |
| [software/](software/) | Virtualization: VirtualBox, GNOME Boxes/virt-manager, VMware prereqs |
| [vpn/](vpn/) | VPN clients: NordVPN, Tailscale |
| [mobile/](mobile/) | Manual mobile-dev utilities (not wired into setup.sh) |

## Configuration

Scripts load configuration through `lib/config.bash`; every variable is optional. Inherited environment variables have highest precedence, followed by repo `.env`, then `~/.env-ubuntu-post-install`. The most-used knobs:

| Variable | Purpose |
|---|---|
| `GIT_NAME`, `GIT_EMAIL` | Identity for git config, GPG key, SSH key (interactive prompt if unset) |
| `SWAP_SIZE_GB` | Swap file size in GB (default `4`) |
| `INSTALL_OH_MY_ZSH` | `yes`/`no` — toggle Oh My Zsh in `tools/zsh.sh` |
| `INSTALL_FISHER` | `yes`/`no` — toggle Fisher in `tools/fish.sh` |
| `SET_FISH_AS_DEFAULT` | `yes`/`no` — make Fish the login shell |
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

The repo ships with an isolated Docker harness. It compares deterministic package/file metadata, while network-backed installer availability can still vary upstream.

```bash
bash tests/run-in-docker.sh                          # default: Ubuntu 24.04, smoke
bash tests/run-in-docker.sh 22.04 idempotency        # idempotency stage on 22.04
bash tests/run-in-docker.sh 24.04 smoke dev/node.sh  # single script
bash tests/lint.sh                                   # shellcheck on every .sh/.bash file
```

Or via the [Makefile](Makefile) (`make help` for the full list):

```bash
make check                      # lint + manifest validation + local regressions
make smoke UBUNTU=22.04         # smoke stage on a specific Ubuntu version
make smoke SCRIPT=dev/node.sh   # scope to one script
make idempotency-all            # idempotency across every supported version
make release-dry-run            # full checks + build and verify release artifacts
make tag VERSION=1.0.0          # cut and push a release tag
```

[`lint.yml`](.github/workflows/lint.yml) runs the complete local check gate on every push and pull request. [`docker-tests.yml`](.github/workflows/docker-tests.yml) runs the supported-version smoke/idempotency matrix on pushes to `main`, pull requests, and manual dispatches.

Full testing guide: [docs/TESTING.md](docs/TESTING.md).

## Documentation

| Doc | What's in it |
|---|---|
| [docs/SETUP.md](docs/SETUP.md) | How `setup.sh` orchestrates runs: menu input, marker files, log layout, resume / reset |
| [docs/PUSH.md](docs/PUSH.md) | How to cut and publish a new release (tag conventions, workflow, verification) |
| [docs/SCRIPTS.md](docs/SCRIPTS.md) | Full inventory of every script with one-line purpose |
| [docs/CONFIG.md](docs/CONFIG.md) | Every configuration variable, its default, and which scripts read it |
| [docs/TESTING.md](docs/TESTING.md) | Docker test harness, manifest format, CI workflows |
| [docs/CONTRIBUTING.md](docs/CONTRIBUTING.md) | Adding a new script: shape, manifest row, local checks, CI gates |
| [docs/TROUBLESHOOTING.md](docs/TROUBLESHOOTING.md) | Common failures and recovery steps |
| [docs/SECURITY.md](docs/SECURITY.md) | Trade-offs the scripts make: UFW defaults, GPG passphrase, rc-file edits, telemetry |

## Conventions

Every script follows the same shape:

- `#!/bin/bash` + `set -euo pipefail` + bash re-exec shim
- configuration loaded through `lib/config.bash` without automatically exporting secrets
- Repeat-safe guards (`command -v`, marker, file existence) where the operation supports them
- Temp files cleaned via `trap 'rm -f "$TMP"' EXIT`
- Shell config additions written to **both** `~/.zshrc` and `~/.bashrc`, guarded by `grep -q`
- `apt-get update` before installing any repository package; downloads land in a file and are checksum-verified rather than piped into a shell
- Emoji legend: 🚀 start · 📦 installing · ✅ success · ❌ error · ⚠️ warning · 💡 tip · 🔧 configuring · 🔍 detecting

The mechanical parts of these conventions are enforced by [tests/script-contract-regression.sh](tests/script-contract-regression.sh), which checks every script — including the ones no Docker stage can execute.

## Contributing

See [docs/CONTRIBUTING.md](docs/CONTRIBUTING.md) for the full guide. TL;DR:

1. Follow the script conventions above.
2. For a selectable installer, add the user-facing label and category to [config/catalog.txt](config/catalog.txt). Maintenance utilities such as `updates/*.sh` stay out of the fresh-install catalog.
3. Map that installer in [updates/catalog.txt](updates/catalog.txt), or record its audited omission reason in [updates/skipped.txt](updates/skipped.txt).
4. Add a row to [tests/manifest.sh](tests/manifest.sh) for compatibility, env vars, and verification commands.
5. Optional: add a multi-line verification under `tests/verify/<category>_<name>.sh`.
6. Run `make check` before opening a PR.

CI will reject PRs that add scripts without manifest entries.

## License

MIT — see [LICENSE](LICENSE).

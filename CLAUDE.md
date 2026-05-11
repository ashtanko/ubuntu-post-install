# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Overview

Personal Ubuntu development environment setup toolkit — a collection of independent bash scripts organized by category, designed to provision a fresh Ubuntu system with the developer's preferred toolchain. Run `setup.sh` for an interactive menu-driven installer.

## Running Scripts

```bash
# Interactive master installer (recommended for fresh setup):
bash setup.sh

# Run any individual script directly:
bash system/base.sh
bash dev/node.sh
```

All scripts require `sudo` where needed and will prompt for credentials. Scripts are idempotent — safe to re-run; already-installed tools are detected and skipped. Every script also re-execs itself under `bash` if invoked via `sh`, so dash-isms (`[[ ]]`, `&>`) don't break.

## Folder Structure

| Folder | Purpose |
|---|---|
| `essentials/` | Core OS bootstrap: swap, firewall, auto-updates, locale/TZ, GNOME tweaks, system info |
| `system/` | OS foundations: apt upgrade, keyboard remapping, GPG key, SSH key |
| `apps/` | GUI applications: Chrome, Guake, Warp, VS Code |
| `dev/` | Development runtimes: Java, Docker, Flutter, Node, Python, Rust, Go |
| `tools/` | Shell, CLI, and dev helpers: Zsh, Claude Code, CLI tools, fonts, git config, pre-commit, backup, maintenance |
| `ide/` | Editors: Zed, Neovim, JetBrains Toolbox, VS Code extensions bulk install |
| `ai/` | LLM tooling: Ollama, llama.cpp, Gemini CLI, Antigravity, opencode, prompt-runner |
| `software/` | Virtualization: VirtualBox, GNOME Boxes/virt-manager, VMware prereqs |
| `vpn/` | VPN clients: NordVPN |
| `mobile/` | Mobile dev utilities (manual; not wired into setup.sh) |
| `setup.sh` | Interactive master installer with category menus and progress logging |

## Script Inventory

### essentials/
| Script | Purpose |
|---|---|
| `swap.sh` | Create swap file if none active (size from `$SWAP_SIZE_GB`, default 4G); persists in `/etc/fstab` |
| `firewall.sh` | UFW with safe defaults (deny in / allow out / limit OpenSSH); set `ENABLE_UFW=no` to skip |
| `auto-updates.sh` | unattended-upgrades + 20auto-upgrades for daily security patches; set `ENABLE_AUTO_UPDATES=no` to skip |
| `locale-timezone.sh` | Sets timezone (from `$TZ` or auto-detected via ipapi.co) and generates `$LOCALE` (default `en_US.UTF-8`) |
| `gnome-settings.sh` | Idempotent gsettings: night light, tap-to-click, fixed workspaces, hidden files, etc. Skips if not GNOME |
| `system-info.sh` | One-shot dump of CPU/RAM/GPU/disk/distro to `~/system-info-<ts>.log` |

### system/
| Script | Purpose |
|---|---|
| `base.sh` | apt upgrade + build-essential, git, curl, wget, GNOME tweaks |
| `keyboard.sh` | keyd daemon — Left Alt → Ctrl, Left Ctrl → Meta (macOS-style) |
| `gpg.sh` | GPG key generation, auto-extracts key ID, configures git signing |
| `ssh.sh` | ed25519 SSH key + installs ssh-agent autostart block in shell rc files |

### apps/
| Script | Purpose |
|---|---|
| `browsers.sh` | Google Chrome |
| `guake.sh` | Guake drop-down terminal |
| `postman.sh` | Postman API client — official tarball into `$POSTMAN_INSTALL_DIR` (default `~/.local/share/Postman`), with `~/.local/bin/postman` symlink and `.desktop` entry |
| `warp.sh` | Warp terminal |
| `vscode.sh` | VS Code via Microsoft apt repo |

### dev/
| Script | Purpose |
|---|---|
| `java.sh` | Default OpenJDK |
| `docker.sh` | Docker Engine + Docker Desktop + user group |
| `flutter.sh` | Flutter SDK (stable), Android deps, Linux desktop deps |
| `node.sh` | Node.js via NVM — installs latest LTS |
| `python.sh` | Python 3 + pyenv + pipx + poetry |
| `rust.sh` | Rust toolchain via rustup |
| `go.sh` | Latest Go SDK — version detection with fallback (VERSION endpoint → JSON) |

### tools/
| Script | Purpose |
|---|---|
| `zsh.sh` | Zsh + Oh My Zsh; set `INSTALL_OH_MY_ZSH=no` to skip OMZ |
| `claude.sh` | Claude Code CLI (installs Node via verified NodeSource repo if missing) |
| `cli-tools.sh` | bat, fzf, ripgrep, eza, jq, htop, tmux, tree, gh (GitHub CLI) |
| `fonts.sh` | JetBrains Mono, Fira Code, Hack — all Nerd Font variants |
| `git-config.sh` | Opinionated git defaults (rebase pull, autosetup, aliases, global gitignore, optional GPG signing) |
| `pre-commit-setup.sh` | pre-commit framework via pipx + git template hook + starter `.pre-commit-config.yaml` |
| `backup-home.sh` | Tar (optionally GPG-encrypted) backup of SSH/GPG/AWS/.config to `$BACKUP_DIR` |
| `system-maintenance.sh` | apt autoremove/clean, journal vacuum, docker/snap/flatpak prune, user-cache trim |

### ide/
| Script | Purpose |
|---|---|
| `zed.sh` | Zed editor (preview channel) via official installer |
| `vscode-extensions.sh` | Bulk-install extensions from `$VSCODE_EXTENSIONS` (whitespace-separated) |
| `jetbrains-toolbox.sh` | JetBrains Toolbox app + desktop entry; pick IDEs from the Toolbox UI |
| `nvim.sh` | Latest Neovim from official GitHub release tarball; writes starter `init.lua` if absent |

### ai/
| Script | Purpose |
|---|---|
| `ollama.sh` | Ollama via official installer; ensures systemd service is up |
| `llama-cpp.sh` | Build llama.cpp from source (CMake, Release); symlinks main binaries to `~/.local/bin` |
| `gemini.sh` | Google Gemini CLI (installs Node via verified NodeSource repo if missing) |
| `antigravity.sh` | Antigravity auto-updater via Google APT repo |
| `opencode.sh` | opencode CLI via official installer |
| `prompt-runner.sh` | Installs `prompt` command — runs text/.prompt files against ollama / openai / anthropic |

### software/
| Script | Purpose |
|---|---|
| `virtualbox.sh` | VirtualBox + extension pack |
| `boxes.sh` | GNOME Boxes + virt-manager |
| `vmware.sh` | Installs kernel build prereqs for VMware Workstation Pro (manual download required) |

### vpn/
| Script | Purpose |
|---|---|
| `nord.sh` | NordVPN official Linux app via `install.sh`; adds user to `nordvpn` group; prints reminder to run `nordvpn login` |

### mobile/
| Script | Purpose |
|---|---|
| `zip_flutter_plugin.sh` | Manual utility — archives a Flutter plugin directory excluding build artefacts |

## Conventions

- All scripts: `#!/bin/bash` + `set -euo pipefail` + bash-reexec shim (so `sh script.sh` still works)
- Idempotency: each script checks if the tool is already installed and exits early
- Temp files: cleaned via `trap 'rm -f "$TMP"' EXIT`
- Shell config additions (`PATH`, env vars): written to both `~/.zshrc` and `~/.bashrc` with a `grep -q` guard to prevent duplicates
- Emojis: 🚀 start · 📦 installing · ✅ success · ❌ error · ⚠️ warning · 💡 tip · 🔧 configuring · 🔍 detecting
- GPG repo keys: added via `gpg --dearmor` to `/etc/apt/keyrings/` and pinned with `signed-by=` in the apt source

## setup.sh Behaviour

- Displays a category menu; user selects items by number, `a` (all), or `n` (none)
- Recommended order (top-to-bottom in the menu): essentials → system → apps → dev → tools → ide → ai → software → vpn
- Logs all output with timestamps to `~/ubuntu-setup.log`
- Tracks completed steps via marker files in `~/.cache/ubuntu-setup/`; delete a marker to force re-run
- Shows a pass/fail/skipped summary at the end

## .env Configuration

Copy `.env.example` to `.env` and fill in your values. `.env` is gitignored. Every script sources it automatically at startup via:

```bash
[[ -f "$REPO_ROOT/.env" ]] && { set -a; source "$REPO_ROOT/.env"; set +a; }
```

| Variable | Used by | Default |
|---|---|---|
| `GIT_NAME` | system/base.sh (git config) | — prompts if not set |
| `GIT_EMAIL` | system/base.sh, gpg.sh, ssh.sh | — prompts if not set |
| `GIT_DEFAULT_BRANCH` | system/base.sh | `main` |
| `GIT_EDITOR` | system/base.sh | `nano` |
| `FLUTTER_DIR` | dev/flutter.sh | `$HOME/development` |
| `NVM_DIR` | dev/node.sh | `$HOME/.nvm` |
| `PYENV_ROOT` | dev/python.sh | `$HOME/.pyenv` |
| `GO_INSTALL_DIR` | dev/go.sh | `/usr/local/go` |
| `INSTALL_OH_MY_ZSH` | tools/zsh.sh | `yes` |
| `INSTALL_DOCKER_DESKTOP` | dev/docker.sh | `yes` |
| `SETUP_LOG_FILE` | setup.sh | `$HOME/ubuntu-setup.log` |
| `SWAP_SIZE_GB` | essentials/swap.sh | `4` |
| `ENABLE_UFW` | essentials/firewall.sh | `yes` |
| `ENABLE_AUTO_UPDATES` | essentials/auto-updates.sh | `yes` |
| `TZ` | essentials/locale-timezone.sh | auto-detect via ipapi.co |
| `LOCALE` | essentials/locale-timezone.sh | `en_US.UTF-8` |
| `LLAMA_CPP_DIR` | ai/llama-cpp.sh | `$HOME/.local/src/llama.cpp` |
| `PROMPT_BACKEND` | ai/prompt-runner.sh (`prompt` CLI) | `ollama` |
| `PROMPT_MODEL` | ai/prompt-runner.sh | per-backend default |
| `OLLAMA_HOST` | ai/prompt-runner.sh | `http://localhost:11434` |
| `OPENAI_API_KEY` | ai/prompt-runner.sh | — required for `-b openai` |
| `ANTHROPIC_API_KEY` | ai/prompt-runner.sh | — required for `-b anthropic` |
| `VSCODE_EXTENSIONS` | ide/vscode-extensions.sh | — empty = no-op |
| `JETBRAINS_TOOLBOX_DIR` | ide/jetbrains-toolbox.sh | `$HOME/.local/share/JetBrains/Toolbox` |
| `NVIM_INSTALL_DIR` | ide/nvim.sh | `$HOME/.local/share/nvim-stable` |
| `POSTMAN_INSTALL_DIR` | apps/postman.sh | `$HOME/.local/share/Postman` |
| `ENABLE_GIT_COMMIT_SIGNING` | tools/git-config.sh | `no` |
| `BACKUP_DIR` | tools/backup-home.sh | `$HOME/backups` |
| `BACKUP_ENCRYPT` | tools/backup-home.sh | `no` |
| `BACKUP_GPG_RECIPIENT` | tools/backup-home.sh | `$GIT_EMAIL` |

When `GIT_NAME` and `GIT_EMAIL` are set, `system/gpg.sh` generates the key non-interactively (no passphrase, RSA 4096). Without them it falls back to the interactive `gpg --full-generate-key` wizard.

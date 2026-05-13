# Script Inventory

Every script in this repo is independent — `bash <path>` runs it standalone, or pick it from the [`setup.sh`](../setup.sh) menu. All scripts are idempotent, source `.env` automatically, and re-exec under `bash` if invoked via `sh`.

## essentials/

OS bootstrap — run these first on a fresh install.

| Script | Purpose |
|---|---|
| [swap.sh](../essentials/swap.sh) | Create swap file if none active (size from `$SWAP_SIZE_GB`, default 4G); persists in `/etc/fstab` |
| [firewall.sh](../essentials/firewall.sh) | UFW with safe defaults (deny in / allow out / limit OpenSSH); set `ENABLE_UFW=no` to skip |
| [auto-updates.sh](../essentials/auto-updates.sh) | unattended-upgrades + 20auto-upgrades for daily security patches; set `ENABLE_AUTO_UPDATES=no` to skip |
| [locale-timezone.sh](../essentials/locale-timezone.sh) | Sets timezone (from `$TZ` or auto-detected via ipapi.co) and generates `$LOCALE` (default `en_US.UTF-8`) |
| [gnome-settings.sh](../essentials/gnome-settings.sh) | Idempotent gsettings: night light, tap-to-click, fixed workspaces, hidden files, etc. Skips if not GNOME |
| [system-info.sh](../essentials/system-info.sh) | One-shot dump of CPU/RAM/GPU/disk/distro to `~/system-info-<ts>.log` |

## system/

Foundations — git, build tools, keys.

| Script | Purpose |
|---|---|
| [base.sh](../system/base.sh) | apt upgrade + build-essential, git, curl, wget, GNOME tweaks |
| [keyboard.sh](../system/keyboard.sh) | keyd daemon — Left Alt → Ctrl, Left Ctrl → Meta (macOS-style) |
| [gpg.sh](../system/gpg.sh) | GPG key generation, auto-extracts key ID, configures git signing |
| [ssh.sh](../system/ssh.sh) | ed25519 SSH key + installs ssh-agent autostart block in shell rc files |

## apps/

GUI applications.

| Script | Purpose |
|---|---|
| [browsers.sh](../apps/browsers.sh) | Google Chrome |
| [guake.sh](../apps/guake.sh) | Guake drop-down terminal |
| [warp.sh](../apps/warp.sh) | Warp terminal |
| [vscode.sh](../apps/vscode.sh) | VS Code via Microsoft apt repo |

## dev/

Language runtimes and SDKs.

| Script | Purpose |
|---|---|
| [java.sh](../dev/java.sh) | OpenJDK 8/11/17/21/25 — interactive menu or `JAVA_VERSION` env (installs side-by-side; switch default via `update-alternatives`) |
| [docker.sh](../dev/docker.sh) | Docker Engine + Docker Desktop + user group |
| [flutter.sh](../dev/flutter.sh) | Flutter SDK (stable), Android deps, Linux desktop deps |
| [node.sh](../dev/node.sh) | Node.js via NVM — installs latest LTS |
| [python.sh](../dev/python.sh) | Python 3 + pyenv + pipx + poetry |
| [rust.sh](../dev/rust.sh) | Rust toolchain via rustup |
| [go.sh](../dev/go.sh) | Latest Go SDK — version detection with fallback (VERSION endpoint → JSON) |
| [databases.sh](../dev/databases.sh) | PostgreSQL, MySQL, Redis, SQLite CLI clients + pgcli/mycli/litecli (interactive shells via pipx) |
| [kubernetes.sh](../dev/kubernetes.sh) | kubectl + helm + k9s + kind + kustomize |
| [aws-cli.sh](../dev/aws-cli.sh) | AWS CLI v2 (official zip) + Session Manager plugin |
| [terraform.sh](../dev/terraform.sh) | Terraform (HashiCorp apt repo) + tflint + tfsec |

## tools/

Shell, CLI, and dev helpers.

| Script | Purpose |
|---|---|
| [zsh.sh](../tools/zsh.sh) | Zsh + Oh My Zsh; set `INSTALL_OH_MY_ZSH=no` to skip OMZ |
| [claude.sh](../tools/claude.sh) | Claude Code CLI (installs Node via verified NodeSource repo if missing) |
| [cli-tools.sh](../tools/cli-tools.sh) | bat, fzf, ripgrep, eza, jq, htop, tmux, tree, gh (GitHub CLI) |
| [modern-cli.sh](../tools/modern-cli.sh) | lazygit, delta, zoxide, btop, direnv, fd, dust, hyperfine, tldr (tealdeer) |
| [fonts.sh](../tools/fonts.sh) | JetBrains Mono, Fira Code, Hack — all Nerd Font variants |
| [git-config.sh](../tools/git-config.sh) | Opinionated git defaults (rebase pull, autosetup, aliases, global gitignore, optional GPG signing) |
| [pre-commit-setup.sh](../tools/pre-commit-setup.sh) | pre-commit framework via pipx + git template hook + starter `.pre-commit-config.yaml` |
| [backup-home.sh](../tools/backup-home.sh) | Tar (optionally GPG-encrypted) backup of SSH/GPG/AWS/.config to `$BACKUP_DIR` |
| [system-maintenance.sh](../tools/system-maintenance.sh) | apt autoremove/clean, journal vacuum, docker/snap/flatpak prune, user-cache trim |

## ide/

Editors and IDEs.

| Script | Purpose |
|---|---|
| [zed.sh](../ide/zed.sh) | Zed editor (preview channel) via official installer |
| [vscode-extensions.sh](../ide/vscode-extensions.sh) | Bulk-install extensions from `$VSCODE_EXTENSIONS` (whitespace-separated) |
| [jetbrains-toolbox.sh](../ide/jetbrains-toolbox.sh) | JetBrains Toolbox app + desktop entry; pick IDEs from the Toolbox UI |
| [nvim.sh](../ide/nvim.sh) | Latest Neovim from official GitHub release tarball; writes starter `init.lua` if absent |

## ai/

LLM tooling and CLIs.

| Script | Purpose |
|---|---|
| [ollama.sh](../ai/ollama.sh) | Ollama via official installer; ensures systemd service is up |
| [llama-cpp.sh](../ai/llama-cpp.sh) | Build llama.cpp from source (CMake, Release); symlinks main binaries to `~/.local/bin` |
| [gemini.sh](../ai/gemini.sh) | Google Gemini CLI (installs Node via verified NodeSource repo if missing) |
| [antigravity.sh](../ai/antigravity.sh) | Antigravity auto-updater via Google APT repo |
| [opencode.sh](../ai/opencode.sh) | opencode CLI via official installer |
| [prompt-runner.sh](../ai/prompt-runner.sh) | Installs `prompt` command — runs text/.prompt files against ollama / openai / anthropic |

## software/

Virtualization stacks.

| Script | Purpose |
|---|---|
| [virtualbox.sh](../software/virtualbox.sh) | VirtualBox + extension pack |
| [boxes.sh](../software/boxes.sh) | GNOME Boxes + virt-manager |
| [vmware.sh](../software/vmware.sh) | Installs kernel build prereqs for VMware Workstation Pro (manual download required) |

## mobile/

Manual utilities — **not** wired into `setup.sh`.

| Script | Purpose |
|---|---|
| [zip_flutter_plugin.sh](../mobile/zip_flutter_plugin.sh) | Archives a Flutter plugin directory excluding build artefacts |

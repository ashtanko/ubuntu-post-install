# Script Inventory

Every installer script can run standalone with `bash <path>`, or from the [`setup.sh`](../setup.sh) menu when registered there. Scripts load shared configuration, include re-run guards appropriate to their installer, and re-exec under `bash` if invoked via `sh`.

## essentials/

OS bootstrap — run these first on a fresh install.

| Script | Purpose |
|---|---|
| [swap.sh](../essentials/swap.sh) | Create swap file if none active (size from `$SWAP_SIZE_GB`, default 4G); persists in `/etc/fstab` |
| [firewall.sh](../essentials/firewall.sh) | UFW with safe defaults (deny in / allow out / limit OpenSSH); set `ENABLE_UFW=no` to skip |
| [auto-updates.sh](../essentials/auto-updates.sh) | unattended-upgrades + 20auto-upgrades for daily security patches; set `ENABLE_AUTO_UPDATES=no` to skip |
| [locale-timezone.sh](../essentials/locale-timezone.sh) | Sets timezone (from `$TZ` or auto-detected via ipapi.co) and generates `$LOCALE` (default `en_US.UTF-8`) |
| [gnome-settings.sh](../essentials/gnome-settings.sh) | Idempotent gsettings: night light, tap-to-click, fixed workspaces, hidden files, etc. Skips if not GNOME |
| [journald.sh](../essentials/journald.sh) | Caps the systemd journal to `$JOURNAL_MAX_USE` (default `200M`) via a journald.conf.d drop-in |
| [fstrim.sh](../essentials/fstrim.sh) | Enables `fstrim.timer` for periodic SSD/NVMe TRIM; skips on rotational-only disks |
| [motd-news.sh](../essentials/motd-news.sh) | Disables Ubuntu's `motd-news` ESM/livepatch login-banner ads (config file + systemd timer) |
| [sysctl-limits.sh](../essentials/sysctl-limits.sh) | Raises inotify watch/instance limits and the open-file (`nofile`) limit for IDEs, docker, and bundlers |
| [system-info.sh](../essentials/system-info.sh) | One-shot dump of CPU/RAM/GPU/disk/distro to `~/system-info-<ts>.log` |

## system/

Foundations — git, build tools, keys.

| Script | Purpose |
|---|---|
| [base.sh](../system/base.sh) | apt upgrade + build-essential, git, curl, wget, GNOME tweaks |
| [hostname.sh](../system/hostname.sh) | Sets hostname (from `$NEW_HOSTNAME` or prompt) and syncs the 127.0.1.1 line in `/etc/hosts` |
| [user-groups.sh](../system/user-groups.sh) | Adds `$USER` to common dev groups (`$EXTRA_USER_GROUPS`, default docker/dialout/plugdev/wireshark); skips groups that don't exist yet |
| [ntp.sh](../system/ntp.sh) | Ensures the clock is time-synced — `timedatectl set-ntp` on systemd, chrony fallback otherwise |
| [hosts-dns.sh](../system/hosts-dns.sh) | Configures systemd-resolved DNS/FallbackDNS via drop-in (`$DNS_SERVERS`, `$DNS_FALLBACK_SERVERS`); no-ops if systemd-resolved isn't in use |
| [sudoers.sh](../system/sudoers.sh) | Opt-in only (`$SUDO_TIMESTAMP_TIMEOUT_MINUTES`): extends the sudo timestamp timeout via a `visudo -cf`-validated drop-in. Never configures passwordless sudo |
| [keyboard.sh](../system/keyboard.sh) | keyd daemon — Left Alt → Ctrl, Left Ctrl → Meta (macOS-style) |
| [gpg.sh](../system/gpg.sh) | GPG key generation, auto-extracts key ID, configures git signing |
| [ssh.sh](../system/ssh.sh) | ed25519 SSH key + installs ssh-agent autostart block in shell rc files |

## apps/

GUI applications.

| Script | Purpose |
|---|---|
| [browsers.sh](../apps/browsers.sh) | Google Chrome (amd64 only; rejected before apt changes on other architectures) |
| [guake.sh](../apps/guake.sh) | Guake drop-down terminal |
| [warp.sh](../apps/warp.sh) | Warp terminal (amd64 repository only; rejected before apt changes otherwise) |
| [vscode.sh](../apps/vscode.sh) | VS Code via Microsoft apt repo |

## dev/

Language runtimes and SDKs.

| Script | Purpose |
|---|---|
| [java.sh](../dev/java.sh) | OpenJDK 8/11/17/21/25 — interactive menu or `JAVA_VERSION` env (installs side-by-side; switch default via `update-alternatives`) |
| [docker.sh](../dev/docker.sh) | Docker Engine + Docker Desktop + user group |
| [flutter.sh](../dev/flutter.sh) | Flutter SDK (stable) + Linux desktop dependencies; Android SDK setup remains separate |
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
| [fish.sh](../tools/fish.sh) | Fish shell + Fisher plugin manager; optionally changes the login shell |
| [starship.sh](../tools/starship.sh) | Starship cross-shell prompt, initialized for installed Bash, Zsh, and Fish shells |
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
| [ollama-models.sh](../ai/ollama-models.sh) | Pulls the whitespace-separated `$OLLAMA_MODELS` list; requires a running Ollama service and has no default downloads |
| [llama-cpp.sh](../ai/llama-cpp.sh) | Build llama.cpp from source (CMake, Release); symlinks main binaries to `~/.local/bin` |
| [claude.sh](../ai/claude.sh) | Claude Code CLI from Anthropic's signed Ubuntu APT repository (`$CLAUDE_CHANNEL`: stable/latest) |
| [codex.sh](../ai/codex.sh) | OpenAI Codex CLI via the official standalone installer; `$CODEX_RELEASE` can pin a release |
| [gemini.sh](../ai/gemini.sh) | Google Gemini CLI (installs Node via verified NodeSource repo if missing) |
| [github-copilot.sh](../ai/github-copilot.sh) | GitHub Copilot CLI via the official user-local installer; `$COPILOT_VERSION` can pin a release |
| [huggingface-cli.sh](../ai/huggingface-cli.sh) | Standalone `hf` CLI for Hub authentication, model downloads, uploads, and cache management; skips the installer's optional agent skill |
| [aider.sh](../ai/aider.sh) | Aider coding CLI via its official isolated installer |
| [goose.sh](../ai/goose.sh) | Provider-neutral goose agent CLI; installs without launching its provider configuration wizard |
| [qwen-code.sh](../ai/qwen-code.sh) | Qwen Code terminal agent via the official standalone installer |
| [cursor-agent.sh](../ai/cursor-agent.sh) | Cursor Agent CLI via Cursor's official user-local installer |
| [mistral-vibe.sh](../ai/mistral-vibe.sh) | Mistral Vibe coding agent, including its ACP command, via the official installer |
| [cline.sh](../ai/cline.sh) | Cline terminal agent via npm; `$CLINE_VERSION` can pin a release |
| [fabric.sh](../ai/fabric.sh) | Fabric CLI for reusable prompt patterns and content workflows |
| [llm-cli.sh](../ai/llm-cli.sh) | Provider-neutral `llm` command installed in an isolated pipx environment; `$LLM_VERSION` can pin a release |
| [litellm.sh](../ai/litellm.sh) | LiteLLM OpenAI-compatible proxy CLI in an isolated pipx environment; latest installs align FastAPI/Starlette with LiteLLM's current proxy constraints, while `$LITELLM_VERSION` can pin a release |
| [mcp-inspector.sh](../ai/mcp-inspector.sh) | MCP Inspector web, TUI, and CLI debugger via npm; `$MCP_INSPECTOR_VERSION` can pin a release |
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

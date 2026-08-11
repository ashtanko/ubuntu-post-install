# Configuration Reference

Scripts load configuration through the shared helper before doing any work:

```bash
CONFIG_HELPER="$REPO_ROOT/lib/config.bash"
[[ -r "$CONFIG_HELPER" ]] || { echo "missing config helper: $CONFIG_HELPER" >&2; exit 1; }
source "$CONFIG_HELPER"
load_config "$REPO_ROOT"
```

For a source checkout, `.env` is gitignored and is a convenient repo-local config. Release installs advertise the stable user config path `~/.env-ubuntu-post-install` (override it with `UBUNTU_POST_INSTALL_CONFIG`). Copy [.env.example](../.env.example) to either location and edit. **No value is required** — scripts fall back to interactive prompts or sensible defaults.

## Variables

| Variable | Used by | Default | Notes |
|---|---|---|---|
| `GIT_NAME` | [system/base.sh](../system/base.sh) (git config) | — | Prompts if unset; also feeds GPG key |
| `GIT_EMAIL` | [system/base.sh](../system/base.sh), [system/gpg.sh](../system/gpg.sh), [system/ssh.sh](../system/ssh.sh) | — | Prompts if unset |
| `GIT_DEFAULT_BRANCH` | [system/base.sh](../system/base.sh) | `main` | `main` \| `master` |
| `GIT_EDITOR` | [system/base.sh](../system/base.sh) | `nano` | `nano` \| `vim` \| `code` \| `nvim` |
| `FLUTTER_DIR` | [dev/flutter.sh](../dev/flutter.sh), [updates/update-flutter.sh](../updates/update-flutter.sh) | `$HOME/development` | Where the Flutter SDK is cloned |
| `NVM_DIR` | [dev/node.sh](../dev/node.sh), [updates/update-node.sh](../updates/update-node.sh) | `$HOME/.nvm` | NVM installation directory |
| `PYENV_ROOT` | [dev/python.sh](../dev/python.sh), [updates/update-pyenv.sh](../updates/update-pyenv.sh) | `$HOME/.pyenv` | pyenv installation directory |
| `GO_INSTALL_DIR` | [dev/go.sh](../dev/go.sh), [updates/update-go.sh](../updates/update-go.sh) | `/usr/local/go` | Go SDK extraction target (needs sudo) |
| `GO_VERSION` | [dev/go.sh](../dev/go.sh), [updates/update-go.sh](../updates/update-go.sh) | latest stable | Pins a version (e.g. `go1.23.4`); the updater leaves pinned installs unchanged |
| `GO_ARCHIVE_URL` / `GO_ARCHIVE_SHA256` | [dev/go.sh](../dev/go.sh), [updates/update-go.sh](../updates/update-go.sh) | official release | Custom archives require an explicit SHA-256 checksum and disable automatic updates |
| `JAVA_VERSION` | [dev/java.sh](../dev/java.sh) | interactive prompt (fallback `21`) | OpenJDK major: `8` \| `11` \| `17` \| `21` \| `25` |
| `DOTNET_VERSION` | [dev/dotnet.sh](../dev/dotnet.sh) | `8.0` | .NET SDK major.minor to install |
| `RBENV_ROOT` | [dev/ruby.sh](../dev/ruby.sh), [updates/update-rbenv.sh](../updates/update-rbenv.sh) | `$HOME/.rbenv` | rbenv installation directory |
| `RUBY_VERSION` | [dev/ruby.sh](../dev/ruby.sh) | latest stable | Pins a version; resolved from `rbenv install -l` when empty |
| `PHP_VERSION` | [dev/php.sh](../dev/php.sh) | `8.3` | PHP major.minor installed from the `ondrej/php` PPA |
| `DENO_INSTALL` | [dev/deno.sh](../dev/deno.sh), [updates/update-deno.sh](../updates/update-deno.sh) | `$HOME/.deno` | Deno installation directory |
| `BUN_INSTALL` | [dev/bun.sh](../dev/bun.sh), [updates/update-bun.sh](../updates/update-bun.sh) | `$HOME/.bun` | Bun installation directory |
| `INSTALL_OH_MY_ZSH` | [tools/zsh.sh](../tools/zsh.sh) | `yes` | Set `no` to install plain Zsh only |
| `INSTALL_FISHER` | [tools/fish.sh](../tools/fish.sh) | `yes` | Set `no` to install plain Fish only |
| `SET_FISH_AS_DEFAULT` | [tools/fish.sh](../tools/fish.sh) | `yes` | Set `no` to leave the current login shell unchanged |
| `INSTALL_DOCKER_DESKTOP` | [dev/docker.sh](../dev/docker.sh) | `yes` | Set `no` to skip the Docker Desktop GUI |
| `DOCKER_ROOTLESS_ENABLE_LINGER` | [dev/docker-rootless.sh](../dev/docker-rootless.sh) | `yes` | Set `no` and the rootless daemon stops when you log out |
| `DOCKER_PRUNE_IMAGES` | [tools/docker-maintenance.sh](../tools/docker-maintenance.sh) | `dangling` | `all` also removes tagged images no container references |
| `DOCKER_PRUNE_VOLUMES` | [tools/docker-maintenance.sh](../tools/docker-maintenance.sh) | `no` | Opt-in: `yes` deletes unused volumes, which may hold real data |
| `DOCKER_PRUNE_UNTIL` | [tools/docker-maintenance.sh](../tools/docker-maintenance.sh) | `168h` | Age cutoff for containers, networks, images, and build cache |
| `SETUP_LOG_FILE` | [setup.sh](../setup.sh) | `$HOME/ubuntu-setup.log` | Where the master installer appends timestamped output |
| `SWAP_SIZE_GB` | [essentials/swap.sh](../essentials/swap.sh) | `4` | Skipped if any swap is already active |
| `SWAP_FILE` / `FSTAB_FILE` | [essentials/swap.sh](../essentials/swap.sh) | `/swapfile` / `/etc/fstab` | Overrideable paths also support isolated regression testing |
| `ENABLE_UFW` | [essentials/firewall.sh](../essentials/firewall.sh) | `yes` | Set `no` to skip firewall configuration |
| `ENABLE_AUTO_UPDATES` | [essentials/auto-updates.sh](../essentials/auto-updates.sh) | `yes` | Set `no` to skip unattended-upgrades |
| `ENABLE_FAIL2BAN` | [essentials/fail2ban.sh](../essentials/fail2ban.sh) | `yes` | Set `no` to skip SSH brute-force protection |
| `FAIL2BAN_BANTIME` / `FAIL2BAN_FINDTIME` / `FAIL2BAN_MAXRETRY` | [essentials/fail2ban.sh](../essentials/fail2ban.sh) | `1h` / `10m` / `5` | sshd jail thresholds; bantime/findtime use systemd-style durations |
| `TZ` | [essentials/locale-timezone.sh](../essentials/locale-timezone.sh) | auto-detect | Falls back to ipapi.co when empty |
| `LOCALE` | [essentials/locale-timezone.sh](../essentials/locale-timezone.sh) | `en_US.UTF-8` | Generated and set as system default |
| `JOURNAL_MAX_USE` | [essentials/journald.sh](../essentials/journald.sh) | `200M` | systemd disk-size syntax: `200M`, `1G`, `10%` |
| `INOTIFY_MAX_WATCHES` | [essentials/sysctl-limits.sh](../essentials/sysctl-limits.sh) | `524288` | `fs.inotify.max_user_watches` |
| `INOTIFY_MAX_INSTANCES` | [essentials/sysctl-limits.sh](../essentials/sysctl-limits.sh) | `1024` | `fs.inotify.max_user_instances` |
| `NOFILE_LIMIT` | [essentials/sysctl-limits.sh](../essentials/sysctl-limits.sh) | `1048576` | Soft/hard `nofile` ulimit via pam_limits; needs a new login session |
| `NEW_HOSTNAME` | [system/hostname.sh](../system/hostname.sh) | — | Prompts if unset and interactive; skipped otherwise |
| `EXTRA_USER_GROUPS` | [system/user-groups.sh](../system/user-groups.sh) | `docker dialout plugdev wireshark` | Space-separated; missing groups are skipped, not created |
| `DNS_SERVERS` | [system/hosts-dns.sh](../system/hosts-dns.sh) | `1.1.1.1 9.9.9.9` | Space-separated resolvers written to systemd-resolved `DNS=` |
| `DNS_FALLBACK_SERVERS` | [system/hosts-dns.sh](../system/hosts-dns.sh) | `1.0.0.1 149.112.112.112` | Written to systemd-resolved `FallbackDNS=` |
| `SUDO_TIMESTAMP_TIMEOUT_MINUTES` | [system/sudoers.sh](../system/sudoers.sh) | — | Opt-in only: unset = script skips. Minutes; `-1` = never expire |
| `VSCODE_EXTENSIONS` | [ide/vscode-extensions.sh](../ide/vscode-extensions.sh), [updates/update-vscode-extensions.sh](../updates/update-vscode-extensions.sh) | empty | Whitespace-separated extension IDs; the updater refreshes all installed extensions |
| `JETBRAINS_TOOLBOX_DIR` | [ide/jetbrains-toolbox.sh](../ide/jetbrains-toolbox.sh) | `$HOME/.local/share/JetBrains/Toolbox` | Toolbox install dir |
| `NVIM_INSTALL_DIR` | [ide/nvim.sh](../ide/nvim.sh), [updates/update-nvim.sh](../updates/update-nvim.sh) | `$HOME/.local/share/nvim-stable` | Where the Neovim tarball is extracted |
| `NVIM_VERSION` | [ide/nvim.sh](../ide/nvim.sh), [updates/update-nvim.sh](../updates/update-nvim.sh) | latest release | Pins a release tag (e.g. `v0.11.4`); the updater leaves pinned installs unchanged |
| `NVIM_ARCHIVE_URL` / `NVIM_ARCHIVE_SHA256` | [ide/nvim.sh](../ide/nvim.sh), [updates/update-nvim.sh](../updates/update-nvim.sh) | official release | Custom URLs require a SHA-256 digest and disable automatic updates; a digest alone can authorize the matching official latest asset |
| `CURSOR_INSTALL_DIR` | [ide/cursor.sh](../ide/cursor.sh) | `$HOME/.local/share/Cursor` | Where the Cursor AppImage is placed |
| `POSTMAN_INSTALL_DIR` | [apps/postman.sh](../apps/postman.sh) | `$HOME/.local/share/Postman` | Where Postman is extracted; symlinked into `~/.local/bin` |
| `GPG_KEY_ID` | [system/gpg.sh](../system/gpg.sh) | unique `GIT_EMAIL` match | Select an existing secret key explicitly when email lookup is ambiguous |
| `ENABLE_GIT_COMMIT_SIGNING` | [tools/git-config.sh](../tools/git-config.sh) | `no` | Flip to `yes` after running [system/gpg.sh](../system/gpg.sh) |
| `TMUX_PLUGIN_DIR` | [tools/tmux-config.sh](../tools/tmux-config.sh), [updates/update-tpm.sh](../updates/update-tpm.sh) | `$HOME/.tmux/plugins/tpm` | Where TPM is cloned; the updater requires a clean checkout |
| `BACKUP_DIR` | [tools/backup-home.sh](../tools/backup-home.sh) | `$HOME/backups` | Backup tarball destination |
| `BACKUP_ENCRYPT` | [tools/backup-home.sh](../tools/backup-home.sh) | `no` | `yes` = GPG-encrypt the tarball |
| `BACKUP_GPG_RECIPIENT` | [tools/backup-home.sh](../tools/backup-home.sh) | `$GIT_EMAIL` | GPG recipient for encrypted backups |
| `DOTFILES_REPO` | [tools/dotfiles.sh](../tools/dotfiles.sh) | — | Optional repo URL for `chezmoi init`; the script never runs `chezmoi apply` |
| `TAILSCALE_AUTHKEY` | [vpn/tailscale.sh](../vpn/tailscale.sh) | — | Non-interactive `tailscale up`; empty = manual browser login |
| `LLAMA_CPP_DIR` | [ai/llama-cpp.sh](../ai/llama-cpp.sh), [updates/update-llama-cpp.sh](../updates/update-llama-cpp.sh) | `$HOME/.local/src/llama.cpp` | Where llama.cpp is cloned and built; the updater requires a clean checkout and existing CMake build |
| `OLLAMA_MODELS` | [ai/ollama-models.sh](../ai/ollama-models.sh) | — | Required whitespace-separated model references; downloads only when the script is explicitly run |
| `CLAUDE_CHANNEL` | [ai/claude.sh](../ai/claude.sh) | `stable` | Anthropic APT channel: `stable` or `latest` |
| `CODEX_RELEASE` | [ai/codex.sh](../ai/codex.sh), [updates/update-codex.sh](../updates/update-codex.sh) | `latest` | Pins the installer; the updater runs native `codex update` only when this remains `latest` |
| `COPILOT_VERSION` | [ai/github-copilot.sh](../ai/github-copilot.sh), [updates/update-github-copilot.sh](../updates/update-github-copilot.sh) | `latest` | Pins the installer; the updater skips pinned installations |
| `CLINE_VERSION` | [ai/cline.sh](../ai/cline.sh), [updates/update-cline.sh](../updates/update-cline.sh) | `latest` | Pins the installer; the updater skips pinned installations |
| `MCP_INSPECTOR_VERSION` | [ai/mcp-inspector.sh](../ai/mcp-inspector.sh), [updates/update-mcp-inspector.sh](../updates/update-mcp-inspector.sh) | `latest` | Pins the npm release; the updater leaves pinned installs unchanged |
| `LLM_VERSION` | [ai/llm-cli.sh](../ai/llm-cli.sh), [updates/update-pipx-tools.sh](../updates/update-pipx-tools.sh) | `latest` | Pins the `llm` PyPI release; the updater leaves pinned installs unchanged |
| `LITELLM_VERSION` | [ai/litellm.sh](../ai/litellm.sh), [updates/update-pipx-tools.sh](../updates/update-pipx-tools.sh) | `latest` | Pins the LiteLLM PyPI release; the updater leaves pinned installs unchanged |
| `OPENCODE_INSTALL_DIR` | [ai/opencode.sh](../ai/opencode.sh), [updates/update-opencode.sh](../updates/update-opencode.sh) | `$HOME/.opencode` | opencode installation directory |
| `PROMPT_BACKEND` | [ai/prompt-runner.sh](../ai/prompt-runner.sh) | `ollama` | `ollama` \| `openai` \| `anthropic` |
| `PROMPT_MODEL` | [ai/prompt-runner.sh](../ai/prompt-runner.sh) | per-backend default | Override the model the `prompt` CLI uses |
| `OLLAMA_HOST` | [ai/prompt-runner.sh](../ai/prompt-runner.sh), [ai/ollama-models.sh](../ai/ollama-models.sh) | `http://localhost:11434` | Remote Ollama endpoint if not localhost |
| `OPENAI_API_KEY` | [ai/prompt-runner.sh](../ai/prompt-runner.sh) | — | Required for `-b openai` |
| `ANTHROPIC_API_KEY` | [ai/prompt-runner.sh](../ai/prompt-runner.sh) | — | Required for `-b anthropic` |

## Behaviour notes

- **Identity propagation** — when `GIT_NAME` and `GIT_EMAIL` are set, [system/gpg.sh](../system/gpg.sh) generates the key non-interactively (RSA 4096, no passphrase). Without them it falls back to the interactive `gpg --full-generate-key` wizard.
- **Order of precedence** — inherited environment variables take precedence over repo `.env`, which takes precedence over `~/.env-ubuntu-post-install`. Inline overrides work: `GIT_EDITOR=vim bash system/base.sh`.
- **Export isolation** — values read only from config files remain shell variables and are not automatically inherited by child processes. Variables that were already exported remain exported.
- **Booleans** — feature flags use string `yes` / `no`, not `true` / `false` or numeric values.
- **Paths with `$HOME`** — quote them; config files are sourced as Bash, so normal parameter expansion applies.

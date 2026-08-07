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
| `FLUTTER_DIR` | [dev/flutter.sh](../dev/flutter.sh) | `$HOME/development` | Where the Flutter SDK is cloned |
| `NVM_DIR` | [dev/node.sh](../dev/node.sh) | `$HOME/.nvm` | NVM installation directory |
| `PYENV_ROOT` | [dev/python.sh](../dev/python.sh) | `$HOME/.pyenv` | pyenv installation directory |
| `GO_INSTALL_DIR` | [dev/go.sh](../dev/go.sh) | `/usr/local/go` | Go SDK extraction target (needs sudo) |
| `GO_ARCHIVE_URL` / `GO_ARCHIVE_SHA256` | [dev/go.sh](../dev/go.sh) | official release | Custom archives require an explicit SHA-256 checksum |
| `JAVA_VERSION` | [dev/java.sh](../dev/java.sh) | interactive prompt (fallback `21`) | OpenJDK major: `8` \| `11` \| `17` \| `21` \| `25` |
| `INSTALL_OH_MY_ZSH` | [tools/zsh.sh](../tools/zsh.sh) | `yes` | Set `no` to install plain Zsh only |
| `INSTALL_DOCKER_DESKTOP` | [dev/docker.sh](../dev/docker.sh) | `yes` | Set `no` to skip the Docker Desktop GUI |
| `SETUP_LOG_FILE` | [setup.sh](../setup.sh) | `$HOME/ubuntu-setup.log` | Where the master installer appends timestamped output |
| `SWAP_SIZE_GB` | [essentials/swap.sh](../essentials/swap.sh) | `4` | Skipped if any swap is already active |
| `SWAP_FILE` / `FSTAB_FILE` | [essentials/swap.sh](../essentials/swap.sh) | `/swapfile` / `/etc/fstab` | Overrideable paths also support isolated regression testing |
| `ENABLE_UFW` | [essentials/firewall.sh](../essentials/firewall.sh) | `yes` | Set `no` to skip firewall configuration |
| `ENABLE_AUTO_UPDATES` | [essentials/auto-updates.sh](../essentials/auto-updates.sh) | `yes` | Set `no` to skip unattended-upgrades |
| `TZ` | [essentials/locale-timezone.sh](../essentials/locale-timezone.sh) | auto-detect | Falls back to ipapi.co when empty |
| `LOCALE` | [essentials/locale-timezone.sh](../essentials/locale-timezone.sh) | `en_US.UTF-8` | Generated and set as system default |
| `VSCODE_EXTENSIONS` | [ide/vscode-extensions.sh](../ide/vscode-extensions.sh) | empty | Whitespace-separated extension IDs; empty = no-op |
| `JETBRAINS_TOOLBOX_DIR` | [ide/jetbrains-toolbox.sh](../ide/jetbrains-toolbox.sh) | `$HOME/.local/share/JetBrains/Toolbox` | Toolbox install dir |
| `NVIM_INSTALL_DIR` | [ide/nvim.sh](../ide/nvim.sh) | `$HOME/.local/share/nvim-stable` | Where the Neovim tarball is extracted |
| `NVIM_ARCHIVE_URL` / `NVIM_ARCHIVE_SHA256` | [ide/nvim.sh](../ide/nvim.sh) | official release | Custom archives require an explicit SHA-256 checksum |
| `GPG_KEY_ID` | [system/gpg.sh](../system/gpg.sh) | unique `GIT_EMAIL` match | Select an existing secret key explicitly when email lookup is ambiguous |
| `ENABLE_GIT_COMMIT_SIGNING` | [tools/git-config.sh](../tools/git-config.sh) | `no` | Flip to `yes` after running [system/gpg.sh](../system/gpg.sh) |
| `BACKUP_DIR` | [tools/backup-home.sh](../tools/backup-home.sh) | `$HOME/backups` | Backup tarball destination |
| `BACKUP_ENCRYPT` | [tools/backup-home.sh](../tools/backup-home.sh) | `no` | `yes` = GPG-encrypt the tarball |
| `BACKUP_GPG_RECIPIENT` | [tools/backup-home.sh](../tools/backup-home.sh) | `$GIT_EMAIL` | GPG recipient for encrypted backups |
| `LLAMA_CPP_DIR` | [ai/llama-cpp.sh](../ai/llama-cpp.sh) | `$HOME/.local/src/llama.cpp` | Where llama.cpp is cloned and built |
| `PROMPT_BACKEND` | [ai/prompt-runner.sh](../ai/prompt-runner.sh) | `ollama` | `ollama` \| `openai` \| `anthropic` |
| `PROMPT_MODEL` | [ai/prompt-runner.sh](../ai/prompt-runner.sh) | per-backend default | Override the model the `prompt` CLI uses |
| `OLLAMA_HOST` | [ai/prompt-runner.sh](../ai/prompt-runner.sh) | `http://localhost:11434` | Remote Ollama endpoint if not localhost |
| `OPENAI_API_KEY` | [ai/prompt-runner.sh](../ai/prompt-runner.sh) | — | Required for `-b openai` |
| `ANTHROPIC_API_KEY` | [ai/prompt-runner.sh](../ai/prompt-runner.sh) | — | Required for `-b anthropic` |

## Behaviour notes

- **Identity propagation** — when `GIT_NAME` and `GIT_EMAIL` are set, [system/gpg.sh](../system/gpg.sh) generates the key non-interactively (RSA 4096, no passphrase). Without them it falls back to the interactive `gpg --full-generate-key` wizard.
- **Order of precedence** — inherited environment variables take precedence over repo `.env`, which takes precedence over `~/.env-ubuntu-post-install`. Inline overrides work: `GIT_EDITOR=vim bash system/base.sh`.
- **Export isolation** — values read only from config files remain shell variables and are not automatically inherited by child processes. Variables that were already exported remain exported.
- **Booleans** — feature flags use string `yes` / `no`, not `true` / `false` or numeric values.
- **Paths with `$HOME`** — quote them; config files are sourced as Bash, so normal parameter expansion applies.

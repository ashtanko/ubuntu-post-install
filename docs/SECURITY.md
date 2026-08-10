# Security notes

These scripts are designed for a **single-user developer workstation**, not a hardened server. This page calls out the trade-offs the scripts make so you can audit them before running.

> Reporting a vulnerability? Open a private security advisory in the GitHub repo, or email the maintainer listed in `git log --format='%ae' | head -1`.

## Sudo

Every install script uses `sudo` for system-level changes (apt, writing to `/etc/`, `/usr/local/`, etc.). The repo itself is read-only on disk under `$HOME` until you actually invoke a script — so always **review the script before running it**, especially if you cloned from a fork.

Scripts assume your user has standard interactive sudo. Long runs benefit from priming the cache first:

```bash
sudo -v && bash setup.sh
```

## Firewall ([essentials/firewall.sh](../essentials/firewall.sh))

| Setting | Value |
|---|---|
| Default incoming | `deny` |
| Default outgoing | `allow` |
| OpenSSH | `limit` (rate-limited against brute-force) |
| State | `enabled` |

Set `ENABLE_UFW=no` in `.env` to skip this script entirely. Already-active UFW is detected and not re-enabled.

If you SSH into the box, the OpenSSH `limit` rule is permissive enough for normal use but will block aggressive brute-force attempts. If you've moved sshd to a non-standard port, edit the rule yourself after the script runs.

## Sudo timestamp timeout ([system/sudoers.sh](../system/sudoers.sh))

Off by default — the script only acts when you set `SUDO_TIMESTAMP_TIMEOUT_MINUTES` in `.env`. When set, it writes a single `Defaults timestamp_timeout=<N>` line to `/etc/sudoers.d/99-upi-timeout`, validated with `visudo -cf` *before* it's installed so a bad value can't lock you out of `sudo`.

This script intentionally does **not** offer a passwordless-sudo option. Widening a sudoers rule is a bigger security trade-off than an idempotent provisioning script should make silently on your behalf — do that by hand if you decide you want it, with `visudo`.

## DNS resolvers ([system/hosts-dns.sh](../system/hosts-dns.sh))

Points `systemd-resolved` at third-party resolvers (default: Cloudflare `1.1.1.1` / Quad9 `9.9.9.9`) via a drop-in at `/etc/systemd/resolved.conf.d/upi-dns.conf`. That means DNS queries — effectively every hostname you resolve — now go to those resolvers instead of your network's default (e.g. your ISP or VPN). Set `DNS_SERVERS`/`DNS_FALLBACK_SERVERS` to resolvers you trust, or leave the script out of your run entirely if you want to keep whatever DNS your network hands out via DHCP/NetworkManager. The script no-ops on systems that don't run `systemd-resolved` rather than fighting the existing resolver setup.

## GPG ([system/gpg.sh](../system/gpg.sh))

The non-interactive code path (when `GIT_NAME` and `GIT_EMAIL` are both set in `.env`) generates a key with:

- **RSA 4096**
- **No expiry**
- **`%no-protection`** — no passphrase

This is convenient for automated commit signing in a personal dev environment. The trade-off: anyone with read access to `~/.gnupg` can sign as you. If that's not acceptable for your threat model, leave `GIT_NAME` and `GIT_EMAIL` unset and the script falls through to the interactive `gpg --full-generate-key` wizard, which lets you set a passphrase.

The script also writes `export GPG_TTY=$(tty)` to `~/.zshrc` and `~/.bashrc` so the agent can prompt for a passphrase when needed.

## SSH ([system/ssh.sh](../system/ssh.sh))

- Generates an **ed25519** key at `~/.ssh/id_ed25519` (only if one doesn't already exist).
- The key is generated with `ssh-keygen` defaults — passphrase prompt comes from `ssh-keygen` itself; press Enter for an unprotected key, or set one.
- Installs an idempotent `ssh-agent` autostart block in `~/.zshrc` and `~/.bashrc`. The agent socket is at `~/.ssh/agent.sock`; on shell start the block re-uses an existing live agent or spawns a new one and `ssh-add`s the key.

The autostart block is the only piece this repo persists into your shell rc files — the key generation itself is standard `ssh-keygen`.

## Auto-updates ([essentials/auto-updates.sh](../essentials/auto-updates.sh))

Enables `unattended-upgrades` for the **security pocket only** (default Ubuntu policy). Set `ENABLE_AUTO_UPDATES=no` to skip.

## Timezone auto-detection ([essentials/locale-timezone.sh](../essentials/locale-timezone.sh))

If `TZ` is left unset in `.env`, the script asks [ipapi.co](https://ipapi.co) to geolocate your public IP so it can set the right timezone. That's one outbound request carrying your IP to a third party, made once per run (and only when `TZ` is empty). Set `TZ` explicitly (e.g. `TZ="America/New_York"`) to skip the lookup entirely.

## What gets written to your shell rc files

Each block is appended to **both** `~/.zshrc` and `~/.bashrc` and guarded with `grep -q` so re-runs don't duplicate.

| Source | Block |
|---|---|
| [system/gpg.sh](../system/gpg.sh) | `export GPG_TTY=$(tty)` |
| [system/ssh.sh](../system/ssh.sh) | ssh-agent autostart (`SSH_AUTH_SOCK` reuse + `ssh-add`) |
| [dev/node.sh](../dev/node.sh) | `NVM_DIR` export + `nvm.sh` source |
| [dev/python.sh](../dev/python.sh) | `PYENV_ROOT` export + `$PYENV_ROOT/bin` prepended to `PATH` |
| [dev/rust.sh](../dev/rust.sh) | `$HOME/.cargo/bin` appended to `PATH` |
| [dev/go.sh](../dev/go.sh) | `$GO_INSTALL_DIR/bin` appended to `PATH` |

To audit:

```bash
grep -nE 'NVM_DIR|PYENV|cargo|GPG_TTY|ssh-agent|GO_INSTALL_DIR|/usr/local/go' ~/.zshrc ~/.bashrc
```

## APT keyring handling

Scripts that add a third-party apt repository follow the modern keyring pattern — they do **not** trust keys globally:

```bash
wget -qO- <vendor-key-url> | sudo gpg --dearmor -o /etc/apt/keyrings/<name>.gpg
echo "deb [arch=... signed-by=/etc/apt/keyrings/<name>.gpg] <repo-url> ..." \
  | sudo tee /etc/apt/sources.list.d/<name>.list
```

Each repo's signature is pinned to its own keyring file via `signed-by=`. Removing the source list or the keyring is enough to unwire the repo.

## Backup ([tools/backup-home.sh](../tools/backup-home.sh))

- **Default: unencrypted tarball.** The archive contains `~/.ssh`, `~/.gnupg`, `~/.aws`, `~/.kube`, `~/.config`, plus shell rc files and `~/.gitconfig`. Treat it like a copy of all your secrets.
- The archive is created with `chmod 600`.
- Set `BACKUP_ENCRYPT=yes` and `BACKUP_GPG_RECIPIENT=<your-email>` for GPG-encrypted output. The unencrypted intermediate is `shred`-ed (or `rm`-ed) after encryption.
- `$BACKUP_DIR` defaults to `~/backups`. Don't put this on a synced cloud drive unless you're using encryption.

## AI tools and external APIs

- [ai/ollama.sh](../ai/ollama.sh), [ai/ollama-models.sh](../ai/ollama-models.sh), and [ai/llama-cpp.sh](../ai/llama-cpp.sh) perform inference locally. Model and installer downloads still contact their configured upstream services.
- [ai/prompt-runner.sh](../ai/prompt-runner.sh) is multi-backend. With `-b openai` or `-b anthropic`, prompt content is sent to the respective vendor's API; `OPENAI_API_KEY` / `ANTHROPIC_API_KEY` from `.env` are read at runtime. Local Ollama is the default backend.
- [ai/claude.sh](../ai/claude.sh) verifies Anthropic's published signing-key fingerprint before adding its APT repository.
- [ai/codex.sh](../ai/codex.sh), [ai/github-copilot.sh](../ai/github-copilot.sh), [ai/huggingface-cli.sh](../ai/huggingface-cli.sh), [ai/aider.sh](../ai/aider.sh), [ai/goose.sh](../ai/goose.sh), [ai/qwen-code.sh](../ai/qwen-code.sh), [ai/cursor-agent.sh](../ai/cursor-agent.sh), [ai/mistral-vibe.sh](../ai/mistral-vibe.sh), [ai/fabric.sh](../ai/fabric.sh), [ai/gemini.sh](../ai/gemini.sh), [ai/opencode.sh](../ai/opencode.sh), and [ai/antigravity.sh](../ai/antigravity.sh) install vendor CLIs that follow their own auth and telemetry policies. Remote shell installers are downloaded to a temporary file and must complete successfully before execution; the wrapper does not independently sign their contents.
- [ai/cline.sh](../ai/cline.sh), [ai/llm-cli.sh](../ai/llm-cli.sh), [ai/litellm.sh](../ai/litellm.sh), and [ai/mcp-inspector.sh](../ai/mcp-inspector.sh) install third-party packages from npm or PyPI. The wrappers do not configure credentials; review each tool's provider, telemetry, and local-execution settings before use.
- Coding agents can read and modify files or execute commands after approval. MCP Inspector starts local services (ports 6274 and 6277 by default), while LiteLLM starts an API proxy (port 4000 by default); do not expose them to untrusted networks without authentication and access controls.

## Shell frameworks and prompts

- [tools/zsh.sh](../tools/zsh.sh), [tools/fish.sh](../tools/fish.sh), and [tools/starship.sh](../tools/starship.sh) download the official Oh My Zsh, Fisher, and Starship bootstrap scripts over TLS into temporary files before executing them. These upstream scripts are not independently signed by this repository.
- The shell installers edit the selected user's login shell and/or shell startup files. Review `~/.zshrc`, `~/.config/fish`, and the Starship init blocks if you later switch frameworks or prompts.

## Telemetry

These scripts don't phone home. Upstream installers do whatever they do — Google Chrome, Docker Desktop, JetBrains Toolbox, VS Code, and the vendor AI CLIs each have their own opt-out paths in their own settings. Review them after install if that matters to you.

The one exception in the other direction: [essentials/motd-news.sh](../essentials/motd-news.sh) *disables* an existing outbound call — Ubuntu's `motd-news` fetches ESM/livepatch headlines from Canonical on login. Turning it off is opt-out, not opt-in.

## Threat model in one sentence

**These scripts trust your network, the upstream package repositories, and you running them with sudo.** They don't defend against a compromised mirror, a hostile `.env`, or a malicious script in your fork. Read what you run.

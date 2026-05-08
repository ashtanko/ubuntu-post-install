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

- [ai/ollama.sh](../ai/ollama.sh) and [ai/llama-cpp.sh](../ai/llama-cpp.sh) run **fully local** — no traffic leaves your machine.
- [ai/prompt-runner.sh](../ai/prompt-runner.sh) is multi-backend. With `-b openai` or `-b anthropic`, prompt content is sent to the respective vendor's API; `OPENAI_API_KEY` / `ANTHROPIC_API_KEY` from `.env` are read at runtime. Local Ollama is the default backend.
- [tools/claude.sh](../tools/claude.sh), [ai/gemini.sh](../ai/gemini.sh), [ai/opencode.sh](../ai/opencode.sh), [ai/antigravity.sh](../ai/antigravity.sh) install vendor CLIs that follow their own auth and telemetry policies.

## Telemetry

These scripts don't phone home. Upstream installers do whatever they do — Google Chrome, Docker Desktop, JetBrains Toolbox, VS Code, and the vendor AI CLIs each have their own opt-out paths in their own settings. Review them after install if that matters to you.

## Threat model in one sentence

**These scripts trust your network, the upstream package repositories, and you running them with sudo.** They don't defend against a compromised mirror, a hostile `.env`, or a malicious script in your fork. Read what you run.

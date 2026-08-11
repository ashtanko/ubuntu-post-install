# Update scripts

These maintenance wrappers update tools installed by this project when upstream provides a documented command, installer-based update path, or clean source-checkout workflow. They are intentionally separate from the fresh-install catalog and its completion markers.

Run one updater:

```bash
bash updates/update-claude.sh
```

Or run every supported updater; tools that are not installed are skipped:

```bash
bash updates/update-all.sh
```

| Script | Update path |
|---|---|
| `update-aider.sh` | `aider --upgrade` |
| `update-all.sh` | Runs every other updater and reports a combined result |
| `update-android-studio.sh` | `snap refresh android-studio` |
| `update-antigravity.sh` | Upgrades only the `antigravity` APT package |
| `update-atuin.sh` | `atuin update` |
| `update-aws-cli.sh` | Verifies AWS's detached signature, then runs the v2 installer with `--update` |
| `update-bun.sh` | `bun upgrade` |
| `update-chezmoi.sh` | `chezmoi upgrade` |
| `update-claude.sh` | Upgrades only the `claude-code` APT package, or the global `@anthropic-ai/claude-code` npm package when that owns `claude` |
| `update-cline.sh` | `cline update` for the active global npm installation |
| `update-codex.sh` | `codex update` for the standalone CLI installed by this project |
| `update-composer.sh` | `composer self-update --no-interaction` |
| `update-ctop.sh` | Atomically installs the checksum-verified latest official release |
| `update-cursor-agent.sh` | `cursor-agent update` |
| `update-deno.sh` | `deno upgrade --quiet` |
| `update-dive.sh` | Installs the checksum-verified latest official release package |
| `update-fisher.sh` | `fisher update` |
| `update-flutter.sh` | `flutter upgrade` on the current channel |
| `update-gemini.sh` | Installs the latest stable npm package into the owning global prefix |
| `update-gitleaks.sh` | Atomically installs the checksum-verified latest official release |
| `update-github-copilot.sh` | `copilot update` |
| `update-go.sh` | Safely replaces the SDK with the checksum-verified latest stable Go release |
| `update-goose.sh` | `goose update` |
| `update-huggingface-cli.sh` | `hf update` |
| `update-just.sh` | Installs the checksum-verified latest official release |
| `update-lazydocker.sh` | Installs the checksum-verified latest official release |
| `update-llama-cpp.sh` | Fast-forwards the clean checkout and rebuilds its existing CMake configuration |
| `update-mcp-inspector.sh` | Installs the latest npm package into the owning global prefix |
| `update-mistral-vibe.sh` | `uv tool upgrade mistral-vibe` |
| `update-node.sh` | Updates the official NVM checkout, then installs and selects the latest Node.js LTS |
| `update-nvim.sh` | Replaces the managed installation only when an official or configured release digest is available |
| `update-oh-my-zsh.sh` | Runs Oh My Zsh's automation-safe upgrade script |
| `update-opencode.sh` | `opencode upgrade --method curl` |
| `update-pipx-tools.sh` | Upgrades installed project-managed pipx applications |
| `update-pyenv.sh` | Fast-forwards the clean pyenv checkout |
| `update-rbenv.sh` | Fast-forwards the clean rbenv and ruby-build checkouts |
| `update-rclone.sh` | `rclone selfupdate --stable` for the standalone binary |
| `update-restic.sh` | `restic self-update` for the standalone binary |
| `update-rust.sh` | `rustup update` |
| `update-starship.sh` | Atomically installs the checksum-verified latest official release asset |
| `update-tpm.sh` | Fast-forwards the clean TPM checkout |
| `update-vscode-extensions.sh` | `code --update-extensions` for the Debian-packaged VS Code installation |
| `update-vscode.sh` | Upgrades only the Microsoft `code` APT package |
| `update-yq.sh` | Installs the checksum-verified latest official release |

Individual scripts exit successfully when the matching installation is absent or is not owned by the installation method this project uses. Source-checkout updaters fail instead of overwriting uncommitted changes. `update-all.sh` continues after a failure and returns a non-zero status with the failed script names.

Version pins are also respected: Codex, Cline, GitHub Copilot CLI, Go, Neovim, MCP Inspector, LLM, and LiteLLM stay unchanged when their corresponding configuration selects a fixed release or custom archive.

Most software installed through APT remains covered by normal system package upgrades, and applications with their own automatic updater keep using it. The repository omits tools that have no documented, ownership-compatible, verifiable scriptable update path; it does not guess at manual downloads or execute unauthenticated mutable installers. See `skipped.txt` for the audited per-installer reasons.

# shellcheck shell=bash
# Single source of truth for which scripts are tested in Docker and how.
#
# Format: "path|compat|env_vars|verify_cmd|skip_reason|state_paths"
#   compat     : yes | no | partial
#   env_vars   : comma-separated KEY=VAL pairs (passed via `env` to the script)
#   verify_cmd : shell snippet asserting installation succeeded (empty = no verify)
#   skip_reason: required when compat=no, ignored otherwise
#   state_paths: optional comma-separated absolute paths to include in snapshots;
#                literal $HOME is expanded without evaluating shell code
#
# When verify_cmd is "FILE", run-script.sh looks for tests/verify/<dir>_<base>.sh
# instead. Use that for multi-line verifications.

SCRIPTS=(
  # essentials/
  "essentials/auto-updates.sh|no|||systemctl enable unattended-upgrades fails without systemd"
  "essentials/firewall.sh|no|||UFW needs kernel netfilter; rules don't apply inside a container"
  "essentials/fstrim.sh|no|||no systemd in a plain container to manage fstrim.timer; ROTA detection works but has nothing to enable"
  "essentials/gnome-settings.sh|no|||requires active GNOME session (gsettings/dbus)"
  "essentials/journald.sh|no|||no systemd-journald in a plain container; the drop-in would never take effect"
  "essentials/locale-timezone.sh|partial|TZ=Etc/UTC,LOCALE=en_US.UTF-8|[[ \$(locale -a) == *en_US.utf8* ]]|timedatectl needs systemd; locale-gen part works"
  "essentials/motd-news.sh|no|||/etc/default/motd-news and motd-news.timer aren't present in the minimal container base image"
  "essentials/swap.sh|no|||needs real block device + /etc/fstab persistence"
  "essentials/sysctl-limits.sh|partial||grep -q 'fs.inotify.max_user_watches=524288' /etc/sysctl.d/99-upi-inotify.conf \&\& grep -q 'soft nofile 1048576' /etc/security/limits.d/99-upi-nofile.conf|/proc/sys is read-only in an unprivileged container; sysctl -p no-ops but the drop-in files still land and are verified|/etc/sysctl.d/99-upi-inotify.conf,/etc/security/limits.d/99-upi-nofile.conf"
  "essentials/system-info.sh|yes||ls \$HOME/system-info-*.log >/dev/null|"
  "essentials/fail2ban.sh|partial||grep -q 'maxretry = 5' /etc/fail2ban/jail.d/99-upi-sshd.local|no systemd to start the fail2ban service; the jail.d drop-in still lands and is verified|/etc/fail2ban/jail.d/99-upi-sshd.local"
  "essentials/lynis.sh|yes||ls \$HOME/lynis-audit-*.log >/dev/null|"

  # system/
  "system/base.sh|yes|GIT_NAME=CI Tester,GIT_EMAIL=ci@example.com|FILE||\$HOME/.gitconfig"
  "system/gpg.sh|partial|GIT_NAME=CI Tester,GIT_EMAIL=ci@example.com|[[ \$(gpg --list-secret-keys) == *ci@example.com* ]]|entropy slow; key generated but git signing config skipped if no rc|\$HOME/.gnupg,\$HOME/.gitconfig"
  "system/hostname.sh|no|||hostnamectl/UTS namespace changes aren't meaningful inside a container"
  "system/hosts-dns.sh|no|||requires systemd-resolved (resolvectl); not present in minimal containers"
  "system/keyboard.sh|no|||keyd daemon needs /dev/uinput + systemd"
  "system/ntp.sh|partial||dpkg -s chrony &>/dev/null|systemd-timesyncd path needs systemd as PID 1; container run only exercises the chrony-install fallback"
  "system/ssh.sh|partial|GIT_EMAIL=ci@example.com|test -f \$HOME/.ssh/id_ed25519|may prompt for passphrase if interactive|\$HOME/.ssh"
  "system/sudoers.sh|yes|SUDO_TIMESTAMP_TIMEOUT_MINUTES=15|sudo grep -q 'timestamp_timeout=15' /etc/sudoers.d/99-upi-timeout|"
  "system/user-groups.sh|yes||grep -qw dialout <(sudo -u \$(id -un) id -nG) && grep -qw plugdev <(sudo -u \$(id -un) id -nG)|"

  # apps/
  "apps/browsers.sh|no|||Chrome installs but is GUI-only; not useful in CI"
  "apps/guake.sh|no|||GUI terminal emulator"
  "apps/postman.sh|no|||Postman is a GUI app; needs display"
  "apps/vscode.sh|no|||GUI editor; pulls hundreds of MB for no test value"
  "apps/warp.sh|no|||GUI terminal"
  "apps/bitwarden-cli.sh|yes||command -v bw && bw --version|"
  "apps/flameshot.sh|no|||GUI screenshot tool; needs a display server"

  # dev/
  "dev/aws-cli.sh|yes||command -v aws && command -v session-manager-plugin|"
  "dev/databases.sh|yes||command -v psql && command -v redis-cli && command -v sqlite3 && command -v mysql|"
  "dev/docker.sh|partial|INSTALL_DOCKER_DESKTOP=no|command -v docker|Docker daemon won't start in container; CLI installs fine"
  "dev/flutter.sh|no|||Flutter SDK and Linux desktop dependencies are large and GUI-focused"
  "dev/go.sh|yes|GO_INSTALL_DIR=/usr/local/go|/usr/local/go/bin/go version||/usr/local/go"
  "dev/java.sh|yes||command -v javac && javac -version|"
  "dev/kubernetes.sh|yes||command -v kubectl && command -v helm && command -v k9s && command -v kind && command -v kustomize|"
  "dev/node.sh|yes||FILE||\$HOME/.nvm"
  "dev/python.sh|yes||FILE||\$HOME/.pyenv"
  "dev/rust.sh|yes||bash -lc 'command -v rustc && rustc --version'||\$HOME/.cargo,\$HOME/.rustup"
  "dev/terraform.sh|yes||command -v terraform && command -v tflint && command -v tfsec|"
  "dev/dotnet.sh|yes||command -v dotnet && dotnet --list-sdks|"
  "dev/ruby.sh|yes||FILE||\$HOME/.rbenv"
  "dev/gcloud.sh|yes||command -v gcloud && gcloud --version|"
  "dev/azure-cli.sh|yes||command -v az && az version|"
  "dev/podman.sh|partial||command -v podman && command -v podman-compose|rootless containers need subuid/subgid + user namespaces; the CLI installs and is verified"
  "dev/deno.sh|yes||test -x \$HOME/.deno/bin/deno && \$HOME/.deno/bin/deno --version||\$HOME/.deno"
  "dev/bun.sh|yes||test -x \$HOME/.bun/bin/bun && \$HOME/.bun/bin/bun --version||\$HOME/.bun"
  "dev/php.sh|yes||command -v php && command -v composer|"
  "dev/cpp.sh|yes||command -v cmake && command -v gdb && command -v clang-tidy && command -v valgrind|"

  # tools/
  "tools/backup-home.sh|no|||interactive backup utility; not a setup script"
  "tools/btop.sh|yes||FILE|"
  "tools/cli-tools.sh|yes||FILE|"
  "tools/fonts.sh|yes||test -n \"\$(find \$HOME/.local/share/fonts -type f -print -quit 2>/dev/null)\"||\$HOME/.local/share/fonts"
  "tools/fish.sh|yes|SET_FISH_AS_DEFAULT=no|FILE||\$HOME/.config/fish"
  "tools/git-config.sh|yes|GIT_NAME=CI Tester,GIT_EMAIL=ci@example.com|git config --global --get pull.rebase||\$HOME/.gitconfig,\$HOME/.config/git"
  "tools/modern-cli.sh|yes||FILE|"
  "tools/pre-commit-setup.sh|yes||bash -lc 'command -v pre-commit'||\$HOME/.config/pre-commit,\$HOME/.config/git/template"
  "tools/starship.sh|yes||FILE||\$HOME/.config/fish"
  "tools/system-maintenance.sh|partial||test -d /var/cache/apt/archives|journalctl/snap/flatpak may be absent; available maintenance steps still run"
  "tools/zsh.sh|yes|INSTALL_OH_MY_ZSH=no|command -v zsh||\$HOME/.oh-my-zsh"
  "tools/wireshark.sh|partial||command -v tshark|debconf-set-selections + dpkg-reconfigure work, but there's no real capture interface to verify in a container"
  "tools/dotfiles.sh|yes||test -x \$HOME/.local/bin/chezmoi && \$HOME/.local/bin/chezmoi --version|"
  "tools/rclone.sh|yes||command -v rclone && rclone version|"
  "tools/lazydocker.sh|yes||command -v lazydocker && lazydocker --version|"
  "tools/tmux-config.sh|yes||FILE||\$HOME/.tmux.conf,\$HOME/.tmux/plugins/tpm"
  "tools/restic.sh|yes||command -v restic && restic version|"
  "tools/network-tools.sh|yes||command -v mtr && command -v nmap && command -v dig && command -v iperf3 && command -v http|"
  "tools/gitleaks.sh|yes||command -v gitleaks && gitleaks version|"
  "tools/yq.sh|yes||command -v yq && yq --version|"
  "tools/just.sh|yes||command -v just && just --version|"
  "tools/atuin.sh|yes||test -x \$HOME/.atuin/bin/atuin && \$HOME/.atuin/bin/atuin --version||\$HOME/.atuin"

  # ide/
  "ide/jetbrains-toolbox.sh|no|||GUI app; needs display"
  "ide/nvim.sh|yes|NVIM_INSTALL_DIR=\$HOME/.local/share/nvim-stable|test -x \$HOME/.local/bin/nvim && \$HOME/.local/bin/nvim --version >/dev/null||\$HOME/.local/share/nvim-stable"
  "ide/vscode-extensions.sh|no|||requires VS Code installed + display"
  "ide/zed.sh|no|||GUI editor"
  "ide/android-studio.sh|no|||snap install needs snapd + a running snapd daemon; large GUI-only download, no test value"
  "ide/cursor.sh|no|||Electron AppImage GUI editor; needs FUSE + display, no test value"
  "ide/dbeaver.sh|no|||GUI database client; needs display"

  # ai/
  "ai/aider.sh|yes||test -x \$HOME/.local/bin/aider && \$HOME/.local/bin/aider --version|"
  "ai/antigravity.sh|partial||command -v antigravity >/dev/null|requires Google APT; may not exist for all Ubuntu versions"
  "ai/claude.sh|yes|CLAUDE_CHANNEL=stable|command -v claude && claude --version||/etc/apt/keyrings/claude-code.asc,/etc/apt/sources.list.d/claude-code.list"
  "ai/cline.sh|yes|CLINE_VERSION=latest|command -v cline && cline --version|"
  "ai/codex.sh|yes||test -x \$HOME/.local/bin/codex && \$HOME/.local/bin/codex --version||\$HOME/.codex/packages/standalone"
  "ai/cursor-agent.sh|yes||test -x \$HOME/.local/bin/cursor-agent && \$HOME/.local/bin/cursor-agent --version||\$HOME/.local/share/cursor-agent"
  "ai/fabric.sh|yes||test -x \$HOME/.local/bin/fabric && \$HOME/.local/bin/fabric --version|"
  "ai/gemini.sh|yes||bash -lc 'command -v gemini'|"
  "ai/github-copilot.sh|yes||test -x \$HOME/.local/bin/copilot && \$HOME/.local/bin/copilot version|"
  "ai/goose.sh|yes||test -x \$HOME/.local/bin/goose && \$HOME/.local/bin/goose --version|"
  "ai/huggingface-cli.sh|yes||test -x \$HOME/.local/bin/hf && \$HOME/.local/bin/hf version||\$HOME/.hf-cli"
  "ai/llama-cpp.sh|no|||CMake build OOMs / takes too long in CI containers; verify on real hardware"
  "ai/litellm.sh|yes|LITELLM_VERSION=latest|test -x \$HOME/.local/bin/litellm && \$HOME/.local/bin/litellm --help >/dev/null||\$HOME/.local/share/pipx/venvs/litellm"
  "ai/llm-cli.sh|yes|LLM_VERSION=latest|test -x \$HOME/.local/bin/llm && \$HOME/.local/bin/llm --version||\$HOME/.local/share/pipx/venvs/llm"
  "ai/mcp-inspector.sh|yes|MCP_INSPECTOR_VERSION=latest|command -v mcp-inspector && mcp-inspector --help >/dev/null|"
  "ai/mistral-vibe.sh|yes||test -x \$HOME/.local/bin/vibe && \$HOME/.local/bin/vibe --version||\$HOME/.local/share/uv/tools/mistral-vibe"
  "ai/ollama-models.sh|no|||downloads user-selected large models and requires a running Ollama service"
  "ai/ollama.sh|partial||command -v ollama|systemd service won't start; binary installs"
  "ai/opencode.sh|yes||test -x \$HOME/.opencode/bin/opencode||\$HOME/.opencode"
  "ai/prompt-runner.sh|yes||test -x \$HOME/.local/bin/prompt|"
  "ai/qwen-code.sh|yes||if [ -x \$HOME/.local/bin/qwen ]; then true; else test -x \$HOME/.qwen/bin/qwen; fi||\$HOME/.qwen"

  # software/
  "software/boxes.sh|no|||GNOME Boxes needs KVM + display"
  "software/virtualbox.sh|no|||needs kernel modules + bare metal"
  "software/vmware.sh|no|||VMware Workstation needs manual download + kernel build"

  # vpn/
  "vpn/nord.sh|no|||installer invokes systemctl to enable nordvpnd; daemon won't start in container — verify on real hardware"
  "vpn/tailscale.sh|no|||installer invokes systemctl to enable tailscaled; daemon won't start in container — verify on real hardware"

  # mobile/
  "mobile/zip_flutter_plugin.sh|no|||manual utility, not a setup script"

  # root/
  "setup.sh|no|||interactive menu orchestrator; covered by local regression tests rather than Docker"
  "install.sh|no|||remote installer; downloads release tarball, not exercised in container tests"
)

# ---- Helpers ---------------------------------------------------------------

# Iterate manifest entries, calling: $1 path compat env_vars verify_cmd skip_reason state_paths
manifest_iter() {
    local cb="$1" entry path compat env_vars verify_cmd skip_reason state_paths
    for entry in "${SCRIPTS[@]}"; do
        IFS='|' read -r path compat env_vars verify_cmd skip_reason state_paths <<<"$entry"
        "$cb" "$path" "$compat" "$env_vars" "$verify_cmd" "$skip_reason" "$state_paths"
    done
}

# Lookup helpers (return field for given path; exit 1 if not found)
manifest_lookup() {
    local path="$1" field="$2" entry p c e v r s
    for entry in "${SCRIPTS[@]}"; do
        IFS='|' read -r p c e v r s <<<"$entry"
        if [ "$p" = "$path" ]; then
            case "$field" in
                compat) printf '%s\n' "$c" ;;
                env)    printf '%s\n' "$e" ;;
                verify) printf '%s\n' "$v" ;;
                reason) printf '%s\n' "$r" ;;
                state)  printf '%s\n' "$s" ;;
            esac
            return 0
        fi
    done
    return 1
}

manifest_paths() {
    local entry p _rest
    for entry in "${SCRIPTS[@]}"; do
        IFS='|' read -r p _rest <<<"$entry"
        printf '%s\n' "$p"
    done
}

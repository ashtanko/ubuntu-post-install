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
  "essentials/gnome-settings.sh|no|||requires active GNOME session (gsettings/dbus)"
  "essentials/locale-timezone.sh|partial|TZ=Etc/UTC,LOCALE=en_US.UTF-8|[[ \$(locale -a) == *en_US.utf8* ]]|timedatectl needs systemd; locale-gen part works"
  "essentials/swap.sh|no|||needs real block device + /etc/fstab persistence"
  "essentials/system-info.sh|yes||ls \$HOME/system-info-*.log >/dev/null|"

  # system/
  "system/base.sh|yes|GIT_NAME=CI Tester,GIT_EMAIL=ci@example.com|FILE||\$HOME/.gitconfig"
  "system/gpg.sh|partial|GIT_NAME=CI Tester,GIT_EMAIL=ci@example.com|[[ \$(gpg --list-secret-keys) == *ci@example.com* ]]|entropy slow; key generated but git signing config skipped if no rc|\$HOME/.gnupg,\$HOME/.gitconfig"
  "system/keyboard.sh|no|||keyd daemon needs /dev/uinput + systemd"
  "system/ssh.sh|partial|GIT_EMAIL=ci@example.com|test -f \$HOME/.ssh/id_ed25519|may prompt for passphrase if interactive|\$HOME/.ssh"

  # apps/
  "apps/browsers.sh|no|||Chrome installs but is GUI-only; not useful in CI"
  "apps/guake.sh|no|||GUI terminal emulator"
  "apps/postman.sh|no|||Postman is a GUI app; needs display"
  "apps/vscode.sh|no|||GUI editor; pulls hundreds of MB for no test value"
  "apps/warp.sh|no|||GUI terminal"

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

  # tools/
  "tools/backup-home.sh|no|||interactive backup utility; not a setup script"
  "tools/btop.sh|yes||FILE|"
  "tools/claude.sh|yes||command -v claude|"
  "tools/cli-tools.sh|yes||FILE|"
  "tools/fonts.sh|yes||test -n \"\$(find \$HOME/.local/share/fonts -type f -print -quit 2>/dev/null)\"||\$HOME/.local/share/fonts"
  "tools/git-config.sh|yes|GIT_NAME=CI Tester,GIT_EMAIL=ci@example.com|git config --global --get pull.rebase||\$HOME/.gitconfig,\$HOME/.config/git"
  "tools/modern-cli.sh|yes||FILE|"
  "tools/pre-commit-setup.sh|yes||bash -lc 'command -v pre-commit'||\$HOME/.config/pre-commit,\$HOME/.config/git/template"
  "tools/system-maintenance.sh|partial||test -d /var/cache/apt/archives|journalctl/snap/flatpak may be absent; available maintenance steps still run"
  "tools/zsh.sh|yes|INSTALL_OH_MY_ZSH=no|command -v zsh||\$HOME/.oh-my-zsh"

  # ide/
  "ide/jetbrains-toolbox.sh|no|||GUI app; needs display"
  "ide/nvim.sh|yes|NVIM_INSTALL_DIR=\$HOME/.local/share/nvim-stable|test -x \$HOME/.local/bin/nvim && \$HOME/.local/bin/nvim --version >/dev/null||\$HOME/.local/share/nvim-stable"
  "ide/vscode-extensions.sh|no|||requires VS Code installed + display"
  "ide/zed.sh|no|||GUI editor"

  # ai/
  "ai/antigravity.sh|partial||command -v antigravity >/dev/null|requires Google APT; may not exist for all Ubuntu versions"
  "ai/gemini.sh|yes||bash -lc 'command -v gemini'|"
  "ai/llama-cpp.sh|no|||CMake build OOMs / takes too long in CI containers; verify on real hardware"
  "ai/ollama.sh|partial||command -v ollama|systemd service won't start; binary installs"
  "ai/opencode.sh|yes||test -x \$HOME/.opencode/bin/opencode||\$HOME/.opencode"
  "ai/prompt-runner.sh|yes||test -x \$HOME/.local/bin/prompt|"

  # software/
  "software/boxes.sh|no|||GNOME Boxes needs KVM + display"
  "software/virtualbox.sh|no|||needs kernel modules + bare metal"
  "software/vmware.sh|no|||VMware Workstation needs manual download + kernel build"

  # vpn/
  "vpn/nord.sh|no|||installer invokes systemctl to enable nordvpnd; daemon won't start in container — verify on real hardware"

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

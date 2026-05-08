# shellcheck shell=bash
# Single source of truth for which scripts are tested in Docker and how.
#
# Format: "path|compat|env_vars|verify_cmd|skip_reason"
#   compat     : yes | no | partial
#   env_vars   : comma-separated KEY=VAL pairs (passed via `env` to the script)
#   verify_cmd : shell snippet asserting installation succeeded (empty = no verify)
#   skip_reason: required when compat=no, ignored otherwise
#
# When verify_cmd is "FILE", run-script.sh looks for tests/verify/<dir>_<base>.sh
# instead. Use that for multi-line verifications.

SCRIPTS=(
  # essentials/
  "essentials/auto-updates.sh|no|||systemctl enable unattended-upgrades fails without systemd"
  "essentials/firewall.sh|no|||UFW needs kernel netfilter; rules don't apply inside a container"
  "essentials/gnome-settings.sh|no|||requires active GNOME session (gsettings/dbus)"
  "essentials/locale-timezone.sh|partial|TZ=Etc/UTC,LOCALE=en_US.UTF-8|locale -a | grep -q en_US.utf8|timedatectl needs systemd; locale-gen part works"
  "essentials/swap.sh|no|||needs real block device + /etc/fstab persistence"
  "essentials/system-info.sh|yes||ls \$HOME/system-info-*.log >/dev/null|"

  # system/
  "system/base.sh|yes|GIT_NAME=CI Tester,GIT_EMAIL=ci@example.com|FILE|"
  "system/gpg.sh|partial|GIT_NAME=CI Tester,GIT_EMAIL=ci@example.com|gpg --list-secret-keys | grep -q ci@example.com|entropy slow; key generated but git signing config skipped if no rc"
  "system/keyboard.sh|no|||keyd daemon needs /dev/uinput + systemd"
  "system/ssh.sh|partial|GIT_EMAIL=ci@example.com|test -f \$HOME/.ssh/id_ed25519|may prompt for passphrase if interactive"

  # apps/
  "apps/browsers.sh|no|||Chrome installs but is GUI-only; not useful in CI"
  "apps/guake.sh|no|||GUI terminal emulator"
  "apps/vscode.sh|no|||GUI editor; pulls hundreds of MB for no test value"
  "apps/warp.sh|no|||GUI terminal"

  # dev/
  "dev/docker.sh|partial|INSTALL_DOCKER_DESKTOP=no|command -v docker|Docker daemon won't start in container; CLI installs fine"
  "dev/flutter.sh|no|||Android SDK + Linux desktop deps are huge and need display"
  "dev/go.sh|yes|GO_INSTALL_DIR=/usr/local/go|/usr/local/go/bin/go version|"
  "dev/java.sh|yes||command -v javac && javac -version|"
  "dev/node.sh|yes||FILE|"
  "dev/python.sh|yes||FILE|"
  "dev/rust.sh|yes||bash -lc 'command -v rustc && rustc --version'|"

  # tools/
  "tools/backup-home.sh|no|||interactive backup utility; not a setup script"
  "tools/claude.sh|yes||command -v claude|"
  "tools/cli-tools.sh|yes||FILE|"
  "tools/fonts.sh|yes||fc-list 2>/dev/null | grep -qi 'jetbrains\\|fira\\|hack' || ls \$HOME/.local/share/fonts/ | grep -qi nerd|"
  "tools/git-config.sh|yes|GIT_NAME=CI Tester,GIT_EMAIL=ci@example.com|git config --global --get pull.rebase|"
  "tools/pre-commit-setup.sh|yes||bash -lc 'command -v pre-commit'|"
  "tools/system-maintenance.sh|partial||true|journalctl/snap/flatfak likely absent; should no-op gracefully"
  "tools/zsh.sh|yes|INSTALL_OH_MY_ZSH=no|command -v zsh|"

  # ide/
  "ide/jetbrains-toolbox.sh|no|||GUI app; needs display"
  "ide/nvim.sh|yes|NVIM_INSTALL_DIR=\$HOME/.local/share/nvim-stable|test -x \$HOME/.local/bin/nvim && \$HOME/.local/bin/nvim --version | head -1|"
  "ide/vscode-extensions.sh|no|||requires VS Code installed + display"
  "ide/zed.sh|no|||GUI editor"

  # ai/
  "ai/antigravity.sh|partial||command -v antigravity 2>/dev/null || dpkg -s antigravity >/dev/null 2>&1|requires Google APT; may not exist for all Ubuntu versions"
  "ai/gemini.sh|yes||bash -lc 'command -v gemini'|"
  "ai/llama-cpp.sh|no|||CMake build OOMs / takes too long in CI containers; verify on real hardware"
  "ai/ollama.sh|partial||command -v ollama|systemd service won't start; binary installs"
  "ai/opencode.sh|yes||test -x \$HOME/.opencode/bin/opencode|"
  "ai/prompt-runner.sh|yes||test -x \$HOME/.local/bin/prompt|"

  # software/
  "software/boxes.sh|no|||GNOME Boxes needs KVM + display"
  "software/virtualbox.sh|no|||needs kernel modules + bare metal"
  "software/vmware.sh|no|||VMware Workstation needs manual download + kernel build"

  # mobile/
  "mobile/zip_flutter_plugin.sh|no|||manual utility, not a setup script"

  # root/
  "setup.sh|no|||interactive menu orchestrator; tested via individual scripts"
  "install.sh|no|||remote installer; downloads release tarball, not exercised in container tests"
)

# ---- Helpers ---------------------------------------------------------------

# Iterate manifest entries, calling: $1 path compat env_vars verify_cmd skip_reason
manifest_iter() {
    local cb="$1" entry path compat env_vars verify_cmd skip_reason
    for entry in "${SCRIPTS[@]}"; do
        IFS='|' read -r path compat env_vars verify_cmd skip_reason <<<"$entry"
        "$cb" "$path" "$compat" "$env_vars" "$verify_cmd" "$skip_reason"
    done
}

# Lookup helpers (return field for given path; exit 1 if not found)
manifest_lookup() {
    local path="$1" field="$2" entry p c e v r
    for entry in "${SCRIPTS[@]}"; do
        IFS='|' read -r p c e v r <<<"$entry"
        if [ "$p" = "$path" ]; then
            case "$field" in
                compat) printf '%s\n' "$c" ;;
                env)    printf '%s\n' "$e" ;;
                verify) printf '%s\n' "$v" ;;
                reason) printf '%s\n' "$r" ;;
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

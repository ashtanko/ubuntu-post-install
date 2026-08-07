# shellcheck shell=bash

# Load configuration without exporting config-only values. Precedence is:
# inherited environment > repository .env > ~/.env-ubuntu-post-install.
load_config() {
    local __upi_repo_root="${1:?load_config requires the repository root}"
    local __upi_user_config="${UBUNTU_POST_INSTALL_CONFIG:-$HOME/.env-ubuntu-post-install}"
    local __upi_repo_config="$__upi_repo_root/.env"
    local __upi_name __upi_declaration
    local -A __upi_inherited_values=()
    local -A __upi_inherited_exports=()

    while IFS= read -r __upi_name; do
        [[ "$__upi_name" =~ ^[a-zA-Z_][a-zA-Z0-9_]*$ ]] || continue
        __upi_inherited_values["$__upi_name"]="${!__upi_name}"
        __upi_inherited_exports["$__upi_name"]=1
    done < <(compgen -e)

    # shellcheck source=/dev/null
    [[ -f "$__upi_user_config" ]] && source "$__upi_user_config"
    # shellcheck source=/dev/null
    [[ -f "$__upi_repo_config" ]] && source "$__upi_repo_config"

    # An `export` in a config file must not leak a secret into child processes.
    while IFS= read -r __upi_name; do
        __upi_declaration="$(declare -p "$__upi_name" 2>/dev/null || true)"
        if [[ "$__upi_declaration" == "declare -x"* ]] && [[ -z "${__upi_inherited_exports[$__upi_name]:-}" ]]; then
            export -n "${__upi_name?}"
        fi
    done < <(compgen -v)

    for __upi_name in "${!__upi_inherited_values[@]}"; do
        printf -v "$__upi_name" '%s' "${__upi_inherited_values[$__upi_name]}"
        export "${__upi_name?}"
    done
}

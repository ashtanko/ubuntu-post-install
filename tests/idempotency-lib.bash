# shellcheck shell=bash

snapshot_path() {
    local path="$1" item type mode link hash hash_output listing sorted_listing
    local -a items=()
    echo "## path $path"
    if [[ ! -e "$path" && ! -L "$path" ]]; then
        echo "missing"
        return 0
    fi
    listing=$(mktemp)
    if ! find -P "$path" -print0 > "$listing"; then
        echo "❌ could not traverse tracked state: $path" >&2
        rm -f "$listing"
        return 1
    fi
    sorted_listing=$(mktemp)
    if ! sort -z "$listing" > "$sorted_listing"; then
        echo "❌ could not sort tracked state: $path" >&2
        rm -f "$listing" "$sorted_listing"
        return 1
    fi
    mapfile -d '' -t items < "$sorted_listing"
    rm -f "$listing" "$sorted_listing"
    for item in "${items[@]}"; do
        if ! type="$(stat -c '%F' -- "$item")" || ! mode="$(stat -c '%a' -- "$item")"; then
            echo "❌ could not inspect tracked state: $item" >&2
            return 1
        fi
        link="-"
        hash="-"
        if [[ -L "$item" ]] && ! link="$(readlink -- "$item")"; then
            echo "❌ could not read tracked symlink: $item" >&2
            return 1
        fi
        if [[ -f "$item" && ! -L "$item" ]]; then
            if ! hash_output="$(sha256sum -- "$item")"; then
                echo "❌ could not hash tracked state: $item" >&2
                return 1
            fi
            hash="${hash_output%% *}"
        fi
        printf '%s|%s|%s|%s|%s\n' "$item" "$type" "$mode" "$link" "$hash"
    done
}

snapshot_state() {
    local out="$1"
    local configured_path expanded_path packages package_listing
    local -a configured_paths=()
    {
        echo "## dpkg"
        if ! packages=$(dpkg-query -W -f='${Package} ${Version}\n' 2>&1); then
            echo "❌ could not query installed package state" >&2
            return 1
        fi
        package_listing=$(mktemp)
        if ! printf '%s\n' "$packages" > "$package_listing"; then
            echo "❌ could not stage installed package state" >&2
            rm -f "$package_listing"
            return 1
        fi
        if ! sort "$package_listing"; then
            echo "❌ could not sort installed package state" >&2
            rm -f "$package_listing"
            return 1
        fi
        rm -f "$package_listing"
        snapshot_path "$HOME/.bashrc" || return
        snapshot_path "$HOME/.zshrc" || return
        snapshot_path "$HOME/.profile" || return
        snapshot_path "$HOME/.local/bin" || return
        if [[ -n "${STATE_PATHS:-}" ]]; then
            IFS=',' read -r -a configured_paths <<< "$STATE_PATHS"
            for configured_path in "${configured_paths[@]}"; do
                expanded_path="${configured_path//\$HOME/$HOME}"
                expanded_path="${expanded_path//\$\{HOME\}/$HOME}"
                case "$expanded_path" in
                    "$HOME"/*|/etc/*|/opt/*|/usr/local/*|/var/lib/*) ;;
                    *) echo "❌ unsafe manifest state path: $configured_path" >&2; return 2 ;;
                esac
                [[ "$expanded_path" != *'/../'* && "$expanded_path" != */.. ]] || {
                    echo "❌ unsafe manifest state path: $configured_path" >&2
                    return 2
                }
                snapshot_path "$expanded_path" || return
            done
        fi
    } > "$out"
}

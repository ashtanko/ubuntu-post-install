#!/bin/bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

bash tests/config-regression.sh
bash tests/catalog-regression.sh
bash tests/tui-launcher-regression.sh
bash tests/runtime-core-regression.sh
bash tests/installer-regression.sh
bash tests/release-metadata-regression.sh
bash tests/idempotency-regression.sh

for docker_args in \
    '25.04 smoke' \
    '24.04 invalid' \
    '24.04 smoke does/not-exist.sh'; do
    read -r -a parsed_docker_args <<< "$docker_args"
    set +e
    bash tests/run-in-docker.sh "${parsed_docker_args[@]}" >/dev/null 2>&1
    status=$?
    set -e
    if [[ "$status" -ne 2 ]]; then
        echo "❌ Docker preflight returned $status instead of 2 for: $docker_args"
        exit 1
    fi
done

if grep -REn --include='*.sh' 'set -a;[[:space:]]*(source|\.)[[:space:]].*\.env|set -a;[[:space:]]*source' \
    setup.sh ai apps dev essentials ide software system tools vpn; then
    echo "❌ legacy config loader still exports configuration to child processes"
    exit 1
fi

mapfile -t configured_scripts < <(find ai apps dev essentials ide software system tools vpn \
    -maxdepth 1 -type f -name '*.sh' | sort)
for configured_script in "${configured_scripts[@]}"; do
    # The repository-root token is intentionally matched literally.
    # shellcheck disable=SC2016
    grep -q 'load_config "\$REPO_ROOT"' "$configured_script" || {
        echo "❌ production script bypasses the shared config loader: $configured_script"
        exit 1
    }
done

echo "✅ all local regression checks passed"

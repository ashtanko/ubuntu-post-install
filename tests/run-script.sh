#!/bin/bash
# Run inside the test container. Executes one script per invocation, then
# verifies it. In `idempotency` mode, runs twice and diffs state.
set -uo pipefail

if [ -z "${BASH_VERSION:-}" ]; then
    exec /bin/bash "$0" "$@"
fi

SCRIPT_PATH="${MANIFEST_SCRIPT:?MANIFEST_SCRIPT required}"
ENV_PAIRS="${MANIFEST_ENV:-}"
VERIFY_CMD="${MANIFEST_VERIFY:-}"
MODE="${MANIFEST_MODE:-smoke}"
STATE_PATHS="${MANIFEST_STATE_PATHS:-}"

# Stage repo into a writable location (container mount may be read-only)
WORK="$HOME/work"
rm -rf "$WORK"
cp -r /home/tester/repo "$WORK"
cd "$WORK" || { echo "❌ cd $WORK failed"; exit 1; }

# shellcheck source=tests/idempotency-lib.bash
source "$WORK/tests/idempotency-lib.bash"

# Drop in CI .env (overrides anything in tests/fixtures)
cp tests/fixtures/test.env .env

# Build env-pair args for `env`
declare -a ENV_ARGS=()
if [ -n "$ENV_PAIRS" ]; then
    IFS=',' read -ra pairs <<<"$ENV_PAIRS"
    for kv in "${pairs[@]}"; do
        [[ "$kv" == *=* ]] || { echo "❌ invalid manifest env entry: $kv"; exit 2; }
        key="${kv%%=*}"
        value="${kv#*=}"
        [[ "$key" =~ ^[a-zA-Z_][a-zA-Z0-9_]*$ ]] || { echo "❌ invalid manifest env name: $key"; exit 2; }
        value="${value//\$HOME/$HOME}"
        value="${value//\$\{HOME\}/$HOME}"
        kv_expanded="$key=$value"
        ENV_ARGS+=("$kv_expanded")
    done
fi

run_script() {
    local label="$1" log="$2"
    echo "▶️  [$label] $SCRIPT_PATH"
    if [ "${#ENV_ARGS[@]}" -gt 0 ]; then
        env "${ENV_ARGS[@]}" bash "$SCRIPT_PATH" 2>&1 | tee "$log"
    else
        bash "$SCRIPT_PATH" 2>&1 | tee "$log"
    fi
    return "${PIPESTATUS[0]}"
}

run_verify() {
    if [ -z "$VERIFY_CMD" ]; then
        return 0
    fi
    local file_verify
    if [ "$VERIFY_CMD" = "FILE" ]; then
        file_verify="$WORK/tests/verify/$(echo "$SCRIPT_PATH" | tr '/' '_')"
        if [ ! -f "$file_verify" ]; then
            echo "❌ verify=FILE but $file_verify does not exist"
            return 1
        fi
        bash "$file_verify"
    else
        bash -c "$VERIFY_CMD"
    fi
}

LOG1=/tmp/run1.log
LOG2=/tmp/run2.log
SNAP1=/tmp/snap1.txt
SNAP2=/tmp/snap2.txt

if ! run_script "run-1" "$LOG1"; then
    echo "❌ FIRST RUN FAILED: $SCRIPT_PATH"
    exit 1
fi

if ! run_verify; then
    echo "❌ VERIFY FAILED: $SCRIPT_PATH"
    exit 1
fi

if [ "$MODE" = "smoke" ]; then
    echo "✅ SMOKE OK: $SCRIPT_PATH"
    exit 0
fi

# idempotency mode
if ! snapshot_state "$SNAP1"; then
    echo "❌ FIRST STATE SNAPSHOT FAILED: $SCRIPT_PATH"
    exit 1
fi

if ! run_script "run-2" "$LOG2"; then
    echo "❌ SECOND RUN FAILED (idempotency): $SCRIPT_PATH"
    exit 1
fi

if ! run_verify; then
    echo "❌ VERIFY AFTER SECOND RUN FAILED: $SCRIPT_PATH"
    exit 1
fi

if ! snapshot_state "$SNAP2"; then
    echo "❌ SECOND STATE SNAPSHOT FAILED: $SCRIPT_PATH"
    exit 1
fi

if ! diff -u "$SNAP1" "$SNAP2"; then
    echo "❌ STATE CHANGED ON RE-RUN: $SCRIPT_PATH"
    exit 1
fi

echo "✅ IDEMPOTENCY OK: $SCRIPT_PATH"

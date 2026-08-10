#!/bin/bash
set -euo pipefail

# Re-exec under bash if invoked via `sh` (dash mishandles &>, [[ ]], etc.)
if [ -z "${BASH_VERSION:-}" ]; then
    exec /bin/bash "$0" "$@"
fi

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONFIG_HELPER="$REPO_ROOT/lib/config.bash"
# shellcheck source=lib/config.bash
source "$CONFIG_HELPER" || { echo "❌ Missing config helper: $CONFIG_HELPER" >&2; exit 1; }
load_config "$REPO_ROOT"

echo "🚀 Pulling configured Ollama models..."

if ! command -v ollama &>/dev/null; then
    echo "❌ Ollama is required. Run ai/ollama.sh first." >&2
    exit 1
fi

if [ -z "${OLLAMA_MODELS:-}" ]; then
    echo "❌ OLLAMA_MODELS is empty." >&2
    echo "💡 Set a whitespace-separated list, for example: OLLAMA_MODELS=\"qwen3:4b nomic-embed-text\"" >&2
    exit 2
fi

run_ollama() {
    if [ -n "${OLLAMA_HOST:-}" ]; then
        OLLAMA_HOST="$OLLAMA_HOST" ollama "$@"
    else
        ollama "$@"
    fi
}

if ! INSTALLED_OUTPUT=$(run_ollama list 2>&1); then
    echo "❌ Could not query Ollama. Ensure the Ollama service is running." >&2
    echo "$INSTALLED_OUTPUT" >&2
    exit 1
fi
INSTALLED_MODELS=$(printf '%s\n' "$INSTALLED_OUTPUT" | awk 'NR > 1 { print $1 }')

NORMALIZED_MODELS=${OLLAMA_MODELS//$'\n'/ }
read -r -a MODELS <<< "$NORMALIZED_MODELS"
declare -A SEEN=()

for MODEL in "${MODELS[@]}"; do
    if [[ ! "$MODEL" =~ ^[[:alnum:]][[:alnum:]./_:+-]*$ ]]; then
        echo "❌ Invalid Ollama model reference: $MODEL" >&2
        exit 2
    fi
    if [ -n "${SEEN[$MODEL]:-}" ]; then
        continue
    fi
    SEEN["$MODEL"]=1

    MODEL_REF="$MODEL"
    [[ "$MODEL_REF" == *:* ]] || MODEL_REF="${MODEL_REF}:latest"
    if printf '%s\n' "$INSTALLED_MODELS" | grep -Fxq -- "$MODEL_REF"; then
        echo "✅ $MODEL already available"
        continue
    fi

    echo "📥 Pulling $MODEL..."
    run_ollama pull "$MODEL"
done

echo "✅ Configured Ollama models are available"

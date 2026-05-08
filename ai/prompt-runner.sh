#!/bin/bash
set -euo pipefail

# Re-exec under bash if invoked via `sh` (dash mishandles &>, [[ ]], etc.)
if [ -z "${BASH_VERSION:-}" ]; then
    exec /bin/bash "$0" "$@"
fi

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
[[ -f "$REPO_ROOT/.env" ]] && { set -a; source "$REPO_ROOT/.env"; set +a; }

# This installer drops a `prompt` command into ~/.local/bin that runs a text
# (.prompt or any text) file against a configured backend: ollama (default),
# openai, or anthropic. Backends pull keys/host from .env at runtime.
#
# Usage after install:
#   prompt path/to/file.prompt                 # use $PROMPT_BACKEND
#   prompt -b openai  path/to/file.prompt      # override backend
#   prompt -m llama3.2 path/to/file.prompt     # override model
#   echo "hi" | prompt                         # read from stdin

echo "🚀 Installing prompt-runner..."

BIN_DIR="$HOME/.local/bin"
BIN="$BIN_DIR/prompt"
mkdir -p "$BIN_DIR"

cat > "$BIN" <<'RUNNER'
#!/bin/bash
set -euo pipefail

PROMPT_RUNNER_REPO="__REPO_ROOT__"
if [ -n "${PROMPT_RUNNER_REPO:-}" ] && [ "$PROMPT_RUNNER_REPO" != "__REPO_ROOT__" ] && [ -f "$PROMPT_RUNNER_REPO/.env" ]; then
    set -a; source "$PROMPT_RUNNER_REPO/.env"; set +a
fi

usage() {
    cat <<EOF
prompt — run a text/.prompt file against an LLM backend

Usage: prompt [-b BACKEND] [-m MODEL] [FILE]
       echo "..." | prompt [-b BACKEND] [-m MODEL]

Backends (set via -b or \$PROMPT_BACKEND):
  ollama     local Ollama at \$OLLAMA_HOST (default http://localhost:11434)
  openai     OpenAI Chat Completions, requires \$OPENAI_API_KEY
  anthropic  Anthropic Messages,        requires \$ANTHROPIC_API_KEY

Defaults can be set in .env: PROMPT_BACKEND, PROMPT_MODEL, OLLAMA_HOST.
EOF
    exit "${1:-0}"
}

BACKEND="${PROMPT_BACKEND:-ollama}"
MODEL="${PROMPT_MODEL:-}"
while getopts "b:m:h" opt; do
    case "$opt" in
        b) BACKEND="$OPTARG" ;;
        m) MODEL="$OPTARG" ;;
        h) usage 0 ;;
        *) usage 1 ;;
    esac
done
shift $((OPTIND - 1))

FILE="${1:-}"
if [ -n "$FILE" ] && [ ! -f "$FILE" ]; then
    echo "❌ File not found: $FILE" >&2
    exit 1
fi
if [ -n "$FILE" ]; then
    BODY="$(cat -- "$FILE")"
else
    if [ -t 0 ]; then usage 1; fi
    BODY="$(cat)"
fi

case "$BACKEND" in
    ollama)
        : "${OLLAMA_HOST:=http://localhost:11434}"
        : "${MODEL:=llama3.2}"
        curl -fsSL "$OLLAMA_HOST/api/generate" \
            -H "Content-Type: application/json" \
            --data "$(jq -n --arg m "$MODEL" --arg p "$BODY" \
                '{model:$m, prompt:$p, stream:false}')" \
        | jq -r '.response'
        ;;
    openai)
        : "${OPENAI_API_KEY:?OPENAI_API_KEY not set in environment / .env}"
        : "${MODEL:=gpt-4o-mini}"
        curl -fsSL https://api.openai.com/v1/chat/completions \
            -H "Authorization: Bearer $OPENAI_API_KEY" \
            -H "Content-Type: application/json" \
            --data "$(jq -n --arg m "$MODEL" --arg p "$BODY" \
                '{model:$m, messages:[{role:"user", content:$p}]}')" \
        | jq -r '.choices[0].message.content'
        ;;
    anthropic)
        : "${ANTHROPIC_API_KEY:?ANTHROPIC_API_KEY not set in environment / .env}"
        : "${MODEL:=claude-opus-4-7}"
        curl -fsSL https://api.anthropic.com/v1/messages \
            -H "x-api-key: $ANTHROPIC_API_KEY" \
            -H "anthropic-version: 2023-06-01" \
            -H "Content-Type: application/json" \
            --data "$(jq -n --arg m "$MODEL" --arg p "$BODY" \
                '{model:$m, max_tokens:4096, messages:[{role:"user", content:$p}]}')" \
        | jq -r '.content[0].text'
        ;;
    *)
        echo "❌ Unknown backend: $BACKEND" >&2
        usage 1
        ;;
esac
RUNNER

chmod +x "$BIN"

# Substitute the repo path placeholder so the runner can find .env
# without hardcoding (use | as delimiter — REPO_ROOT may contain /)
sed -i "s|__REPO_ROOT__|$REPO_ROOT|" "$BIN"

# Sanity-check dependencies the runner needs
NEEDS_APT_UPDATE=1
for dep in curl jq; do
    if ! command -v "$dep" &>/dev/null; then
        if [ "$NEEDS_APT_UPDATE" = "1" ]; then
            sudo apt-get update
            NEEDS_APT_UPDATE=0
        fi
        echo "📦 Installing missing dep: $dep"
        sudo apt-get install -y "$dep"
    fi
done

# Ensure ~/.local/bin is on PATH (idempotent).
# Single quotes are intentional — `$HOME` / `$PATH` must be literal in the rc file.
# shellcheck disable=SC2016
PATH_LINE='[ -d "$HOME/.local/bin" ] && case ":$PATH:" in *":$HOME/.local/bin:"*) ;; *) export PATH="$HOME/.local/bin:$PATH";; esac'
for RC in "$HOME/.zshrc" "$HOME/.bashrc"; do
    # shellcheck disable=SC2016
    if [ -f "$RC" ] && ! grep -qF '$HOME/.local/bin' "$RC"; then
        {
            echo ""
            echo "# ~/.local/bin (added by prompt-runner.sh)"
            echo "$PATH_LINE"
        } >> "$RC"
        echo "✅ Added \$HOME/.local/bin to PATH in $RC"
    fi
done

echo ""
echo "✅ Installed: $BIN"
echo "💡 Try it:"
echo "     echo 'Why is the sky blue?' | prompt"
echo "     prompt -b anthropic some.prompt"

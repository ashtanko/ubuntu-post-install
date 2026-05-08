#!/bin/bash
set -euo pipefail

# Re-exec under bash if invoked via `sh` (dash mishandles &>, [[ ]], etc.)
if [ -z "${BASH_VERSION:-}" ]; then
    exec /bin/bash "$0" "$@"
fi

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
[[ -f "$REPO_ROOT/.env" ]] && { set -a; source "$REPO_ROOT/.env"; set +a; }

echo "🚀 Building llama.cpp from source..."

LLAMA_CPP_DIR="${LLAMA_CPP_DIR:-$HOME/.local/src/llama.cpp}"
LLAMA_CPP_BIN="$HOME/.local/bin"

# Skip if already built and on PATH
if command -v llama-cli &>/dev/null && [ -d "$LLAMA_CPP_DIR" ]; then
    echo "✅ llama.cpp already installed ($(llama-cli --version 2>/dev/null | head -1 || echo 'unknown'))"
    echo "💡 Update with: cd $LLAMA_CPP_DIR && git pull && cmake --build build --config Release -j"
    exit 0
fi

echo "📦 Installing build dependencies..."
sudo apt update
sudo apt install -y build-essential cmake git ccache pkg-config libcurl4-openssl-dev

# Clone or update
mkdir -p "$(dirname "$LLAMA_CPP_DIR")"
if [ -d "$LLAMA_CPP_DIR/.git" ]; then
    echo "📥 Updating existing checkout..."
    git -C "$LLAMA_CPP_DIR" pull --ff-only
else
    echo "📥 Cloning ggml-org/llama.cpp..."
    git clone --depth 1 https://github.com/ggml-org/llama.cpp.git "$LLAMA_CPP_DIR"
fi

# Build (CPU-only by default; user can rebuild with -DGGML_CUDA=ON later)
echo "🔨 Configuring CMake build..."
cmake -S "$LLAMA_CPP_DIR" -B "$LLAMA_CPP_DIR/build" \
    -DCMAKE_BUILD_TYPE=Release \
    -DLLAMA_CURL=ON

echo "🔨 Compiling (this takes a few minutes)..."
cmake --build "$LLAMA_CPP_DIR/build" --config Release -j "$(nproc)"

# Symlink the most useful binaries into ~/.local/bin
mkdir -p "$LLAMA_CPP_BIN"
for tool in llama-cli llama-server llama-quantize llama-bench; do
    SRC="$LLAMA_CPP_DIR/build/bin/$tool"
    if [ -x "$SRC" ]; then
        ln -sf "$SRC" "$LLAMA_CPP_BIN/$tool"
        echo "🔗 Linked $tool → $LLAMA_CPP_BIN/$tool"
    fi
done

# Ensure ~/.local/bin is on PATH (idempotent)
PATH_LINE='[ -d "$HOME/.local/bin" ] && case ":$PATH:" in *":$HOME/.local/bin:"*) ;; *) export PATH="$HOME/.local/bin:$PATH";; esac'
for RC in "$HOME/.zshrc" "$HOME/.bashrc"; do
    if [ -f "$RC" ] && ! grep -qF '$HOME/.local/bin' "$RC"; then
        echo "" >> "$RC"
        echo "# ~/.local/bin (added by llama-cpp.sh)" >> "$RC"
        echo "$PATH_LINE" >> "$RC"
        echo "✅ Added \$HOME/.local/bin to PATH in $RC"
    fi
done

echo ""
echo "✅ llama.cpp built and linked."
echo "💡 Try a model:"
echo "     llama-server -hf Qwen/Qwen2.5-0.5B-Instruct-GGUF"
echo "💡 To rebuild with GPU support:"
echo "     cmake -S $LLAMA_CPP_DIR -B $LLAMA_CPP_DIR/build -DGGML_CUDA=ON"
echo "     cmake --build $LLAMA_CPP_DIR/build --config Release -j"

#!/bin/bash
set -euo pipefail

# Re-exec under bash if invoked via `sh` (dash mishandles &>, [[ ]], etc.)
if [ -z "${BASH_VERSION:-}" ]; then
    exec /bin/bash "$0" "$@"
fi

# Check if a directory was provided
if [ -z "${1:-}" ]; then
    echo "Usage: $0 <path_to_flutter_plugin> [output_filename.zip]"
    exit 1
fi

PLUGIN_PATH=$1
OUTPUT_ZIP=${2:-"plugin_distribution.zip"}

# Convert output path to absolute so it doesn't get messed up after 'cd'
OUTPUT_PATH=$(realpath "$OUTPUT_ZIP")

# Move into the plugin directory
cd "$PLUGIN_PATH" || { echo "Directory not found"; exit 1; }

echo "📦 Archiving Flutter plugin from: $(pwd)"

# Create the zip archive
# -r: recursive
# -x: exclude patterns
zip -r "$OUTPUT_PATH" . -x \
    "build/*" \
    "*/build/*" \
    ".dart_tool/*" \
    "*/.dart_tool/*" \
    ".git/*" \
    ".idea/*" \
    ".vscode/*" \
    "*.iml" \
    ".pub-cache/*" \
    "pubspec.lock" \
    "android/.gradle/*" \
    "android/local.properties" \
    "ios/.symlinks/*" \
    "ios/Pods/*" \
    "ios/Podfile.lock" \
    ".DS_Store"

echo "✅ Archive created at: $OUTPUT_PATH"
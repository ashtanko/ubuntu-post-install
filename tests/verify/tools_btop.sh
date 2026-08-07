#!/bin/bash
set -euo pipefail
command -v btop >/dev/null || { echo "❌ missing: btop"; exit 1; }

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

echo "🚀 Installing Trivy (container + filesystem vulnerability scanner)..."

if command -v trivy &>/dev/null; then
    echo "✅ Trivy already installed ($(trivy --version 2>/dev/null | head -1))"
    exit 0
fi

ARCH=$(dpkg --print-architecture)
KEYRING=/etc/apt/keyrings/trivy.gpg
SOURCE_LIST=/etc/apt/sources.list.d/trivy.list

echo "📦 Adding Trivy apt repository..."
sudo apt-get update
sudo apt-get install -y ca-certificates curl gnupg

sudo install -m 0755 -d /etc/apt/keyrings
curl -fsSL --retry 3 --retry-all-errors https://get.trivy.dev/deb/public.key \
    | sudo gpg --dearmor --yes -o "$KEYRING"
sudo chmod a+r "$KEYRING"

# Deliberately the release-independent `generic` suite rather than the Ubuntu
# codename: Trivy publishes codename suites too, but not for every release
# (25.04/plucky has none), and pointing apt at a suite upstream never published
# breaks every later `apt-get update` with a 404 — exactly the failure that the
# ondrej/php PPA caused in dev/php.sh.
echo "deb [arch=${ARCH} signed-by=${KEYRING}] https://get.trivy.dev/deb generic main" \
    | sudo tee "$SOURCE_LIST" > /dev/null

sudo apt-get update
sudo apt-get install -y trivy

if ! command -v trivy &>/dev/null; then
    echo "❌ Trivy installation failed or is not in PATH"
    exit 1
fi

echo ""
echo "✅ Trivy installed ($(trivy --version 2>/dev/null | head -1))"
echo "💡 Scan a container image:      trivy image <image>"
echo "💡 Scan this working tree:      trivy fs ."
echo "💡 Scan IaC (Terraform, k8s):   trivy config ."
echo "💡 Fail only on real problems:  trivy image --severity HIGH,CRITICAL --exit-code 1 <image>"
echo "💡 First run downloads the vulnerability DB (~several hundred MB)"

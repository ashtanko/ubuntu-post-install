#!/bin/bash
set -euo pipefail

# Re-exec under bash if invoked via `sh` (dash mishandles &>, [[ ]], etc.)
if [ -z "${BASH_VERSION:-}" ]; then
    exec /bin/bash "$0" "$@"
fi

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
[[ -f "$REPO_ROOT/.env" ]] && { set -a; source "$REPO_ROOT/.env"; set +a; }

echo "🚀 Preparing prerequisites for VMware Workstation..."

# VMware Workstation Pro is now free for personal use but distributed as a
# bundle from Broadcom that requires manual download + sign-in. This script
# only installs the kernel build prereqs needed for the .bundle installer.

echo "📦 Installing kernel headers and build tools..."
sudo apt update
sudo apt install -y build-essential "linux-headers-$(uname -r)"

cat <<'EOF'

✅ Prerequisites installed.

Manual next steps:
  1. Sign in at https://support.broadcom.com/ and download
     "VMware Workstation Pro for Personal Use" (.bundle).
  2. Run:    chmod +x VMware-Workstation-Full-*.bundle
             sudo ./VMware-Workstation-Full-*.bundle
  3. Launch via the application menu the first time so it can compile its
     kernel modules against the headers we just installed.

💡 If kernel modules fail to build after a kernel upgrade, re-run this script
   to refresh the headers, then run:  sudo vmware-modconfig --console --install-all
EOF

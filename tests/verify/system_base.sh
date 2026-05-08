#!/bin/bash
set -euo pipefail
for pkg in build-essential git curl wget; do
    dpkg -s "$pkg" >/dev/null
done
git config --global --get user.email | grep -q '@'

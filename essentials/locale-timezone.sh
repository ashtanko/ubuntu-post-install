#!/bin/bash
set -euo pipefail

# Re-exec under bash if invoked via `sh` (dash mishandles &>, [[ ]], etc.)
if [ -z "${BASH_VERSION:-}" ]; then
    exec /bin/bash "$0" "$@"
fi

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
[[ -f "$REPO_ROOT/.env" ]] && { set -a; source "$REPO_ROOT/.env"; set +a; }

echo "🚀 Configuring locale and timezone..."

DESIRED_LOCALE="${LOCALE:-en_US.UTF-8}"
DESIRED_TZ="${TZ:-}"

# Detect whether systemd is the active init (timedatectl/localectl need it).
HAVE_SYSTEMD=0
[ -d /run/systemd/system ] && HAVE_SYSTEMD=1

# ── Timezone ──────────────────────────────────────────────────────────────────
if [ "$HAVE_SYSTEMD" = "1" ]; then
    CURRENT_TZ=$(timedatectl show -p Timezone --value 2>/dev/null || echo "")
else
    CURRENT_TZ=$(readlink -f /etc/localtime 2>/dev/null | sed 's|^/usr/share/zoneinfo/||' || echo "")
fi

if [ -z "$DESIRED_TZ" ]; then
    echo "🔍 No TZ set in .env — auto-detecting from public IP..."
    DESIRED_TZ=$(curl -fsSL --max-time 5 https://ipapi.co/timezone 2>/dev/null || echo "")
fi

if [ -z "$DESIRED_TZ" ]; then
    echo "⚠️  Could not determine timezone — leaving current value ($CURRENT_TZ)"
elif [ "$DESIRED_TZ" = "$CURRENT_TZ" ]; then
    echo "✅ Timezone already $CURRENT_TZ"
elif [ ! -f "/usr/share/zoneinfo/$DESIRED_TZ" ]; then
    echo "❌ Unknown timezone: $DESIRED_TZ"
    exit 1
elif [ "$HAVE_SYSTEMD" = "1" ]; then
    echo "🔧 Setting timezone to $DESIRED_TZ..."
    sudo timedatectl set-timezone "$DESIRED_TZ"
    echo "✅ Timezone set"
else
    echo "🔧 Setting timezone to $DESIRED_TZ (no systemd — using /etc/localtime)..."
    sudo ln -sf "/usr/share/zoneinfo/$DESIRED_TZ" /etc/localtime
    echo "$DESIRED_TZ" | sudo tee /etc/timezone >/dev/null
    echo "✅ Timezone set"
fi

# ── Locale ────────────────────────────────────────────────────────────────────
if locale -a 2>/dev/null | grep -qiE "^${DESIRED_LOCALE//-/}$|^${DESIRED_LOCALE}$"; then
    echo "✅ Locale $DESIRED_LOCALE already generated"
else
    echo "📦 Ensuring locales package + generating $DESIRED_LOCALE..."
    sudo apt install -y locales
    sudo locale-gen "$DESIRED_LOCALE"
fi

if [ "$HAVE_SYSTEMD" = "1" ]; then
    CURRENT_LANG=$(localectl status 2>/dev/null | awk -F= '/LANG=/{print $2}' | head -1 || echo "")
    if [ "$CURRENT_LANG" = "$DESIRED_LOCALE" ]; then
        echo "✅ System locale already $DESIRED_LOCALE"
    else
        echo "🔧 Setting system locale to $DESIRED_LOCALE..."
        sudo localectl set-locale "LANG=$DESIRED_LOCALE"
    fi
else
    echo "🔧 Setting system locale to $DESIRED_LOCALE (no systemd — writing /etc/default/locale)..."
    echo "LANG=$DESIRED_LOCALE" | sudo tee /etc/default/locale >/dev/null
fi

echo ""
echo "✅ Locale/timezone configured:"
if [ "$HAVE_SYSTEMD" = "1" ]; then
    timedatectl | sed 's/^/   /'
else
    echo "   Timezone: $(readlink -f /etc/localtime 2>/dev/null | sed 's|^/usr/share/zoneinfo/||')"
    echo "   Locale:   $(head -1 /etc/default/locale 2>/dev/null)"
fi
echo "💡 New shells will pick up the locale; existing ones keep the old LANG."

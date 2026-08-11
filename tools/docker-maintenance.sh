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

# One-shot Docker disk-reclaim pass. Safe to run repeatedly.
#
# tools/system-maintenance.sh runs a plain `docker system prune -f` as one step
# of a whole-machine sweep. This script is the Docker-only counterpart: it
# reports what is actually using space, prunes each resource class separately,
# and keeps the destructive options opt-in.

echo "🚀 Docker maintenance pass..."

PRUNE_IMAGES="${DOCKER_PRUNE_IMAGES:-dangling}"
PRUNE_VOLUMES="${DOCKER_PRUNE_VOLUMES:-no}"
PRUNE_UNTIL="${DOCKER_PRUNE_UNTIL:-168h}"

case "$PRUNE_IMAGES" in
    dangling|all) ;;
    *) echo "❌ DOCKER_PRUNE_IMAGES must be 'dangling' or 'all' (got '$PRUNE_IMAGES')"; exit 1 ;;
esac
case "$PRUNE_VOLUMES" in
    yes|no) ;;
    *) echo "❌ DOCKER_PRUNE_VOLUMES must be 'yes' or 'no' (got '$PRUNE_VOLUMES')"; exit 1 ;;
esac

# Nothing to clean up is a successful outcome, not a failure — this script is
# wired into the installer menu and may run on a machine without Docker.
if ! command -v docker &>/dev/null; then
    echo "⏭️  Docker is not installed — nothing to prune"
    echo "💡 Install it with: bash dev/docker.sh"
    exit 0
fi

if ! docker info &>/dev/null; then
    echo "⏭️  Docker daemon is not reachable — nothing to prune"
    echo "💡 Start it with: sudo systemctl start docker"
    echo "   (or, for a rootless install: systemctl --user start docker)"
    exit 0
fi

echo ""
echo "📊 Before:"
docker system df | sed 's/^/   /'

echo ""
echo "🐳 Removing stopped containers older than $PRUNE_UNTIL..."
docker container prune -f --filter "until=$PRUNE_UNTIL" || true

echo ""
echo "🌐 Removing unused networks older than $PRUNE_UNTIL..."
docker network prune -f --filter "until=$PRUNE_UNTIL" || true

echo ""
if [[ "$PRUNE_IMAGES" == "all" ]]; then
    # -a drops every image not referenced by a container, not just the
    # untagged layers, so the next build re-pulls its bases.
    echo "🖼️  Removing all images unused for $PRUNE_UNTIL (DOCKER_PRUNE_IMAGES=all)..."
    docker image prune -af --filter "until=$PRUNE_UNTIL" || true
else
    echo "🖼️  Removing dangling (untagged) images..."
    docker image prune -f || true
fi

echo ""
echo "🏗️  Removing build cache older than $PRUNE_UNTIL..."
docker builder prune -f --filter "until=$PRUNE_UNTIL" || true

echo ""
if [[ "$PRUNE_VOLUMES" == "yes" ]]; then
    # Opt-in only: an unused volume is still somebody's database.
    echo "💾 Removing unused volumes (DOCKER_PRUNE_VOLUMES=yes)..."
    docker volume prune -f || true
else
    echo "⏭️  Keeping unused volumes — they may hold real data"
    echo "💡 Remove them anyway with: DOCKER_PRUNE_VOLUMES=yes bash tools/docker-maintenance.sh"
fi

echo ""
echo "📊 After:"
docker system df | sed 's/^/   /'

echo ""
echo "✅ Docker maintenance complete!"
echo "💡 Reclaim more aggressively: DOCKER_PRUNE_IMAGES=all bash tools/docker-maintenance.sh"
echo "💡 Change the age cutoff:     DOCKER_PRUNE_UNTIL=24h bash tools/docker-maintenance.sh"
echo "💡 Whole-machine cleanup:     bash tools/system-maintenance.sh"

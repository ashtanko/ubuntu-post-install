# Contributing

Thanks for taking the time to add a script. This guide walks through the conventions and the test wiring so your PR sails through CI.

## Script shape

Every script in this repo follows the same skeleton. Use this as the starting point:

```bash
#!/bin/bash
set -euo pipefail

# Re-exec under bash if invoked via `sh` (dash mishandles &>, [[ ]], etc.)
if [ -z "${BASH_VERSION:-}" ]; then
    exec /bin/bash "$0" "$@"
fi

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONFIG_HELPER="$REPO_ROOT/lib/config.bash"
[[ -r "$CONFIG_HELPER" ]] || { echo "❌ missing config helper: $CONFIG_HELPER" >&2; exit 1; }
# shellcheck source=../lib/config.bash
source "$CONFIG_HELPER"
load_config "$REPO_ROOT"

echo "🚀 Installing <thing>..."

# 1. Idempotency check — early-exit if already done
if command -v <tool> &>/dev/null; then
    echo "✅ <tool> already installed"
    exit 0
fi

# 2. Install
echo "📦 Installing <tool>..."
sudo apt-get update
sudo apt-get install -y <pkg>

# 3. (Optional) PATH or rc-file changes — guarded with grep -q
RC_LINE='export PATH="$HOME/.local/bin:$PATH"'
for RC in "$HOME/.zshrc" "$HOME/.bashrc"; do
    if [ -f "$RC" ] && ! grep -q '\.local/bin' "$RC"; then
        echo "" >> "$RC"
        echo "$RC_LINE" >> "$RC"
        echo "✅ Added <tool> to PATH in $RC"
    fi
done

echo "✅ <tool> setup complete!"
```

Real examples to model on:

- [tools/cli-tools.sh](../tools/cli-tools.sh) — apt-based installs with a per-tool `install_if_missing` helper, plus a tar-release fallback for a tool that isn't in apt.
- [system/ssh.sh](../system/ssh.sh) — file-existence idempotency, env-var fallback to interactive prompt, multi-line rc block guarded by `grep -q`.
- [dev/node.sh](../dev/node.sh) — third-party installer (NVM), `set +u` relaxation when sourcing the vendor's init script, escaped rc block.

## Idempotency

The single hardest rule: **running your script twice on the same machine should succeed both times**, and the second run must not duplicate state. CI enforces this for runnable container-compatible entries in the [idempotency stage](TESTING.md), which diffs configured system state between two runs. `compat=no` scripts need equivalent manual validation and a concrete skip reason.

Cheap and reliable idempotency checks:

| Check | Use when |
|---|---|
| `command -v <tool> &>/dev/null` | Binary on `PATH` |
| `[ -f <file> ]` / `[ -d <dir> ]` | Vendor installer drops a known file |
| `dpkg -s <pkg> &>/dev/null` | Pure apt package |
| `! grep -q <pattern> "$RC"` | Before appending to `~/.zshrc` / `~/.bashrc` |

## `.env` support

If your script needs a config knob, expose it as an env var with a sensible default:

```bash
INSTALL_DIR="${MYTOOL_DIR:-$HOME/.local/share/mytool}"
```

Then add a row to [docs/CONFIG.md](CONFIG.md) and the matching commented-out line to [.env.example](../.env.example).

## Test wiring

Every script in the repo has a row in [tests/manifest.sh](../tests/manifest.sh). CI rejects PRs without one (enforced by `tests/check-manifest-coverage.sh`).

Format:

```
"path|compat|env_vars|verify_cmd|skip_reason|state_paths"
```

| Column | What goes here |
|---|---|
| `path` | Repo-relative path, e.g. `dev/mytool.sh` |
| `compat` | `yes` if it works in a plain Ubuntu container, `partial` if it half-works (note why in `skip_reason`), `no` if it can't run in CI at all |
| `env_vars` | Comma-separated `KEY=VALUE` pairs to seed before the script runs |
| `verify_cmd` | A shell one-liner that exits 0 on success — **or** the literal `FILE` |
| `skip_reason` | Required when `compat` is `no` or `partial` |
| `state_paths` | Optional comma-separated safe paths whose hashes, modes, types, and link targets must remain stable on run two |

Examples:

```
"dev/mytool.sh|yes||command -v mytool|"
"dev/mytool.sh|yes|MYTOOL_DIR=/tmp/mytool|FILE|"
"dev/mytool.sh|no|||needs systemd"
```

If a one-liner verify isn't enough, drop a script at `tests/verify/<category>_<name>.sh` (e.g. `tests/verify/dev_mytool.sh`) and set `verify_cmd` to `FILE`. The verify script runs inside the container after the script under test and should `exit 0` on success.

See [TESTING.md](TESTING.md) for the full harness reference.

## Wire into `setup.sh`

To make your script appear in the interactive menu, add an entry to the matching `*_ITEMS` array near the top of [setup.sh](../setup.sh):

```bash
declare -a DEV_ITEMS=(
    ...
    "My new tool|dev/mytool.sh"
)
```

Keep the label short — the menu wraps on long lines.

## Local checks before opening a PR

```bash
bash tests/lint.sh                                          # shellcheck
bash tests/check-manifest-coverage.sh                       # manifest coverage
bash tests/regression.sh                                    # local behavior regressions
bash tests/run-in-docker.sh 24.04 smoke dev/mytool.sh       # smoke
bash tests/run-in-docker.sh 24.04 idempotency dev/mytool.sh # idempotency
```

If a targeted script is `compat=no`, the runner reports the skip and exits non-zero because no runnable work occurred. Validate that script manually on a suitable host and keep the manifest reason specific.

## CI gates

| Gate | Workflow |
|---|---|
| ShellCheck on every `.sh` / `.bash` file | [lint.yml](../.github/workflows/lint.yml) |
| Manifest schema/coverage + local regressions | [lint.yml](../.github/workflows/lint.yml) |
| Smoke + idempotency × Ubuntu 22.04 / 24.04 / 26.04 | [docker-tests.yml](../.github/workflows/docker-tests.yml) |

[.shellcheckrc](../.shellcheckrc) silences `SC1091` for dynamic shared-helper paths. Other shellcheck warnings should be fixed, not silenced.

## Style

- One script per tool. Don't bundle unrelated tools into a single script.
- Use the emoji legend already in use across the repo: 🚀 start · 📦 installing · ✅ success · ❌ error · ⚠️ warning · 💡 tip · 🔧 configuring · 🔍 detecting.
- No comments that explain *what* the code does — well-named variables and the script's `echo` lines are the documentation. Comments are for *why* (a non-obvious workaround, an upstream quirk).
- Don't add abstractions for hypothetical future scripts. Three similar lines beats a premature helper function.
- Prefer **editing an existing script** over creating a new one when adding a closely related tool.

## License

Contributions are accepted under the project's MIT [LICENSE](../LICENSE).

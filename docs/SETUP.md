# `setup.sh` — How the installer works

[setup.sh](../setup.sh) is an interactive menu wrapped around the same scripts you can also run directly. This page documents the orchestration: input syntax, marker files, log layout, and how to resume after a partial run.

## Flow

1. **Bash re-exec shim** — re-execs under bash if invoked via `sh`, so dash-isms in the menu code don't break.
2. **Configuration is loaded** with precedence `environment > repo .env > ~/.env-ubuntu-post-install`; config-only secrets are not automatically exported to child processes.
3. **Marker directory** is created at `~/.cache/ubuntu-setup/`.
4. **Nine category menus** are printed in order: Essentials → System → Apps → Dev → Tools → IDE → AI → Software → VPN. You select items per category.
5. **Confirmation** — selections are echoed back; press `Y` (default) to proceed, `n` to abort.
6. **Run loop** — each selected script is invoked via `bash`, with stdout+stderr `tee`'d to the log.
7. **Summary** — pass / fail / skipped counts; non-zero exit code if any script failed.

## Menu input

| Input | Effect |
|---|---|
| `1 3 5` | Run items 1, 3, and 5 in this category |
| `a` | Run **all** items |
| `n` or empty | Skip this category |

Invalid numbers are silently ignored. Items with a `✓` next to them already have a marker file and will be skipped during the run loop (you can still select them — they just won't actually run).

## Marker files

Each script has a corresponding marker at `~/.cache/ubuntu-setup/<path>.done`, where `<path>` is the script's repo-relative path with `/` replaced by `_`:

| Script | Marker |
|---|---|
| `dev/node.sh` | `~/.cache/ubuntu-setup/dev_node.sh.done` |
| `essentials/firewall.sh` | `~/.cache/ubuntu-setup/essentials_firewall.sh.done` |
| `tools/cli-tools.sh` | `~/.cache/ubuntu-setup/tools_cli-tools.sh.done` |

A marker is created when the script's exit status is `0`. It's checked at the start of `run_script` — if present, the script is reported as `skipped` and not executed.

> **Markers track invocation success, not the current state of the tool.** If you uninstall Node manually, the `dev_node.sh.done` marker still exists and `setup.sh` will skip the install. Delete the marker to force a re-run.

## Log file

| What | Where |
|---|---|
| Default | `~/ubuntu-setup.log` |
| Override | export `SETUP_LOG_FILE`, or set it in repo `.env` / `~/.env-ubuntu-post-install` |
| Format | `tee -a` of the menu's own messages plus full stdout+stderr of every script run |

Each run header is timestamped with `date '+%Y-%m-%d %H:%M:%S'`. Tail it for the actual error when something fails:

```bash
tail -200 ~/ubuntu-setup.log
```

The log is **appended**, not truncated. Multiple runs accumulate; rotate manually if it grows large.

## Result tracking and summary

Internally, each script lands in a `RESULTS` map with one of three values: `ok`, `failed`, `skipped`. After the loop:

```
✅ 7 succeeded  |  ❌ 1 failed  |  ⏭️  2 skipped
```

If any script reports `failed`, `setup.sh` exits non-zero — useful when wrapping it in another script.

## Resuming and resetting

```bash
# Re-run a single script next time (e.g. you fixed a bug or added env vars)
rm ~/.cache/ubuntu-setup/dev_node.sh.done

# Re-run a category
rm ~/.cache/ubuntu-setup/dev_*.done

# Wipe everything — next setup.sh treats it as a fresh machine
rm -rf ~/.cache/ubuntu-setup/
```

Markers are independent of the log; deleting markers does not erase log history.

## Running scripts standalone

Markers are only consulted by `setup.sh`. Direct invocations ignore them:

```bash
bash dev/node.sh           # runs regardless of marker state
bash tools/cli-tools.sh    # idempotency is enforced inside the script itself
```

Scripts use repeat-safe guards where the underlying operation supports them (for example `command -v node` or `[ -d "$NVM_DIR" ]`). Container-compatible entries are exercised twice by CI; `compat=no` entries require the manual validation documented in their manifest reason.

## Resilience notes

- **Failures don't stop the run loop.** A failed script is logged and reported in the summary; the next selected script still runs.
- **Sudo prompts** happen inside child scripts. If you cancel a sudo prompt, the child script exits non-zero, **no marker is written**, and you can re-run it.
- **Environment variables** set in your shell take precedence over repo `.env` and the stable user config. Inline overrides also work: `SWAP_SIZE_GB=8 bash setup.sh`.
- **Categorical order** matters when scripts depend on each other (e.g. [system/base.sh](../system/base.sh) before [tools/cli-tools.sh](../tools/cli-tools.sh)). The menu is laid out in the recommended order; running it top-to-bottom is the safe default.

See [TROUBLESHOOTING.md](TROUBLESHOOTING.md) for what to do when a step fails.

# Troubleshooting

Common failures and how to recover from them. The full log is at `~/ubuntu-setup.log` (or `$SETUP_LOG_FILE`); start there for the actual error message.

## A script failed mid-run

`setup.sh` doesn't write a marker file when a script fails, so it will be selected again on the next run. Two equivalent recovery paths:

```bash
# Option A — re-run the menu and pick the failed item again
bash setup.sh

# Option B — run the script directly (faster while iterating)
bash dev/node.sh
```

If a *successful* run set the wrong marker (e.g. you fixed an env var and want to re-run cleanly):

```bash
rm ~/.cache/ubuntu-setup/dev_node.sh.done
bash setup.sh
```

See [SETUP.md](SETUP.md) for how marker files map to script paths.

## Marker says done but the tool is broken or missing

Markers track *successful invocation*, not the current state of the system. If you uninstalled a tool manually, or a partial reinstall left it broken:

```bash
rm ~/.cache/ubuntu-setup/<category>_<name>.sh.done
bash <category>/<name>.sh
```

To wipe every marker and start fresh:

```bash
rm -rf ~/.cache/ubuntu-setup/
```

## `[[: not found` or `Bad substitution` when running a script

You ran the script with `sh` instead of `bash`. Every script has a re-exec shim that should catch this — if you still see the error, you're probably running an outdated copy. Always invoke with `bash` explicitly:

```bash
bash setup.sh         # ✅
bash dev/node.sh      # ✅
sh  dev/node.sh       # ❌ — relies on the shim
```

## Sudo prompt cancelled / timed out

The script exits non-zero, no marker is written, and the run loop continues with the next script. Re-run the cancelled one once you're ready:

```bash
sudo -v               # warm up the sudo cache for ~5 minutes
bash setup.sh         # answer the prompt promptly when asked
```

## GPG key generation hangs ("not enough random bytes")

[system/gpg.sh](../system/gpg.sh) uses `gpg --batch --generate-key` when `GIT_NAME` and `GIT_EMAIL` are set. On low-entropy systems (containers, freshly booted VMs), this can stall. Install an entropy daemon and retry:

```bash
sudo apt install -y rng-tools-debian   # or: haveged
bash system/gpg.sh
```

## Shell additions aren't picked up

Several scripts append blocks to `~/.zshrc` and `~/.bashrc` (NVM init, pyenv init, ssh-agent autostart, `GPG_TTY` export, Go/Cargo `PATH`). They take effect in **new** shells. Either:

```bash
source ~/.zshrc        # or ~/.bashrc
```

…or open a new terminal. Group changes (e.g. `docker` group from [dev/docker.sh](../dev/docker.sh)) need a full **log out and log back in**.

## `apt` lock contention

If you see `Could not get lock /var/lib/dpkg/lock-frontend`, another process is using `apt`. Most often it's `unattended-upgrades`:

```bash
sudo systemctl status unattended-upgrades
# wait for it to finish, then re-run
```

## A test verification fails

When `tests/run-script.sh` reports `❌ VERIFY FAILED`, the install ran but the post-check (manifest column or `tests/verify/<file>.sh`) didn't pass. Reproduce in isolation to read the full output:

```bash
bash tests/run-in-docker.sh 24.04 smoke <category>/<name>.sh
```

For idempotency-stage failures (`❌ STATE CHANGED ON RE-RUN`), the script wrote something different on the second invocation — usually a missing `grep -q` guard before appending to an rc file, or a duplicated install step.

## NVM / pyenv / cargo not found in a new shell

Check that the rc-file block was actually written:

```bash
grep -n NVM_DIR  ~/.zshrc
grep -n PYENV    ~/.zshrc
grep -n cargo    ~/.zshrc
```

If a block is missing, the script likely exited before the append step. Re-run with the marker removed (see above). If the block is present but nothing happens on shell start, your shell may be reading a different rc file (e.g. `~/.bash_profile` instead of `~/.bashrc`); add `source ~/.bashrc` to the relevant file.

## `setup.sh` reports "skipped" for an item I want to run

That item already has a marker. Either:

- Delete the marker (`rm ~/.cache/ubuntu-setup/<...>.done`) and re-run `setup.sh`, or
- Run the script directly with `bash <path>`, which ignores markers entirely.

## Still stuck

1. Tail the log: `tail -200 ~/ubuntu-setup.log`.
2. Run the failing script standalone and watch the live output.
3. Check the matching test in [tests/manifest.sh](../tests/manifest.sh) — the `compat` column flags scripts that aren't expected to work in certain environments (e.g. UFW / GNOME / systemd inside a container).

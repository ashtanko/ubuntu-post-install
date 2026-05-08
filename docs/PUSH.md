# Publishing a new release

This page describes how to cut a new versioned release of `ubuntu-post-install`. Releases are git-tag driven — pushing a tag matching `v<major>.<minor>.<patch>` (optionally with a `-suffix`) triggers [.github/workflows/release.yml](../.github/workflows/release.yml), which lints, runs the Docker smoke matrix, builds the artifacts, and publishes a GitHub Release.

## Versioning

We follow [Semantic Versioning](https://semver.org/):

| Bump | When |
|---|---|
| **MAJOR** (`v1.0.0` → `v2.0.0`) | Breaking change to `setup.sh` arguments, marker layout, or `.env` keys |
| **MINOR** (`v1.0.0` → `v1.1.0`) | New script added; new menu category; new `.env` knob |
| **PATCH** (`v1.0.0` → `v1.0.1`) | Bug fix, doc update, idempotency tightening — nothing user-facing changes |
| **Pre-release** (`v1.1.0-rc1`, `v1.1.0-beta.2`) | Try a release without marking it `latest`. Tag still triggers the workflow. |

Tags **must** start with `v` — the workflow regex (`v[0-9]+.[0-9]+.[0-9]+` and `v[0-9]+.[0-9]+.[0-9]+-*`) is strict.

## Pre-flight

Before tagging, confirm the working tree is in a releasable state:

```bash
git checkout main
git pull --ff-only
git status                                # must be clean

bash tests/lint.sh                        # shellcheck on all scripts
bash tests/check-manifest-coverage.sh     # every .sh registered
bash tests/run-in-docker.sh               # local smoke (optional, slow)
```

If you've added or renamed scripts since the last release, double-check that [tests/manifest.sh](../tests/manifest.sh) reflects reality — CI will reject a release that fails the manifest check.

## Cut the release

```bash
TAG=v1.0.0
git tag -a "$TAG" -m "Release $TAG"
git push origin "$TAG"
```

That's it. Within ~5–15 minutes (depending on the Docker matrix), the workflow will:

1. Run shellcheck + manifest coverage.
2. Run the smoke stage on Ubuntu 22.04, 24.04, 25.04, and 26.04 in parallel.
3. Stage `dist/ubuntu-post-install-<semver>/`, `sed`-replace `VERSION="dev"` in `setup.sh` with the tag, write a `VERSION` file.
4. Build `dist/ubuntu-post-install-<semver>.tar.gz`, copy `install.sh` into `dist/`, and generate `dist/SHA256SUMS`.
5. Publish a GitHub Release at `https://github.com/ashtanko/ubuntu-post-install/releases/tag/<tag>` with auto-generated notes (PR titles since the previous tag) and three attached files: the tarball, `install.sh`, and `SHA256SUMS`.

Watch progress at the [Actions tab](https://github.com/ashtanko/ubuntu-post-install/actions/workflows/release.yml).

## Dry-run a release (no tag)

To exercise the build without publishing — useful when changing the workflow itself:

1. Open Actions → **release** → **Run workflow**.
2. Pick a branch and enter a synthetic version (e.g. `0.0.0-dev`).
3. The workflow runs lint + smoke + build, but the final "Create GitHub Release" step is skipped. Built artifacts are uploaded under the workflow run as `release-<semver>` so you can download and inspect them.

## Verifying a published release

After the workflow completes:

```bash
TAG=v1.0.0

# 1. Install via the new install.sh
curl -fsSL "https://github.com/ashtanko/ubuntu-post-install/releases/download/${TAG}/install.sh" | bash

# 2. Confirm the embedded version
~/.local/bin/ubuntu-post-install --version
# → ubuntu-post-install 1.0.0

# 3. Manually verify the checksum
cd /tmp
curl -LO "https://github.com/ashtanko/ubuntu-post-install/releases/download/${TAG}/SHA256SUMS"
curl -LO "https://github.com/ashtanko/ubuntu-post-install/releases/download/${TAG}/ubuntu-post-install-${TAG#v}.tar.gz"
sha256sum -c SHA256SUMS
```

The `latest` redirect (`/releases/latest/download/install.sh`) updates automatically when a non-pre-release tag is pushed.

## Re-running a failed release

If the workflow fails after the tag is already pushed, **don't delete the tag** — fix the bug, push the fix to `main`, then move the tag forward:

```bash
git tag -d v1.0.0                         # delete locally
git push origin :refs/tags/v1.0.0         # delete remotely
git tag -a v1.0.0 -m "Release v1.0.0"     # re-tag at new commit
git push origin v1.0.0
```

This is a force-update of the tag — only safe when no one has pulled the broken release yet. If users may have pulled it, bump to `v1.0.1` instead.

## Yanking a bad release

Releases can't be truly recalled (anyone who downloaded already has the bytes), but you can:

1. Mark the GitHub Release as **draft** or **pre-release** so it stops being `latest`.
2. Push a patch release (`v1.0.1`) with the fix — the install one-liner now resolves to the new version automatically.

## What lives where

| Concern | File |
|---|---|
| Workflow that builds + publishes | [.github/workflows/release.yml](../.github/workflows/release.yml) |
| Version placeholder (replaced at build) | `VERSION="dev"` near the top of [setup.sh](../setup.sh) |
| `--version` flag handler | top of [setup.sh](../setup.sh) |
| Remote installer (downloaded by users) | [install.sh](../install.sh) |
| Build artifacts (gitignored) | `dist/` |

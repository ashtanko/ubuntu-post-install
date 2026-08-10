# Repository automation rules

## Keep the installer catalog synchronized

When adding, renaming, moving, or removing an installation script, update the
installer in the same change.

For every selectable script under `ai/`, `apps/`, `dev/`, `essentials/`, `ide/`,
`software/`, `system/`, `tools/`, or `vpn/`:

1. Add or update its category, user-facing label, and repository-relative path
   in `config/catalog.txt`. This catalog drives both the full-screen terminal UI
   and the classic Bash installer; do not duplicate menu entries elsewhere.
2. Add or update its test metadata in `tests/manifest.sh`.
3. Update `docs/SCRIPTS.md` and any related configuration documentation when
   the visible inventory or supported settings change.
4. Run `bash tests/catalog-regression.sh` and `make check` before considering
   the change complete.

Scripts intentionally excluded from the installer must be documented as manual
utilities and must still have an appropriate `tests/manifest.sh` entry.

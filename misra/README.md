# MISRA config notes

## Real vs. best-effort

- **MISRA C:2012** (`.c`/`.h`): real, via Cppcheck's free `misra.py` addon. Rule numbers
  (e.g. `misra-c2012-15.1`) are genuine.
- **MISRA C++:2008** (`.cpp`/`.hpp`): **best-effort only**, via a curated clang-tidy subset
  (`../.clang-tidy`). Not certified, no real rule numbers — no free tool provides certified
  MISRA C++ coverage (Cppcheck's MISRA C++ addon is Premium/paid; PC-lint Plus, PVS-Studio,
  Helix QAC are all paid; the archived `clang-tidy-misra` project covers ~8% and requires
  patching clang-tidy).

## Licensing

MISRA rule *text* is copyrighted by MISRA/HORIBA MIRA, not redistributed here — findings are
rule-number-only. Buying the standard gets you rule text for deviation records/audits; not
needed for the tools to run.

## Before an audit

Buy Cppcheck Premium, swap the clang-tidy pass in `scripts/lint.sh` for its real MISRA C++
addon. Everything else (exclusions, demo self-test) stays the same.

## Notes

- Excluded dirs: `exclude-paths.txt` — vendor/generated code, skipped by every engine.
- Formatting: `scripts/format.sh check|fix [target...]` (clang-format, Allman, 4-space).
- Pre-commit: `../.pre-commit-config.yaml` auto-formats + lints staged files; set up via
  `scripts/setup.sh` (bootstraps `pre-commit` via `uv` or `pip`).
- Windows: needs Git Bash. `bear` is optional there — use CubeIDE's native
  `compile_commands.json` export instead.
- Windows PATH staleness: `setup.sh` installs tools via winget, but Windows only refreshes
  PATH for *new* processes — an already-open terminal or VSCode window won't see them.
  Close and reopen Git Bash (and restart VSCode) **before** opening the folder, so the
  folder-open "Check tools installed" task doesn't falsely report them as missing. This
  applies to STM32CubeIDE too — it's Eclipse-based and has the same stale-PATH problem
  after installing tools that shell out to the system PATH; restart CubeIDE after
  installing anything that changes it.
- Updating an installed copy: `scripts/update.sh <target-repo>` re-syncs from this repo
  without clobbering local changes — a file that differs from upstream gets a `.new`
  sibling instead of being overwritten. `install.sh` is just this run on an empty target.

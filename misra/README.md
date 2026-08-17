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

- Cppcheck platform: `arm32-wchar_t4.xml` (bundled, cppcheck's own upstream ARM definition)
  — 32-bit int/long/pointer, **unsigned-by-default char** (real ARM EABI behavior, verified
  against arm-none-eabi-gcc's own `__CHAR_UNSIGNED__`/`__SIZEOF_WCHAR_T__` macros). Without
  this, cppcheck defaults to this dev machine's own type sizes, which can both miss real
  bugs (e.g. shift-overflow that's fine on a 64-bit host `long` but UB on a 32-bit one) and
  misjudge signedness-sensitive MISRA checks.
- Excluded dirs: `exclude-paths.txt` — vendor/generated code, skipped by every engine.
- Formatting: `scripts/format.sh check|fix [target...]` (clang-format, Allman, 4-space).
- Pre-commit: `../.pre-commit-config.yaml` auto-formats + lints staged files; set up via
  `scripts/setup.sh` (bootstraps `pre-commit` via `uv` or `pip`).
- Windows: needs Git Bash. `bear` is optional there — use CubeIDE's native
  `compile_commands.json` export instead.
- Windows + WSL both installed: `.vscode/tasks.json`'s Windows overrides point at
  `C:\Program Files\Git\bin\bash.exe` explicitly rather than bare `bash` — if PATH resolves
  `bash` to WSL's launcher instead of Git Bash (common when both are present), a task looks
  like it's running forever and does nothing, since it's operating inside WSL's filesystem,
  not yours. If your Git install lives elsewhere (e.g. a per-user install under
  `%LOCALAPPDATA%\Programs\Git`), update that path in `tasks.json` to match.
- Windows PATH staleness: `setup.sh` installs tools via winget, but Windows only refreshes
  PATH for *new* processes — an already-open terminal or VSCode window won't see them.
  Close and reopen Git Bash (and restart VSCode) **before** opening the folder, so the
  folder-open "Check tools installed" task doesn't falsely report them as missing. This
  applies to STM32CubeIDE too — it's Eclipse-based and has the same stale-PATH problem
  after installing tools that shell out to the system PATH; restart CubeIDE after
  installing anything that changes it.
- Updating an installed copy: `scripts/update.sh <target-repo>` re-syncs from this repo.
  `.vscode/*.json` files deep-merge in place (dicts merge key-by-key, lists merge by
  `label`/`id`/`name` identity where present else concat-dedupe, upstream wins scalar
  conflicts — needs `python3`, already a hard dep via cppcheck's `misra.py` addon); every
  other synced file (scripts/, `.clang-tidy`, CI workflow, etc.) is just overwritten.
  `install.sh` is just this run on an empty target.
- Headers "not found" in clangd even with `compile_commands.json` present: clangd refuses
  to query an arbitrary compiler binary named in `compile_commands.json` for its implicit
  system-include paths (newlib/CMSIS headers like `stdint.h` live there) unless that binary
  is explicitly whitelisted. `.vscode/settings.json` sets
  `--query-driver=**/arm-none-eabi-*` to allow it — without this flag, clangd falls back to
  its own bundled Clang headers, which don't match the ARM toolchain's. Restart the clangd
  language server after this changes (Command Palette → `clangd: Restart language server`).
- `compile_flags.txt` is generated, not shipped (`scripts/gen_compile_flags.sh`, called by
  `setup.sh`) — gitignored, since the correct paths depend on this exact machine's ARM
  toolchain version/location. It's the fallback used before you've run
  `gen_compile_commands.sh` against a real project (or for any file that isn't in that
  project's build). If `arm-none-eabi-g++` is on PATH, it queries GCC directly for its real
  system-include paths (the C++ standard library lives in a CPU/FPU-specific multilib
  subdirectory clang can't guess); if not found, you get CPU/target flags only and standard
  headers (`<cstdint>` etc.) won't resolve until either a standalone ARM toolchain is on
  PATH and you re-run `gen_compile_flags.sh`, or you generate a real `compile_commands.json`
  (which always works, since CubeIDE's own compiler path is embedded in the real build).
- If both `compile_flags.txt` and `compile_commands.json` exist in the same directory,
  clang-tidy/clangd pick `compile_flags.txt` — verified empirically, the opposite of the
  commonly assumed precedence. `gen_compile_commands.sh` deletes `compile_flags.txt` once it
  writes a real `compile_commands.json`, so this never comes up in normal use; it only
  matters if you're debugging why lint results don't seem to reflect the real project.
- CubeIDE's native `compile_commands.json` export sets `"directory"` to the project root, but
  every `-I` flag in `"command"` is relative and was written assuming cwd = the build-config
  dir (`Debug/`) one level below root — that's where the compiler actually ran from.
  clang-tidy/clangd resolve relative `-I` paths against `"directory"` per spec, so as
  exported every relative include silently resolves one level *above* the project and never
  finds a header (verified against a real export). `gen_compile_commands.sh` patches
  `"directory"` to the real build-config folder on every copy — this is automatic, not
  something you need to touch, but explains why a hand-copied CubeIDE export (bypassing
  `gen_compile_commands.sh`) will still show nested/standard-library-style header errors.
- `cppcheck --addon=misra.py` bare-name resolution (cwd, then a folder next to cppcheck's own
  exe) can fail on Windows: winget's Cppcheck installs to `Program Files`, but `PATH` often
  resolves `cppcheck` through an App Execution Alias reparse stub, which breaks the
  exe-relative `addons/` lookup even though the real addon file is sitting right there.
  `lint.sh` resolves the real path itself (`resolve_misra_addon`, checked against common
  Linux/macOS/Windows install locations) and passes it explicitly instead of trusting the
  bare name. Some Windows cppcheck installs genuinely don't ship a working `addons/` folder at
  all (a known upstream issue) — if nothing is found locally, `lint.sh` self-heals by
  downloading `misra.py` + its `misra_9.py` dependency from cppcheck's own upstream repo into
  a gitignored `misra/vendor-addons/` cache.
- `misra.py` is itself a Python script; cppcheck spawns a python interpreter to run it, and its
  own auto-detect (bare `python3` then `python` on `PATH`) can fail inside STM32CubeIDE's
  post-build step specifically — Eclipse's spawned-process `PATH` doesn't necessarily carry the
  same `PATH` your interactive Git Bash shell has (verified against a real CubeIDE build: every
  file bailed out with `Failed to auto detect python`, meaning zero MISRA checks actually ran).
  `lint.sh` resolves a `--addon-python` interpreter itself, preferring `uv python find` — `uv`
  is already a hard dependency (it bootstraps pre-commit) and manages its own Python
  independent of system `PATH`, so it works even on a Windows machine with no bare
  `python3`/`python` on `PATH` at all.
- cppcheck's C pass now uses `--project=compile_commands.json` when one exists, giving it real
  per-file `-I`/`-D` flags from the actual CubeIDE build instead of none at all — without this,
  cppcheck can't resolve a single one of the project's own headers (`"FreeRTOS.h"`, `"main.h"`,
  ...) and spams `missingInclude` for every file, which also fails the build since those count
  toward `--error-exitcode=1`. `--file-filter` restricts analysis to just the already
  exclude-paths-filtered target files (`--project` alone would also pull in every compiled
  HAL/CMSIS/Middlewares file). Any target file not actually present in `compile_commands.json`
  (added since the last build, say) runs in a separate plain pass instead of hard-erroring the
  whole run — that pass falls back to whatever `-I`/`-D` flags it can pull out of
  `compile_flags.txt`, since cppcheck has no native concept of that file and errors on most of
  its other flags (`--target=`, `-mcpu=`, ...) if forwarded as-is.
- `lint.sh` exit codes: `0` clean, `1` real lint findings, `2` the toolchain itself is broken
  (e.g. `misra.py` addon not found) — kept distinct from `1` so a CubeIDE post-build failure
  caused by a misconfigured tool doesn't look identical to one caused by a real MISRA
  violation. cppcheck's own output is scanned for known config-error strings to tell them
  apart, since cppcheck returns the same exit code for both.
- `.clang-tidy`'s `HeaderFilterRegex` is `''` (clang-tidy's real default), not `'.*'` — `'.*'`
  makes clang-tidy also diagnose every transitively-included header (CMSIS, HAL, standard
  library), none of which this project owns or can fix. Empty restricts diagnostics to only
  the exact file passed on the command line; `.hpp` files are still linted since `lint.sh`
  scans them directly as their own targets.

## Showing findings in CubeIDE's own Problems view (no plugin)

Eclipse CDT has a built-in mechanism for exactly this: its GNU Error Parser scans the build
console for `file:line:col: severity: message` lines and turns them into Problems-view
markers — but only for `warning`/`error`/`note`/`info`/`remark`, not cppcheck's own
`style`/`performance`/`portability` severities (which most MISRA findings use, and would
otherwise be silently dropped). `scripts/lint.sh --cubeide` forces cppcheck's output into
`warning:` format for exactly this; clang-tidy's already matches (`WarningsAsErrors` in
`.clang-tidy` makes it print `error:`).

Setup: Project Properties → C/C++ Build → Settings → **Build Steps** tab → Post-build steps
command:
```
"C:\Program Files\Git\bin\bash.exe" "${ProjDirPath}/scripts/lint.sh" --cubeide "${ProjDirPath}"
```
(Linux/macOS: drop the `bash.exe` part, just `"${ProjDirPath}/scripts/lint.sh" --cubeide "${ProjDirPath}"`.)
Confirm the GNU C/C++ Error Parser is enabled under the **Error Parsers** tab (on by default
for managed-build projects). Findings then appear as build warnings/errors after every
build. Note this runs *after* compilation, so a lint finding doesn't block getting a
binary — it just flags the build with an error/warning indicator, same fail-loud behavior
as the rest of this toolchain.

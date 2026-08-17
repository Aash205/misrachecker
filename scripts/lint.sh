#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
MISRA_DIR="$REPO_ROOT/misra"

EXCLUDE_FILE="$MISRA_DIR/exclude-paths.txt"
SUPPRESSIONS_FILE="$MISRA_DIR/suppressions.txt"
CLANG_TIDY_CONFIG="$REPO_ROOT/.clang-tidy"
CPPCHECK_PLATFORM="$MISRA_DIR/arm32-wchar_t4.xml"

# cppcheck's own bare `--addon=misra.py` resolution (cwd, then a folder
# next to its own exe) can fail on Windows: winget's Cppcheck installs to
# Program Files, but PATH often resolves `cppcheck` through an App
# Execution Alias reparse stub, which breaks the exe-relative addons/
# lookup even though the real addon file is right there on disk. Resolve
# it ourselves and pass a full path instead of trusting the bare name.
resolve_misra_addon() {
    local exe_dir candidates=()
    if exe_dir="$(command -v cppcheck 2>/dev/null)"; then
        exe_dir="$(dirname "$exe_dir")"
        candidates+=("$exe_dir/addons/misra.py")
    fi
    candidates+=(
        "/usr/share/cppcheck/addons/misra.py"
        "/usr/local/share/cppcheck/addons/misra.py"
        "/opt/homebrew/share/cppcheck/addons/misra.py"
        "/c/Program Files/Cppcheck/addons/misra.py"
        "C:/Program Files/Cppcheck/addons/misra.py"
        "/c/Program Files (x86)/Cppcheck/addons/misra.py"
        "$MISRA_DIR/vendor-addons/misra.py"
    )
    local c
    for c in "${candidates[@]}"; do
        [ -f "$c" ] && { printf '%s' "$c"; return 0; }
    done
    return 1
}

# Last resort: some cppcheck Windows installs genuinely don't ship a
# working addons/ folder at all -- a known upstream issue (misra.py
# installed without its misra_9.py dependency, or the folder missing
# entirely on some MSI/winget installs). Rather than fail, self-heal by
# fetching misra.py + its misra_9.py dependency from cppcheck's own
# upstream repo into a local, gitignored cache. Best-effort: needs curl
# and network access; if either is unavailable this just falls through
# to the same error as before.
download_misra_addon() {
    local dest_dir="$MISRA_DIR/vendor-addons"
    local base="https://raw.githubusercontent.com/danmar/cppcheck/main/addons"
    command -v curl >/dev/null 2>&1 || return 1
    mkdir -p "$dest_dir"
    if curl -fsSL "$base/misra.py" -o "$dest_dir/misra.py" 2>/dev/null \
        && curl -fsSL "$base/misra_9.py" -o "$dest_dir/misra_9.py" 2>/dev/null; then
        printf '%s' "$dest_dir/misra.py"
        return 0
    fi
    rm -f "$dest_dir/misra.py" "$dest_dir/misra_9.py"
    return 1
}

MISRA_ADDON="misra.py"
if resolved_addon="$(resolve_misra_addon)"; then
    MISRA_ADDON="$resolved_addon"
elif downloaded_addon="$(download_misra_addon)"; then
    echo "misra.py addon not found in any local cppcheck install (known issue on some" >&2
    echo "Windows installs) -- downloaded a copy to $MISRA_DIR/vendor-addons/." >&2
    MISRA_ADDON="$downloaded_addon"
fi

# misra.py is itself a Python script -- cppcheck spawns a python
# interpreter to run it, and its own auto-detect (bare "python3" then
# "python" on PATH) can fail: "Bailing out ... Failed to auto detect
# python". Verified against a real STM32CubeIDE post-build run, where
# Eclipse's spawned-process PATH doesn't carry the same PATH the user's
# interactive Git Bash shell has. uv is already a hard dependency here
# (bootstraps pre-commit) and manages its own Python independent of
# system PATH, so prefer `uv python find` over assuming a bare
# python3/python is reachable -- many Windows machines don't have one on
# PATH at all. Falls through to cppcheck's own auto-detect (unchanged
# behavior) if none of this resolves anything.
resolve_addon_python() {
    if command -v python3 >/dev/null 2>&1; then
        command -v python3
        return 0
    fi
    if command -v python >/dev/null 2>&1; then
        command -v python
        return 0
    fi
    local uv_bin=""
    if command -v uv >/dev/null 2>&1; then
        uv_bin="$(command -v uv)"
    else
        local c
        for c in "$HOME/.local/bin/uv" "${USERPROFILE:-}/.local/bin/uv.exe" \
            "/c/Users/${USER:-$USERNAME}/.local/bin/uv.exe"; do
            [ -n "$c" ] && [ -x "$c" ] && { uv_bin="$c"; break; }
        done
    fi
    [ -n "$uv_bin" ] && "$uv_bin" python find 2>/dev/null && return 0
    return 1
}

ADDON_PYTHON_ARGS=()
if addon_python_bin="$(resolve_addon_python)"; then
    ADDON_PYTHON_ARGS=(--addon-python="$addon_python_bin")
fi

FIX=0
if [ "${1:-}" = "--fix" ]; then
    FIX=1
    shift
fi

# --cubeide: force cppcheck's output into GCC "warning:" format so
# STM32CubeIDE's built-in GNU Error Parser (no plugin) turns findings into
# real Problems-view markers when this is run as a C/C++ Build > Settings >
# Build Steps > post-build step. Eclipse CDT's parser only recognizes
# warning/error/note/info/remark -- cppcheck's own severities (style,
# performance, portability) don't match and get silently dropped otherwise.
# clang-tidy's C++ output already matches (WarningsAsErrors in .clang-tidy
# makes it print "error:"), so only cppcheck's template needs to change.
CUBEIDE=0
if [ "${1:-}" = "--cubeide" ]; then
    CUBEIDE=1
    shift
fi

if [ "$#" -eq 0 ]; then
    targets=("$REPO_ROOT")
else
    targets=("$@")
fi

# status: real lint findings (exit 1). config_error: the tool itself is
# broken (missing addon, bad compile db, ...) -- kept separate so a build
# failure caused by a real MISRA violation looks different from one caused
# by a misconfigured toolchain (exit 2). Config errors always win the exit
# code, since findings under a broken tool run aren't trustworthy anyway.
status=0
config_error=0

is_excluded() {
    local path="$1"
    while IFS= read -r pattern; do
        [[ -z "$pattern" || "$pattern" == \#* ]] && continue
        # shellcheck disable=SC2053
        if [[ "$path" == $pattern ]]; then
            return 0
        fi
    done < "$EXCLUDE_FILE"
    return 1
}

# collect_files <out-array-name> <ext...> -- <target...>
# Each target may be a directory (searched recursively) or a single file.
# This dual mode lets the same script serve directory-wide CI/dev-shell runs
# and pre-commit's per-staged-file invocation.
collect_files() {
    local -n _out="$1"
    shift
    local -a exts=()
    while [ "$1" != "--" ]; do
        exts+=("$1")
        shift
    done
    shift

    local find_expr=(-name "*.${exts[0]}")
    local e
    for e in "${exts[@]:1}"; do
        find_expr+=(-o -name "*.$e")
    done

    local t f matches
    for t in "$@"; do
        if [ -d "$t" ]; then
            while IFS= read -r -d '' f; do
                is_excluded "$f" && continue
                _out+=("$f")
            done < <(find "$t" -type f \( "${find_expr[@]}" \) -print0)
        elif [ -f "$t" ]; then
            is_excluded "$t" && continue
            matches=0
            for e in "${exts[@]}"; do
                case "$t" in
                    *.$e) matches=1 ;;
                esac
            done
            [ "$matches" -eq 1 ] && _out+=("$t")
        fi
    done

    return 0
}

# cppcheck has no autofix mode -- MISRA-C findings are logic issues, not
# mechanically fixable. --fix only applies to the clang-tidy pass below.
echo "== MISRA C (cppcheck) =="
c_files=()
collect_files c_files c -- "${targets[@]}"

if [ "${#c_files[@]}" -gt 0 ]; then
    # --platform: STM32/Cortex-M is 32-bit with unsigned-by-default char
    # (ARM EABI), neither of which matches this dev machine's own type
    # sizes/signedness. Without this, cppcheck silently misses real bugs
    # (e.g. `1L << 31` is fine with a 64-bit host long, undefined behavior
    # with Cortex-M's 32-bit one) and can misjudge char-signedness-sensitive
    # MISRA checks. misra/arm32-wchar_t4.xml is cppcheck's own upstream ARM
    # platform definition, bundled here since its install path isn't
    # consistent across OSes/package managers; verified against this
    # exact target's own compiler macros (__SIZEOF_WCHAR_T__=4,
    # __CHAR_UNSIGNED__=1).
    # missingIncludeSystem/checkersReport are cppcheck's own tool tips, not
    # findings (cppcheck says so itself: "Standard library headers do not
    # need to be provided"). Harmless as terminal noise, but --cubeide forces
    # every line's severity to "warning:" for CDT's parser -- without
    # suppressing these, they'd show up looking exactly like real "header
    # not found" problems in CubeIDE's Problems view.
    template_args=()
    if [ "$CUBEIDE" -eq 1 ]; then
        template_args=(--template='{file}:{line}:{column}: warning: {message} [{id}]')
    fi

    # Without --project, cppcheck gets zero -I paths and can't resolve a
    # single one of the project's own headers ("FreeRTOS.h", "main.h", ...)
    # -- verified against a real CubeIDE build, every file spammed
    # missingInclude and failed the build over headers cppcheck was never
    # told where to find. --project=compile_commands.json (when
    # gen_compile_commands.sh has produced one) gives cppcheck the real
    # per-file -I/-D flags from the actual build.
    #
    # Not every c_files entry is guaranteed to be IN that compile database
    # though (a file added since the last CubeIDE build, or -- as seen
    # while testing this against this repo's own demo/ self-test with an
    # unrelated sample compile_commands.json sitting at the root --
    # completely unrelated files). --file-filter for a file --project
    # doesn't know about is a hard "could not find any files matching the
    # filter" error, verified directly, so partition into files the
    # database actually covers (run via --project + --file-filter, for
    # accurate include resolution) and files it doesn't (run plain, same
    # as when there's no compile_commands.json at all) rather than letting
    # one uncovered file kill the entire run.
    matched_files=()
    if [ -f "$REPO_ROOT/compile_commands.json" ]; then
        while IFS= read -r f; do
            matched_files+=("$f")
        done < <(python3 - "$REPO_ROOT/compile_commands.json" "${c_files[@]}" <<'PY'
import json, sys

db_path, targets = sys.argv[1], sys.argv[2:]
with open(db_path) as f:
    entries = json.load(f)
db_files = {e.get("file", "").replace("\\", "/") for e in entries}
for t in targets:
    t_norm = t.replace("\\", "/")
    if any(f.endswith(t_norm) or t_norm.endswith(f) for f in db_files):
        print(t)
PY
        )
    fi

    unmatched_files=()
    for f in "${c_files[@]}"; do
        is_matched=0
        for m in "${matched_files[@]}"; do
            [ "$f" = "$m" ] && { is_matched=1; break; }
        done
        [ "$is_matched" -eq 0 ] && unmatched_files+=("$f")
    done

    # compile_flags.txt fallback (unmatched/no-db files only): cppcheck has
    # no native concept of this file (unlike clang-tidy/clangd, which read
    # it via -p). It also only tolerates -I<dir> and -D<ID> -- anything
    # else in there (--target=, -mcpu=, -mthumb, ...) is a hard
    # "unrecognized command line option" error for cppcheck, verified
    # directly. So pull out just the include paths (-isystem <dir> pairs
    # count as -I too; cppcheck doesn't distinguish system vs quote
    # includes) and drop everything else rather than forwarding as-is.
    fallback_include_args=()
    if [ "${#unmatched_files[@]}" -gt 0 ] && [ -f "$REPO_ROOT/compile_flags.txt" ]; then
        prev_flag=""
        while IFS= read -r flag; do
            case "$prev_flag" in
                -isystem) fallback_include_args+=("-I$flag") ;;
            esac
            case "$flag" in
                -I*) fallback_include_args+=("$flag") ;;
                -D*) fallback_include_args+=("$flag") ;;
            esac
            prev_flag="$flag"
        done < "$REPO_ROOT/compile_flags.txt"
    fi

    cppcheck_log="$(mktemp)"
    cppcheck_rc=0
    # set +e around each pipeline, not `|| true` after it: under pipefail, a
    # failing pipeline followed by `|| true` runs `true` as its own trivial
    # pipeline, which clobbers PIPESTATUS before the next line can read it
    # (verified: PIPESTATUS collapses to just true's "0"). Disabling -e
    # instead lets the real per-stage PIPESTATUS survive to the next line.
    set +e
    if [ "${#matched_files[@]}" -gt 0 ]; then
        file_filter_args=()
        for f in "${matched_files[@]}"; do
            file_filter_args+=(--file-filter="$f")
        done
        cppcheck --enable=all --inconclusive --addon="$MISRA_ADDON" "${ADDON_PYTHON_ARGS[@]}" \
            --platform="$CPPCHECK_PLATFORM" \
            --suppress=missingIncludeSystem --suppress=checkersReport \
            --error-exitcode=1 --suppressions-list="$SUPPRESSIONS_FILE" \
            --inline-suppr "${template_args[@]}" \
            --project="$REPO_ROOT/compile_commands.json" "${file_filter_args[@]}" 2>&1 | tee -a "$cppcheck_log"
        [ "${PIPESTATUS[0]}" -ne 0 ] && cppcheck_rc=1
    fi
    if [ "${#unmatched_files[@]}" -gt 0 ]; then
        cppcheck --enable=all --inconclusive --addon="$MISRA_ADDON" "${ADDON_PYTHON_ARGS[@]}" \
            --platform="$CPPCHECK_PLATFORM" \
            --suppress=missingIncludeSystem --suppress=checkersReport \
            --error-exitcode=1 --suppressions-list="$SUPPRESSIONS_FILE" \
            --inline-suppr "${template_args[@]}" \
            "${fallback_include_args[@]}" "${unmatched_files[@]}" 2>&1 | tee -a "$cppcheck_log"
        [ "${PIPESTATUS[0]}" -ne 0 ] && cppcheck_rc=1
    fi
    set -e

    # Config-error patterns are cppcheck telling us IT is broken, not that
    # the code violates MISRA -- e.g. "Did not find addon misra.py" (see
    # resolve_misra_addon above) or "Failed to auto detect python" (see
    # resolve_addon_python above). Treat these as a distinct failure so
    # they never get mistaken for real findings.
    if grep -qE "Did not find addon|Bailing out from checking|unable to load|Failed to auto detect python" "$cppcheck_log"; then
        echo "ERROR: cppcheck configuration problem (above) -- not a MISRA finding, lint results are unreliable until this is fixed." >&2
        config_error=1
    elif [ "$cppcheck_rc" -ne 0 ]; then
        status=1
    fi
    rm -f "$cppcheck_log"
else
    echo "no .c files found"
fi

echo "== MISRA C++ best-effort (clang-tidy) =="
cpp_files=()
collect_files cpp_files cpp hpp -- "${targets[@]}"

if [ "${#cpp_files[@]}" -gt 0 ]; then
    # -p "$REPO_ROOT" picks up compile_commands.json when a real firmware
    # project has generated one, else falls back to compile_flags.txt
    # (ARM/Cortex-M4 target) which this repo always ships.
    fix_args=()
    [ "$FIX" -eq 1 ] && fix_args=(--fix)
    for f in "${cpp_files[@]}"; do
        if ! clang-tidy --config-file="$CLANG_TIDY_CONFIG" -p "$REPO_ROOT" "${fix_args[@]}" "$f"; then
            status=1
        fi
    done
else
    echo "no .cpp/.hpp files found"
fi

if [ "$config_error" -eq 1 ]; then
    echo "" >&2
    echo "Exiting 2 (toolchain misconfigured) -- distinct from exit 1 (real findings)." >&2
    exit 2
fi
exit "$status"

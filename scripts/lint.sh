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

# cppcheck's --addon= accepts either a bare script path OR a JSON manifest
# with a "script" + "args" list -- the JSON form is the only way to pass
# --rule-texts= through to misra.py, since cppcheck's own CLI has no
# forwarding syntax for addon args. Without this, every finding prints the
# placeholder "misra violation (use --rule-texts=<file> to get proper
# output) [misra-c2012-N.M]" instead of the actual rule description.
# MISRA-C:2012 rule text is copyrighted by MISRA Ltd. and can't ship with
# cppcheck, so users have to supply their own text file; misra/rule-texts.txt
# in this repo is a paraphrased developer-facing summary (not audit-grade).
RULE_TEXTS_FILE="$MISRA_DIR/rule-texts.txt"
if [ -f "$RULE_TEXTS_FILE" ]; then
    misra_manifest="$(mktemp --suffix=.json)"
    python3 - "$MISRA_ADDON" "$RULE_TEXTS_FILE" "$misra_manifest" <<'PY'
import json, sys
script, rule_texts, out = sys.argv[1:4]
with open(out, "w") as f:
    json.dump({"script": script, "args": ["--rule-texts=" + rule_texts]}, f)
PY
    MISRA_ADDON="$misra_manifest"
    trap 'rm -f "$misra_manifest"' EXIT
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
    # demo/ holds deliberate violations for the self-test walkthrough
    # (README: `./scripts/lint.sh demo`) -- excluded here, not via
    # misra/exclude-paths.txt, because is_excluded() would apply to an
    # explicit `demo` target too and silently hide that walkthrough's own
    # findings. Skipping it only from this implicit whole-repo default
    # keeps pre-commit's pass_filenames: false scan (which relies on this
    # default) from tripping over demo/'s intentional noise, while
    # `./scripts/lint.sh demo` still shows it directly.
    targets=()
    while IFS= read -r -d '' entry; do
        [ "$(basename "$entry")" = "demo" ] && continue
        targets+=("$entry")
    done < <(find "$REPO_ROOT" -mindepth 1 -maxdepth 1 -print0)
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
    # missingIncludeSystem/checkersReport/normalCheckLevelMaxBranches are
    # cppcheck's own tool tips, not findings (cppcheck says so itself:
    # "Standard library headers do not need to be provided"). Harmless as
    # terminal noise -- EXCEPT --error-exitcode=1 below counts them anyway:
    # verified cppcheck 2.21.1 sets the process exit code for
    # normalCheckLevelMaxBranches ("Limiting analysis of branches...")
    # despite it being severity=information and printing nothing that looks
    # like a finding, which silently failed the build/pre-commit hook on a
    # function complex enough to hit cppcheck's default check-level branch
    # limit even with zero real violations. Must suppress all three or
    # --error-exitcode fires on noise. --cubeide forces every line's
    # severity to "warning:" for CDT's parser -- without
    # suppressing these, they'd show up looking exactly like real "header
    # not found" problems in CubeIDE's Problems view.
    template_args=()
    if [ "$CUBEIDE" -eq 1 ]; then
        template_args=(--template='{file}:{line}:{column}: warning: {message} [{id}]')
    fi

    # Without extra -I/-D flags, cppcheck can't resolve a single one of the
    # project's own headers ("FreeRTOS.h", "main.h", ...) -- verified
    # against a real CubeIDE build, every file spammed missingInclude and
    # failed the build over headers cppcheck was never told where to find.
    #
    # Tried cppcheck's own --project=compile_commands.json + --file-filter
    # first, but verified against a real STM32CubeIDE run that cppcheck's
    # native Windows exe can reject every --file-filter with "could not
    # find any files matching the filter" even when the filter path is
    # byte-for-byte identical to the database's own "file" entry -- a
    # project-loader quirk this toolchain has no visibility into and can't
    # fix from the outside. So: extract the real -I/-D flags ourselves
    # (same technique as the compile_flags.txt fallback below) from one
    # representative compile_commands.json entry and apply them to every
    # target file in one plain invocation, same as compile_flags.txt.
    # STM32CubeIDE projects use one global include/define set across all
    # project files (verified against a real export), so one entry's flags
    # generalize fine -- this sidesteps --project/--file-filter entirely
    # rather than depending on cppcheck's own project-file matching.
    extra_include_args=()
    if [ -f "$REPO_ROOT/compile_commands.json" ]; then
        # Python's print() on Windows adds '\r\n' to stdout in text mode,
        # and bash's `read -r` only strips '\n' -- verified: every extracted
        # flag ends up with a trailing '\r' that cppcheck receives as part
        # of the path (e.g. '-I.../Core/Inc\r'), which then reports as
        # "Couldn't find path" because the directory literally doesn't have
        # a CR-suffixed name. Same CRLF hazard applies to compile_flags.txt
        # further down (checked into the repo on Windows = CRLF endings).
        # Strip '\r' explicitly after every read rather than relying on
        # Python/git line-ending behavior we don't control here.
        while IFS= read -r flag; do
            flag="${flag%$'\r'}"
            [ -n "$flag" ] && extra_include_args+=("$flag")
        done < <(python3 - "$REPO_ROOT/compile_commands.json" <<'PY'
import json, os, posixpath, shlex, sys

with open(sys.argv[1]) as f:
    entries = json.load(f)
if not entries:
    sys.exit(0)
entry = entries[0]
directory = entry.get("directory", "").replace("\\", "/").rstrip("/")
tokens = entry.get("arguments") or shlex.split(entry.get("command", ""))

def resolve(path):
    # Normalize slashes first so posixpath can collapse '..' segments
    # regardless of which slash CubeIDE emitted. cppcheck on Windows
    # treats unnormalized '..' in -I paths as literal path components
    # when probing existence (verified against a real CubeIDE export --
    # every '-I../Core/Inc'-style entry got 'Couldn't find path'), which
    # then cascades into missingInclude and [misra-config] errors on
    # everything the header would have defined (HAL_OK, SPI1, ...).
    # posixpath.normpath keeps '/' as separator, which is what cppcheck
    # accepts on Windows without slash-flipping quirks.
    path = path.replace("\\", "/")
    if path.startswith("/") or (len(path) > 1 and path[1] == ":"):
        joined = path
    else:
        joined = directory + "/" + path
    return posixpath.normpath(joined)

seen = set()
def emit(flag):
    if flag not in seen:
        seen.add(flag)
        print(flag)

# gcc/arm-none-eabi-gcc auto-defines __GNUC__ (and friends) as builtin
# predefines -- they never appear on the command line, so they aren't
# in compile_commands.json either. cppcheck DOESN'T inherit builtin
# predefines even in --language=c mode: verified against this exact
# CubeIDE export, cmsis_compiler.h's compiler-detection chain (checks
# __CC_ARM, __ARMCC_VERSION, __GNUC__ in order) falls through to
# '#error Unknown compiler', which then trips cppcheck into
# 'Bailing out from analysis' and suppresses every subsequent MISRA
# finding across the whole TU (silent false pass). Inject the minimum
# GCC predefine set CMSIS's own compiler chain needs so preprocessing
# survives long enough for the MISRA addon to actually run.
compiler = tokens[0].lower() if tokens else ""
if "gcc" in compiler or compiler.endswith("cc"):
    emit("-D__GNUC__=10")
    emit("-D__GNUC_MINOR__=3")
    emit("-D__GNUC_PATCHLEVEL__=1")

i = 0
while i < len(tokens):
    tok = tokens[i]
    flag = None
    if tok.startswith("-I") and len(tok) > 2:
        flag = "-I" + resolve(tok[2:])
    elif tok in ("-I", "-isystem") and i + 1 < len(tokens):
        flag = "-I" + resolve(tokens[i + 1])
        i += 1
    elif tok.startswith("-D"):
        flag = tok
    if flag is not None:
        emit(flag)
    i += 1
PY
        )
    elif [ -f "$REPO_ROOT/compile_flags.txt" ]; then
        # compile_flags.txt fallback: cppcheck has no native concept of this
        # file (unlike clang-tidy/clangd, which read it via -p). It also
        # only tolerates -I<dir> and -D<ID> -- anything else in there
        # (--target=, -mcpu=, -mthumb, ...) is a hard "unrecognized command
        # line option" error for cppcheck, verified directly. So pull out
        # just the include paths (-isystem <dir> pairs count as -I too;
        # cppcheck doesn't distinguish system vs quote includes) and drop
        # everything else rather than forwarding the file as-is.
        prev_flag=""
        while IFS= read -r flag; do
            flag="${flag%$'\r'}"
            case "$prev_flag" in
                -isystem) extra_include_args+=("-I$flag") ;;
            esac
            case "$flag" in
                -I*) extra_include_args+=("$flag") ;;
                -D*) extra_include_args+=("$flag") ;;
            esac
            prev_flag="$flag"
        done < "$REPO_ROOT/compile_flags.txt"
    fi

    # exclude-paths.txt only keeps a path out of the target-file list handed
    # to cppcheck below -- it does nothing once cppcheck follows a target
    # file's own #include chain into a header under one of those paths
    # (HAL/CMSIS/Middlewares/generated). cppcheck's MISRA addon reports
    # findings at the header's own file:line, so vendor headers pulled in by
    # a project's own .c files still flood the output even though the
    # header itself was never a scan target. Verified against a real
    # STM32CubeIDE project (sensor_fusion_rtos): every HAL header included
    # by main.c lit up despite Drivers/*HAL_Driver/* being excluded.
    # Fix: reuse the same glob patterns as cppcheck suppressions (errorId
    # '*' wildcard = any finding) so vendor headers are silent regardless of
    # how they're reached, not just when passed directly as a target.
    combined_suppressions="$(mktemp)"
    cp "$SUPPRESSIONS_FILE" "$combined_suppressions"
    while IFS= read -r pattern; do
        [[ -z "$pattern" || "$pattern" == \#* ]] && continue
        printf '*:%s\n' "$pattern" >> "$combined_suppressions"
    done < "$EXCLUDE_FILE"

    cppcheck_log="$(mktemp)"
    # set +e around the pipeline, not `|| true` after it: under pipefail, a
    # failing pipeline followed by `|| true` runs `true` as its own trivial
    # pipeline, which clobbers PIPESTATUS before the next line can read it
    # (verified: PIPESTATUS collapses to just true's "0"). Disabling -e
    # instead lets the real per-stage PIPESTATUS survive to the next line.
    set +e
    cppcheck --enable=all --inconclusive --addon="$MISRA_ADDON" "${ADDON_PYTHON_ARGS[@]}" \
        --platform="$CPPCHECK_PLATFORM" \
        --suppress=missingIncludeSystem --suppress=checkersReport \
        --suppress=normalCheckLevelMaxBranches \
        --error-exitcode=1 --suppressions-list="$combined_suppressions" \
        --inline-suppr "${template_args[@]}" "${extra_include_args[@]}" "${c_files[@]}" 2>&1 | tee "$cppcheck_log"
    cppcheck_rc="${PIPESTATUS[0]}"
    set -e
    rm -f "$combined_suppressions"

    # Config-error patterns are cppcheck telling us IT is broken, not that
    # the code violates MISRA -- e.g. "Did not find addon misra.py" (see
    # resolve_misra_addon above), "Failed to auto detect python" (see
    # resolve_addon_python above), or misra.py's own "[misra-config]" tag
    # (emitted per-identifier as "Because of missing configuration, misra
    # checking is incomplete" whenever a project macro/type can't be
    # resolved -- e.g. no real compile_commands.json yet, only the
    # compile_flags.txt CPU/target-flags fallback, which never carries
    # project -I paths). Findings from a run missing macro/type info aren't
    # trustworthy (real violations can be silently missed, not just
    # over-reported), so this counts as the tool being unconfigured too,
    # same as the other patterns -- not a real MISRA finding to fix in code.
    if grep -qE "Did not find addon|Bailing out from checking|unable to load|Failed to auto detect python|\[misra-config\]" "$cppcheck_log"; then
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

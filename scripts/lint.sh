#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
MISRA_DIR="$REPO_ROOT/misra"

EXCLUDE_FILE="$MISRA_DIR/exclude-paths.txt"
SUPPRESSIONS_FILE="$MISRA_DIR/suppressions.txt"
CLANG_TIDY_CONFIG="$REPO_ROOT/.clang-tidy"

FIX=0
if [ "${1:-}" = "--fix" ]; then
    FIX=1
    shift
fi

if [ "$#" -eq 0 ]; then
    targets=("$REPO_ROOT")
else
    targets=("$@")
fi

status=0

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
    # --platform=unix32: STM32/Cortex-M is 32-bit (4-byte long/pointer).
    # Without this, cppcheck defaults to the host's own type sizes (64-bit
    # long/pointer on most dev machines), which silently misses real bugs
    # -- e.g. `1L << 31` is fine with a 64-bit long but undefined behavior
    # with a 32-bit one. unix32 is the closest built-in match; cppcheck has
    # no dedicated Cortex-M/ARM platform.
    if ! cppcheck --enable=all --inconclusive --addon=misra.py \
        --platform=unix32 \
        --error-exitcode=1 --suppressions-list="$SUPPRESSIONS_FILE" \
        --inline-suppr "${c_files[@]}"; then
        status=1
    fi
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

exit "$status"

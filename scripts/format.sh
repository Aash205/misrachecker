#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
MISRA_DIR="$REPO_ROOT/misra"

EXCLUDE_FILE="$MISRA_DIR/exclude-paths.txt"

MODE="${1:?usage: format.sh <check|fix> [target...]}"
shift || true

if [ "$#" -eq 0 ]; then
    targets=("$REPO_ROOT")
else
    targets=("$@")
fi

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

# Each target may be a directory (searched recursively) or a single file --
# this dual mode lets the same script serve directory-wide dev-shell runs
# and pre-commit's per-staged-file invocation.
files=()
for t in "${targets[@]}"; do
    if [ -d "$t" ]; then
        while IFS= read -r -d '' f; do
            is_excluded "$f" && continue
            files+=("$f")
        done < <(find "$t" -type f \( -name '*.c' -o -name '*.h' -o -name '*.cpp' -o -name '*.hpp' \) -print0)
    elif [ -f "$t" ]; then
        is_excluded "$t" && continue
        case "$t" in
            *.c | *.h | *.cpp | *.hpp) files+=("$t") ;;
        esac
    fi
done

if [ "${#files[@]}" -eq 0 ]; then
    echo "no C/C++ files found"
    exit 0
fi

status=0
total="${#files[@]}"
i=0
for f in "${files[@]}"; do
    i=$((i + 1))
    echo "[$i/$total] ${f#"$REPO_ROOT"/}"
    case "$MODE" in
        check)
            clang-format --dry-run --Werror "$f" || status=1
            ;;
        fix)
            clang-format -i "$f"
            ;;
        *)
            echo "usage: format.sh <check|fix> [target...]" >&2
            exit 1
            ;;
    esac
done

[ "$MODE" = "fix" ] && echo "formatted $total file(s)"
exit "$status"

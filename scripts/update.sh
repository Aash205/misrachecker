#!/usr/bin/env bash
set -euo pipefail

TARGET="${1:?usage: update.sh <path-to-firmware-repo>}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SRC_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

[ -d "$TARGET" ] || { echo "ERROR: $TARGET is not a directory" >&2; exit 1; }

new_count=0
modified_count=0

# Never overwrites a file that differs from upstream -- writes a .new
# sibling instead so a local customization (e.g. a project-specific
# exclude-paths.txt entry) survives a re-run. This is what install.sh
# calls too: on an empty target every file is "new", so a fresh install
# is just a special case of an update.
sync_file() {
    local src="$1" dst="$2"
    if [ ! -f "$dst" ]; then
        mkdir -p "$(dirname "$dst")"
        cp "$src" "$dst"
        echo "  new:      ${dst#"$TARGET"/}"
        new_count=$((new_count + 1))
    elif cmp -s "$src" "$dst"; then
        : # identical, nothing to do
    else
        cp "$src" "$dst.new"
        echo "  MODIFIED: ${dst#"$TARGET"/} differs from upstream -- wrote $(basename "$dst").new to diff/merge"
        modified_count=$((modified_count + 1))
    fi
}

while IFS= read -r -d '' f; do
    rel="${f#"$SRC_ROOT"/}"
    sync_file "$f" "$TARGET/$rel"
done < <(find "$SRC_ROOT/.vscode" "$SRC_ROOT/misra" "$SRC_ROOT/scripts" -type f -print0)

for f in .clang-tidy .clang-format .editorconfig \
    .pre-commit-config.yaml .github/workflows/misra-lint.yml; do
    sync_file "$SRC_ROOT/$f" "$TARGET/$f"
done
# compile_flags.txt is NOT synced -- it's machine-generated (real ARM
# toolchain include paths, if found) by scripts/gen_compile_flags.sh,
# which setup.sh already runs. A copied one would have this machine's
# paths baked in, wrong on any other machine.

echo ""
echo "Sync summary: $new_count new file(s), $modified_count locally-modified file(s) left untouched."
if [ "$modified_count" -gt 0 ]; then
    echo "Review each *.new file, merge what you want, then delete the *.new file."
fi

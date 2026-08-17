#!/usr/bin/env bash
set -euo pipefail

TARGET="${1:?usage: update.sh <path-to-firmware-repo>}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SRC_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

[ -d "$TARGET" ] || { echo "ERROR: $TARGET is not a directory" >&2; exit 1; }
command -v python3 >/dev/null 2>&1 || { echo "ERROR: python3 not found (needed for JSON merge)" >&2; exit 1; }

new_count=0
modified_count=0

# JSON files (.vscode/*.json) deep-merge instead of .new-siding: dicts
# merge key-by-key with upstream winning on scalar conflicts, lists
# concat-dedupe (upstream items first). Safe for tasks.json/settings.json
# since a local custom task/setting survives as an extra list item / key,
# while upstream fixes (e.g. the shell->process task-type fix) always land.
merge_json() {
    local src="$1" dst="$2"
    python3 - "$src" "$dst" <<'PY'
import json, sys

src_path, dst_path = sys.argv[1], sys.argv[2]
with open(src_path) as f:
    src = json.load(f)
with open(dst_path) as f:
    dst = json.load(f)

def identity(d):
    # VSCode list-of-object conventions (tasks[].label, inputs[].id, ...):
    # merge by this key instead of dict equality, else a locally-edited
    # task with the same label as an upstream one duplicates instead of
    # merging.
    for k in ("label", "id", "name"):
        if k in d:
            return (k, d[k])
    return None

def merge(old, new):
    if isinstance(old, dict) and isinstance(new, dict):
        out = dict(old)
        for k, v in new.items():
            out[k] = merge(old[k], v) if k in old else v
        return out
    if isinstance(old, list) and isinstance(new, list):
        if new and all(isinstance(x, dict) for x in old + new):
            ids_new = [identity(x) for x in new]
            if None not in ids_new and len(set(ids_new)) == len(ids_new):
                by_id_old = {identity(x): x for x in old if identity(x) is not None}
                out = [merge(by_id_old[identity(x)], x) if identity(x) in by_id_old else x for x in new]
                out += [x for x in old if identity(x) not in ids_new]
                return out
        out = list(new)  # fallback: concat-dedupe by equality (e.g. string lists)
        for item in old:
            if item not in out:
                out.append(item)
        return out
    return new  # upstream (new) wins on scalar conflicts

with open(dst_path, "w") as f:
    json.dump(merge(dst, src), f, indent=4)
    f.write("\n")
PY
}

# Never overwrites a non-JSON file that differs from upstream -- writes a
# .new sibling instead so a local customization (e.g. a project-specific
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
    elif [[ "$dst" == *.json ]]; then
        merge_json "$src" "$dst"
        echo "  merged:   ${dst#"$TARGET"/} (JSON deep-merge, upstream wins conflicts)"
        modified_count=$((modified_count + 1))
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
echo "Sync summary: $new_count new file(s), $modified_count locally-modified file(s) touched."
if [ "$modified_count" -gt 0 ]; then
    echo "JSON files were merged in place (upstream wins on conflicts) -- review the diff."
    echo "Non-JSON files got a *.new sibling -- merge what you want, then delete the *.new file."
fi

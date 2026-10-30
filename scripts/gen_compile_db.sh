#!/usr/bin/env bash
# Configure the firmware (no build) and publish its compile database at the project root,
# where lint.sh and clang-tidy look for it. The root copy is gitignored.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

(cd "$ROOT" && cmake --preset Debug >/dev/null)
cp "$ROOT/build/Debug/compile_commands.json" "$ROOT/compile_commands.json"
echo "Wrote $ROOT/compile_commands.json"

#!/usr/bin/env bash
set -euo pipefail

TARGET="${1:?usage: install.sh <path-to-firmware-repo>}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SRC_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

[ -d "$TARGET" ] || { echo "ERROR: $TARGET is not a directory" >&2; exit 1; }

mkdir -p "$TARGET/.vscode" "$TARGET/misra" "$TARGET/scripts" "$TARGET/.github/workflows"

cp -r "$SRC_ROOT/.vscode/." "$TARGET/.vscode/"
cp -r "$SRC_ROOT/misra/." "$TARGET/misra/"
cp -r "$SRC_ROOT/scripts/." "$TARGET/scripts/"
cp "$SRC_ROOT/.clang-tidy" "$TARGET/.clang-tidy"
cp "$SRC_ROOT/.clang-format" "$TARGET/.clang-format"
cp "$SRC_ROOT/.pre-commit-config.yaml" "$TARGET/.pre-commit-config.yaml"
cp "$SRC_ROOT/.github/workflows/misra-lint.yml" "$TARGET/.github/workflows/misra-lint.yml"

echo "Installed MISRA toolchain into $TARGET"
echo "Next:"
echo "  1. cd $TARGET && ./scripts/setup.sh   # installs tools + pre-commit hooks, one shot"
echo "  2. Open $TARGET in VSCode, accept the recommended-extensions prompt."
echo "  3. Run ./scripts/gen_compile_commands.sh <cubeide-project-dir> once."

#!/usr/bin/env bash
set -euo pipefail

TARGET="${1:?usage: install.sh <path-to-firmware-repo>}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

[ -d "$TARGET" ] || { echo "ERROR: $TARGET is not a directory" >&2; exit 1; }

"$SCRIPT_DIR/update.sh" "$TARGET"

echo ""
echo "Installed MISRA toolchain into $TARGET"
echo "Next:"
echo "  1. cd $TARGET && ./scripts/setup.sh   # installs tools + pre-commit hooks, one shot"
echo "  2. Open $TARGET in VSCode, accept the recommended-extensions prompt."
echo "  3. Run ./scripts/gen_compile_commands.sh <cubeide-project-dir> once."

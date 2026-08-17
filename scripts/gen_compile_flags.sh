#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
OUT="$REPO_ROOT/compile_flags.txt"

# clang's target flags (used by clangd/clang-tidy directly). These are
# portable and always safe to write.
CLANG_FLAGS=(--target=arm-none-eabi -mcpu=cortex-m4 -mfloat-abi=soft -mthumb)

# Flags to pass when *querying* a real arm-none-eabi-g++ below. GCC doesn't
# understand clang's --target= syntax, so this list excludes it.
CPU_FLAGS=(-mcpu=cortex-m4 -mfloat-abi=soft -mthumb)

{
    for f in "${CLANG_FLAGS[@]}"; do
        echo "$f"
    done
} > "$OUT"

if command -v arm-none-eabi-g++ >/dev/null 2>&1; then
    echo "Found arm-none-eabi-g++ on PATH -- querying its real system include paths..."
    # Standard library headers (<cstdint>, etc.) live in a CPU/FPU-specific
    # multilib subdirectory that clang can't guess -- only the real GCC
    # cross-compiler knows exactly where, so ask it directly.
    found_any=0
    while IFS= read -r p; do
        p="${p# }"
        [ -d "$p" ] || continue
        {
            echo "-isystem"
            echo "$p"
        } >> "$OUT"
        found_any=1
    done < <(arm-none-eabi-g++ "${CPU_FLAGS[@]}" -std=c++17 -E -x c++ /dev/null -v 2>&1 \
        | sed -n '/search starts here/,/End of search/p' | grep '^ ')

    if [ "$found_any" -eq 1 ]; then
        echo "Wrote $OUT with real ARM toolchain system include paths."
    fi
else
    echo "arm-none-eabi-g++ not found on PATH -- compile_flags.txt has CPU/target flags"
    echo "only. Standard library headers (<cstdint>, etc.) may not resolve in clangd or"
    echo "clang-tidy until you either install a standalone arm-none-eabi-gcc toolchain"
    echo "and re-run this script, or generate a real compile_commands.json against your"
    echo "CubeIDE project via gen_compile_commands.sh (that path always works, since"
    echo "CubeIDE's own compiler path is embedded in the real build command)."
fi

#!/usr/bin/env bash
set -euo pipefail

os_name="$(uname -s)"

missing=()
optional_missing=()

command -v cppcheck >/dev/null 2>&1 || missing+=("cppcheck")
command -v clang-tidy >/dev/null 2>&1 || missing+=("clang-tidy")
command -v clang-format >/dev/null 2>&1 || missing+=("clang-format")

# bear (compile_commands.json fallback for old CubeIDE) has no solid native
# Windows build, and isn't needed on any OS as long as CubeIDE's native
# "Generate compile_commands.json" export checkbox is used -- that's the
# primary path everywhere. Advisory only, on every platform.
command -v bear >/dev/null 2>&1 || optional_missing+=("bear")

# pre-commit itself is bootstrapped on demand by install-hooks.sh via
# whichever of these is available -- either is fine, no preference enforced.
if ! command -v uv >/dev/null 2>&1 && ! command -v pip3 >/dev/null 2>&1 && ! command -v pip >/dev/null 2>&1; then
    missing+=("uv-or-pip (needed to bootstrap pre-commit)")
fi

if [ "${#missing[@]}" -eq 0 ]; then
    echo "MISRA toolchain: all required CLI tools found (cppcheck, clang-tidy, clang-format, uv/pip)."
    if [ "${#optional_missing[@]}" -gt 0 ]; then
        echo "Optional: ${optional_missing[*]} not found -- only needed as a compile_commands.json"
        echo "fallback for old STM32CubeIDE versions without the native export checkbox. Not"
        echo "required on any platform; use CubeIDE's native export instead."
    fi
    exit 0
fi

echo "MISRA toolchain: missing tools: ${missing[*]}"
echo ""
case "$os_name" in
    Linux*)
        echo "Install with:"
        echo "  sudo apt-get update && sudo apt-get install -y cppcheck clang-tidy clang-format"
        echo "  curl -LsSf https://astral.sh/uv/install.sh | sh   # or: sudo apt-get install -y python3-pip"
        echo "  (bear not required -- use STM32CubeIDE's native 'Generate compile_commands.json'"
        echo "   checkbox instead; sudo apt-get install -y bear only if you need the fallback)"
        ;;
    Darwin*)
        echo "Install with:"
        echo "  brew install cppcheck llvm uv"
        echo "  (bear not required -- use STM32CubeIDE's native 'Generate compile_commands.json'"
        echo "   checkbox instead; brew install bear only if you need the fallback)"
        ;;
    MINGW* | MSYS* | CYGWIN*)
        echo "Windows (Git Bash) -- winget ships with Windows 10/11, no separate install needed:"
        echo "  winget install --id Cppcheck.Cppcheck -e"
        echo "  winget install --id LLVM.LLVM -e            # clang-tidy + clang-format"
        echo "  winget install --id astral-sh.uv -e"
        echo "  No winget? Manual installers work too: https://cppcheck.sourceforge.io/"
        echo "  and https://releases.llvm.org/ -- make sure each ends up on PATH."
        echo "  (bear is not required on Windows -- use STM32CubeIDE's native"
        echo "   'Generate compile_commands.json' checkbox instead of the bear fallback)"
        ;;
    *)
        echo "Unsupported OS for auto-suggested install command; install manually: ${missing[*]}"
        ;;
esac

exit 1

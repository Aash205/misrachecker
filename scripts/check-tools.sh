#!/usr/bin/env bash
set -euo pipefail

os_name="$(uname -s)"
is_windows=0
case "$os_name" in
    MINGW* | MSYS* | CYGWIN*) is_windows=1 ;;
esac

missing=()
optional_missing=()

command -v cppcheck >/dev/null 2>&1 || missing+=("cppcheck")
command -v clang-tidy >/dev/null 2>&1 || missing+=("clang-tidy")
command -v clang-format >/dev/null 2>&1 || missing+=("clang-format")

# bear (compile_commands.json fallback for old CubeIDE) has no solid native
# Windows build. On Windows it's advisory only -- CubeIDE's native
# "Generate compile_commands.json" export checkbox is the primary path
# everywhere and doesn't need bear at all.
if [ "$is_windows" -eq 1 ]; then
    command -v bear >/dev/null 2>&1 || optional_missing+=("bear")
else
    command -v bear >/dev/null 2>&1 || missing+=("bear")
fi

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
        echo "required on Windows; use CubeIDE's native export instead."
    fi
    exit 0
fi

echo "MISRA toolchain: missing tools: ${missing[*]}"
echo ""
case "$os_name" in
    Linux*)
        echo "Install with:"
        echo "  sudo apt-get update && sudo apt-get install -y cppcheck clang-tidy clang-format bear"
        echo "  curl -LsSf https://astral.sh/uv/install.sh | sh   # or: sudo apt-get install -y python3-pip"
        ;;
    Darwin*)
        echo "Install with:"
        echo "  brew install cppcheck llvm bear uv"
        ;;
    MINGW* | MSYS* | CYGWIN*)
        echo "Windows (Git Bash) -- install natively, then make sure each is on PATH:"
        echo "  cppcheck:                https://cppcheck.sourceforge.io/ (Windows installer)"
        echo "  clang-tidy/clang-format: https://releases.llvm.org/ (LLVM Windows installer)"
        echo "  uv:                      winget install --id=astral-sh.uv -e   (or: pip install uv)"
        echo "  (bear is not required on Windows -- use STM32CubeIDE's native"
        echo "   'Generate compile_commands.json' checkbox instead of the bear fallback)"
        ;;
    *)
        echo "Unsupported OS for auto-suggested install command; install manually: ${missing[*]}"
        ;;
esac

exit 1

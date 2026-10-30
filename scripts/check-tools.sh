#!/usr/bin/env bash
set -euo pipefail

os_name="$(uname -s)"
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

missing=()
optional_missing=()

command -v cppcheck >/dev/null 2>&1 || missing+=("cppcheck")
command -v clang-tidy >/dev/null 2>&1 || missing+=("clang-tidy")
CLANG_FORMAT_MINIMUM="23.1.2"
if ! command -v clang-format >/dev/null 2>&1; then
    missing+=("clang-format>=$CLANG_FORMAT_MINIMUM")
else
    clang_format_version="$(clang-format --version)"
    if [[ "$clang_format_version" =~ version[[:space:]]+([0-9]+)\.([0-9]+)\.([0-9]+) ]]; then
        clang_format_major="${BASH_REMATCH[1]}"
        clang_format_minor="${BASH_REMATCH[2]}"
        clang_format_patch="${BASH_REMATCH[3]}"
        if (( clang_format_major < 23 ||
              (clang_format_major == 23 && clang_format_minor < 1) ||
              (clang_format_major == 23 && clang_format_minor == 1 && clang_format_patch < 2) )); then
            missing+=("clang-format>=$CLANG_FORMAT_MINIMUM (found: $clang_format_version)")
        fi
    else
        missing+=("clang-format>=$CLANG_FORMAT_MINIMUM (unrecognized version: $clang_format_version)")
    fi
fi
# unit-test.sh and gen_compile_db.sh (cmake --preset Debug) build with CMake + Ninja; ctest ships with cmake.
command -v cmake >/dev/null 2>&1 || missing+=("cmake")
source "$script_dir/resolve-ninja.sh"
resolve_ninja || missing+=("ninja")

# Unit tests need a host compiler that can link native executables. Merely
# finding clang is insufficient on Windows when the Windows SDK is missing.
if ! "$script_dir/check-host-compiler.sh"; then
    missing+=("host-compiler (compile/link check failed)")
fi

# bear (compile_commands.json fallback for old CubeIDE) has no solid native
# Windows build, and isn't needed on any OS as long as CubeIDE's native
# "Generate compile_commands.json" export checkbox is used -- that's the
# primary path everywhere. Advisory only, on every platform.
command -v bear >/dev/null 2>&1 || optional_missing+=("bear")

command -v uv >/dev/null 2>&1 || missing+=("uv (required to install pre-commit)")

if [ "${#missing[@]}" -eq 0 ]; then
    echo "MISRA toolchain: required tools found (including uv) and the host compiler passed its compile/link check."
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
        echo "  sudo apt-get update && sudo apt-get install -y cppcheck clang-tidy clang-format cmake ninja-build"
        echo "  curl -LsSf https://astral.sh/uv/install.sh | sh   # or: sudo apt-get install -y python3-pip"
        echo "  (bear not required -- use STM32CubeIDE's native 'Generate compile_commands.json'"
        echo "   checkbox instead; sudo apt-get install -y bear only if you need the fallback)"
        ;;
    Darwin*)
        echo "Install with:"
        echo "  brew install cppcheck llvm cmake ninja uv"
        echo "  (bear not required -- use STM32CubeIDE's native 'Generate compile_commands.json'"
        echo "   checkbox instead; brew install bear only if you need the fallback)"
        ;;
    MINGW* | MSYS* | CYGWIN*)
        echo "Windows (Git Bash) -- winget ships with Windows 10/11, no separate install needed:"
        echo "  winget install --id Cppcheck.Cppcheck -e"
        echo "  winget install --id LLVM.LLVM -e            # clang-tidy + clang-format"
        echo "  winget install --id Kitware.CMake -e"
        echo "  winget install --id Ninja-build.Ninja -e"
        echo "  winget install --id astral-sh.uv -e"
        echo "  uv tool install 'clang-format>=$CLANG_FORMAT_MINIMUM'"
        echo "  For host unit tests, also install Visual Studio Build Tools with the C++ workload and Windows SDK,"
        echo "  or MSYS2 MinGW-w64 GCC. LLVM Clang alone may not include Windows SDK libraries."
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

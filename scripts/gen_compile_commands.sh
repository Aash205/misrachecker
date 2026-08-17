#!/usr/bin/env bash
set -euo pipefail

PROJECT_DIR="${1:?usage: gen_compile_commands.sh <cubeide-project-dir>}"

# CubeIDE writes compile_commands.json under whichever build config
# directory was actually built (Debug/, Release/, or a custom-named
# config) -- scan every immediate subdirectory rather than assuming
# "Debug", and pick the most recently built one if more than one exists.
NATIVE_JSON=""
for cfg_dir in "$PROJECT_DIR"/*/; do
    candidate="${cfg_dir}compile_commands.json"
    if [ -f "$candidate" ]; then
        if [ -z "$NATIVE_JSON" ] || [ "$candidate" -nt "$NATIVE_JSON" ]; then
            NATIVE_JSON="$candidate"
        fi
    fi
done

if [ -n "$NATIVE_JSON" ]; then
    echo "Found native compile_commands.json (CubeIDE CDT export) at $NATIVE_JSON"
    cp "$NATIVE_JSON" "$PROJECT_DIR/compile_commands.json"
    exit 0
fi

echo "No native compile_commands.json found."
echo "Enable it in STM32CubeIDE: Project Properties > C/C++ Build > Settings >"
echo "check 'Generate compile_commands.json', then rebuild and re-run this script."
echo ""

case "$(uname -s)" in
    MINGW* | MSYS* | CYGWIN*)
        echo "ERROR: no bear fallback on Windows -- bear has no solid native Windows build."
        echo "Use the native CubeIDE export checkbox above instead (works identically on"
        echo "every platform, no bear needed)." >&2
        exit 1
        ;;
esac

echo "Falling back to bear + headless CubeIDE build."
echo "This requires STM32CubeIDE installed and 'bear' on PATH."

command -v bear >/dev/null 2>&1 || {
    echo "ERROR: bear not found. Install it (see scripts/check-tools.sh) and retry." >&2
    exit 1
}

STM32CUBEIDE_BIN="${STM32CUBEIDE_BIN:?set STM32CUBEIDE_BIN to the stm32cubeide executable path}"
STM32CUBEIDE_WORKSPACE="${STM32CUBEIDE_WORKSPACE:?set STM32CUBEIDE_WORKSPACE to your CubeIDE workspace path}"

bear -- "$STM32CUBEIDE_BIN" \
    -nosplash \
    -application org.eclipse.cdt.managedbuilder.core.headlessbuild \
    -data "$STM32CUBEIDE_WORKSPACE" \
    -cleanBuild "$(basename "$PROJECT_DIR")"

mv compile_commands.json "$PROJECT_DIR/compile_commands.json"
echo "Generated $PROJECT_DIR/compile_commands.json via headless build."

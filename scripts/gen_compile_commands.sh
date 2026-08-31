#!/usr/bin/env bash
set -euo pipefail

PROJECT_DIR="${1:?usage: gen_compile_commands.sh <cubeide-project-dir | cmake-source-dir>}"

# Two build systems write a native compile_commands.json here, at two
# different depths:
#   - CubeIDE (classic managed-build): <cfg>/compile_commands.json, one
#     level down (Debug/, Release/, or a custom config name).
#   - STM32Cube VS Code extension's CMake toolchain: CMakePresets.json
#     defaults to binaryDir "${sourceDir}/build/${presetName}", so it's
#     two levels down (build/Debug/compile_commands.json). A depth-1-only
#     scan misses this entirely and falls through to the CubeIDE/bear
#     fallback below, which does nothing useful for a CMake project.
# Search a few levels deep and pick the most recently built one if more
# than one exists (e.g. leftover CubeIDE Debug/ alongside a CMake build/).
NATIVE_JSON=""
while IFS= read -r -d '' candidate; do
    if [ -z "$NATIVE_JSON" ] || [ "$candidate" -nt "$NATIVE_JSON" ]; then
        NATIVE_JSON="$candidate"
    fi
done < <(find "$PROJECT_DIR" -mindepth 2 -maxdepth 4 -name compile_commands.json -print0 2>/dev/null)

# clang-tidy/clangd prefer compile_flags.txt over compile_commands.json
# when BOTH exist in the same directory (verified empirically -- the
# opposite of the commonly assumed precedence). Remove it once a real
# compile_commands.json exists so there's no ambiguity; scripts/setup.sh
# regenerates it if you ever need the fallback again.
remove_stale_compile_flags() {
    local flags_file="$PROJECT_DIR/compile_flags.txt"
    if [ -f "$flags_file" ]; then
        rm -f "$flags_file"
        echo "Removed $flags_file (stale fallback -- compile_commands.json now takes over)."
    fi
}

# CubeIDE's own "directory" field is the project root, but every -I flag
# in "command" is relative (e.g. -I../Core/Inc), written as if resolved
# from the build-config dir (Debug/) one level below root -- that's the
# actual cwd the compiler ran from. clang-tidy/clangd resolve relative -I
# paths against "directory" per the compile_commands.json spec, so as
# shipped every relative include resolves one level ABOVE the project and
# silently fails to find any header (verified against a real CubeIDE
# export). Patch "directory" to the real build dir so relative -I
# resolution matches what the compiler actually saw.
fix_directory_field() {
    local json_file="$1" cfg_basename="$2"
    python3 - "$json_file" "$cfg_basename" <<'PY'
import json, sys

path, cfg = sys.argv[1], sys.argv[2]
with open(path) as f:
    entries = json.load(f)

suffix = "/" + cfg
fixed = 0
for e in entries:
    d = e.get("directory", "").rstrip("/\\")
    if not d.lower().endswith(suffix.lower()):
        e["directory"] = d + suffix
        fixed += 1

if fixed:
    with open(path, "w") as f:
        json.dump(entries, f, indent=2)
    print(f"Fixed 'directory' field in {fixed} entr{'y' if fixed == 1 else 'ies'} "
          f"(CubeIDE wrote the project root instead of the build dir '{cfg}', "
          "breaking every relative -I path).")
PY
}

if [ -n "$NATIVE_JSON" ]; then
    echo "Found native compile_commands.json (CubeIDE CDT export or CMake build dir) at $NATIVE_JSON"
    cp "$NATIVE_JSON" "$PROJECT_DIR/compile_commands.json"
    fix_directory_field "$PROJECT_DIR/compile_commands.json" "$(basename "$(dirname "$NATIVE_JSON")")"
    remove_stale_compile_flags
    exit 0
fi

echo "No native compile_commands.json found."
echo "CubeIDE: Project Properties > C/C++ Build > Settings > check 'Generate"
echo "compile_commands.json', then rebuild and re-run this script."
echo "STM32Cube VS Code extension (CMake): run the CMake configure step at least"
echo "once (Debug or Release preset) so build/<preset>/compile_commands.json"
echo "exists, then re-run this script."
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
remove_stale_compile_flags
echo "Generated $PROJECT_DIR/compile_commands.json via headless build."

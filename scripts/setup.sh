#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

install_uv_if_missing() {
    command -v uv >/dev/null 2>&1 || curl -LsSf https://astral.sh/uv/install.sh | sh
}

case "$(uname -s)" in
    Linux*)
        echo "Installing tools via apt..."
        sudo apt-get update
        sudo apt-get install -y cppcheck clang-tidy clang-format bear
        install_uv_if_missing
        ;;
    Darwin*)
        echo "Installing tools via brew..."
        brew install cppcheck llvm bear
        install_uv_if_missing
        ;;
    MINGW* | MSYS* | CYGWIN*)
        echo "Installing tools via winget (ships with Windows 10/11, no separate install)..."
        command -v winget >/dev/null 2>&1 || {
            echo "ERROR: winget not found. Get it from the Microsoft Store (App Installer)," >&2
            echo "or install manually instead:" >&2
            echo "  https://cppcheck.sourceforge.io/  and  https://releases.llvm.org/" >&2
            exit 1
        }
        # winget exits non-zero for an already-installed package, which would
        # kill the rest of this script under set -e -- skip the call entirely
        # when the tool is already on PATH, and tolerate winget's own exit
        # code otherwise so a real failure doesn't abort remaining installs
        # either (check-tools.sh at the end reports anything still missing).
        command -v cppcheck >/dev/null 2>&1 || winget install --id Cppcheck.Cppcheck -e --accept-source-agreements --accept-package-agreements || true
        command -v clang-tidy >/dev/null 2>&1 || winget install --id LLVM.LLVM -e --accept-source-agreements --accept-package-agreements || true
        command -v uv >/dev/null 2>&1 || winget install --id astral-sh.uv -e --accept-source-agreements --accept-package-agreements || true
        ;;
    *)
        echo "Unsupported OS: $(uname -s)" >&2
        exit 1
        ;;
esac

"$SCRIPT_DIR/install-hooks.sh"

echo ""
"$SCRIPT_DIR/check-tools.sh"
echo ""
echo "Setup complete. Run ./scripts/lint.sh to lint this repo's source."

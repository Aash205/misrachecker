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
        winget install --id Cppcheck.Cppcheck -e --accept-source-agreements --accept-package-agreements
        winget install --id LLVM.LLVM -e --accept-source-agreements --accept-package-agreements
        command -v uv >/dev/null 2>&1 || winget install --id astral-sh.uv -e --accept-source-agreements --accept-package-agreements
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
echo "Setup complete. Try: ./scripts/lint.sh demo"

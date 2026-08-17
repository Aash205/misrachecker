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
        echo "Installing tools via choco (Windows)..."
        command -v choco >/dev/null 2>&1 || {
            echo "ERROR: choco not found. Install Chocolatey first: https://chocolatey.org/install" >&2
            exit 1
        }
        choco install cppcheck llvm -y
        install_uv_if_missing
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

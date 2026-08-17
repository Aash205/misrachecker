#!/usr/bin/env bash
set -euo pipefail

if ! command -v pre-commit >/dev/null 2>&1; then
    if command -v uv >/dev/null 2>&1; then
        echo "pre-commit not found. Installing via uv..."
        uv tool install pre-commit
    elif command -v pip3 >/dev/null 2>&1 || command -v pip >/dev/null 2>&1; then
        echo "pre-commit not found. Installing via pip..."
        pip_cmd="$(command -v pip3 || command -v pip)"
        "$pip_cmd" install --user pre-commit
    else
        echo "ERROR: need uv or pip to install pre-commit. Install one:" >&2
        echo "  uv (recommended): curl -LsSf https://astral.sh/uv/install.sh | sh" >&2
        echo "  pip: install Python (pip ships with it) from https://www.python.org/" >&2
        exit 1
    fi
fi

pre-commit install

echo "Pre-commit hooks installed."
echo "Every commit will now auto-format staged C/C++ files (clang-format)"
echo "and run MISRA lint (cppcheck MISRA C + clang-tidy best-effort C++)"
echo "against staged files only. A formatting fix blocks that commit once"
echo "(re-stage and commit again) -- standard pre-commit behavior."

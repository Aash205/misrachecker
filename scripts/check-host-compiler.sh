#!/usr/bin/env bash
set -euo pipefail

# Match the host compiler selection used by unit-test.sh.
if command -v gcc >/dev/null 2>&1 && command -v g++ >/dev/null 2>&1; then
    HOST_CC=gcc
elif command -v clang >/dev/null 2>&1 && command -v clang++ >/dev/null 2>&1; then
    HOST_CC=clang
else
    echo "Host unit-test compiler missing: install a gcc/g++ or clang/clang++ pair." >&2
    exit 1
fi

probe_dir="$(mktemp -d)"
trap 'rm -rf "$probe_dir"' EXIT
cat > "$probe_dir/probe.c" <<'EOF'
int main(void)
{
    return 0;
}
EOF

if ! "$HOST_CC" "$probe_dir/probe.c" -o "$probe_dir/probe" >"$probe_dir/compiler.log" 2>&1; then
    echo "Host compiler '$HOST_CC' is present but cannot compile and link a native executable." >&2
    if [[ "$(uname -s)" == MINGW* || "$(uname -s)" == MSYS* || "$(uname -s)" == CYGWIN* ]]; then
        echo "On Windows, install Visual Studio Build Tools with the C++ workload and Windows SDK," >&2
        echo "or install MSYS2 MinGW-w64 GCC and put its bin directory on PATH." >&2
    fi
    cat "$probe_dir/compiler.log" >&2
    exit 1
fi

echo "Host unit-test compiler: $HOST_CC can compile and link a native executable."

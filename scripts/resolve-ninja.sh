#!/usr/bin/env bash

resolve_ninja() {
    command -v ninja >/dev/null 2>&1 && return 0

    case "$(uname -s)" in
        MINGW* | MSYS* | CYGWIN*)
            if [ -n "${LOCALAPPDATA:-}" ] && command -v cygpath >/dev/null 2>&1; then
                local bundle_root ninja_bin
                bundle_root="$(cygpath -u "$LOCALAPPDATA")/stm32cube/bundles/ninja"
                for ninja_bin in "$bundle_root"/*/bin; do
                    if [ -f "$ninja_bin/ninja.exe" ]; then
                        PATH="$ninja_bin:$PATH"
                        export PATH
                    fi
                done
            fi
            ;;
    esac

    command -v ninja >/dev/null 2>&1
}

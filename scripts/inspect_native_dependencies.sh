#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 1 || ! -f "$1" ]]; then
    echo "usage: $0 /path/to/executable" >&2
    exit 2
fi

binary="$1"
case "$(uname -s)" in
    Linux*)
        dependencies="$(ldd "$binary")"
        printf '%s\n' "$dependencies"
        if grep -q 'not found' <<<"$dependencies"; then
            echo "unresolved native dependency in $binary" >&2
            exit 1
        fi
        ;;
    Darwin*)
        dependencies="$(otool -L "$binary")"
        printf '%s\n' "$dependencies"
        ;;
    MINGW*|MSYS*|CYGWIN*)
        dependencies="$(ldd "$binary")"
        printf '%s\n' "$dependencies"
        if grep -q 'not found' <<<"$dependencies"; then
            echo "unresolved native dependency in $binary" >&2
            exit 1
        fi
        ;;
    *)
        echo "unsupported dependency-inspection host: $(uname -s)" >&2
        exit 2
        ;;
esac

if [[ "${MOG_REQUIRE_STATIC_OPENSSL:-0}" == 1 ]] && \
   grep -Eiq '(^|[/\\])lib(ssl|crypto)[^/\\]*\.(so|dylib|dll)' <<<"${dependencies:-}"; then
    echo "release binary dynamically links OpenSSL despite MOG_STATIC_OPENSSL" >&2
    exit 1
fi

#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 2 || ! -f "$1" ]]; then
    echo "usage: $0 PACKAGE.vsix TARGET" >&2
    exit 2
fi

vsix="$(cd "$(dirname "$1")" && pwd -P)/$(basename "$1")"
target="$2"
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
extract_dir="$(mktemp -d "${TMPDIR:-/tmp}/mog-vsix.XXXXXX")"
trap 'rm -rf "$extract_dir"' EXIT

(cd "$extract_dir" && cmake -E tar xvf "$vsix" >/dev/null)
extension_dir="$extract_dir/extension"
server_name=mog-lsp
[[ "$target" == win32-* ]] && server_name=mog-lsp.exe
server="$extension_dir/runtime/$target/$server_name"

if [[ ! -f "$server" ]]; then
    echo "VSIX does not contain runtime/$target/$server_name" >&2
    exit 1
fi
if [[ "$target" != win32-* && ! -x "$server" ]]; then
    echo "VSIX language server is not stored as executable: runtime/$target/$server_name" >&2
    exit 1
fi
chmod +x "$server"

if find "$extension_dir" -type f \
    \( -name '*.pem' -o -name '*.key' -o -name '.env' -o -name '*.vsix' \) \
    -print -quit | grep -q .; then
    echo "VSIX contains a forbidden credential or nested-package file" >&2
    exit 1
fi

if find "$extension_dir" -type f -size +75M -print -quit | grep -q .; then
    echo "VSIX contains an unexpected file larger than 75 MiB" >&2
    exit 1
fi

bash "$repo_root/tests/test_lsp_smoke.sh" "$server"
MOG_REQUIRE_STATIC_OPENSSL=1 bash "$repo_root/scripts/inspect_native_dependencies.sh" "$server"
find "$extension_dir" -type f -print | sort

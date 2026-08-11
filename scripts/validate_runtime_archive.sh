#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 2 || ! -f "$1" ]]; then
    echo "usage: $0 ARCHIVE EXPECTED_VERSION" >&2
    exit 2
fi

archive="$(cd "$(dirname "$1")" && pwd -P)/$(basename "$1")"
expected_version="$2"
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
extract_dir="$(mktemp -d "${TMPDIR:-/tmp}/mog-runtime-archive.XXXXXX")"
trap 'rm -rf "$extract_dir"' EXIT

case "$archive" in
    *.tar.gz|*.tgz) tar -xzf "$archive" -C "$extract_dir" ;;
    *.zip) (cd "$extract_dir" && cmake -E tar xvf "$archive" >/dev/null) ;;
    *) echo "unsupported archive type: $archive" >&2; exit 2 ;;
esac

mog_bin="$(find "$extract_dir" -type f \( -name mog -o -name mog.exe \) | head -n 1)"
lsp_bin="$(find "$extract_dir" -type f \( -name mog-lsp -o -name mog-lsp.exe \) | head -n 1)"
if [[ -z "$mog_bin" || -z "$lsp_bin" ]]; then
    echo "archive must contain both mog and mog-lsp" >&2
    exit 1
fi
chmod +x "$mog_bin" "$lsp_bin"

actual_version="$("$mog_bin" --version)"
if [[ "$actual_version" != "mog $expected_version (native ABI 3)" ]]; then
    echo "unexpected archived runtime version: $actual_version" >&2
    exit 1
fi

bash "$repo_root/tests/test_lsp_smoke.sh" "$lsp_bin"
MOG_REQUIRE_STATIC_OPENSSL=1 bash "$repo_root/scripts/inspect_native_dependencies.sh" "$mog_bin"
MOG_REQUIRE_STATIC_OPENSSL=1 bash "$repo_root/scripts/inspect_native_dependencies.sh" "$lsp_bin"

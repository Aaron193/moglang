#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
extension_dir="$repo_root/tooling/vscode-mog"
output="${1:-$repo_root/build/vscode-mog-development.vsix}"

case "$(uname -s):$(uname -m)" in
    Linux:x86_64) target=linux-x64; executable=mog-lsp ;;
    Darwin:arm64) target=darwin-arm64; executable=mog-lsp ;;
    MINGW*:x86_64|MSYS*:x86_64|CYGWIN*:x86_64)
        target=win32-x64
        executable=mog-lsp.exe
        ;;
    *)
        echo "No development VSIX target for $(uname -s) $(uname -m)" >&2
        exit 2
        ;;
esac

server="${MOG_LSP_PATH:-$repo_root/build/tooling-debug/$executable}"
if [[ ! -x "$server" ]]; then
    for candidate in \
        "$repo_root/build/tooling-debug/$executable" \
        "$repo_root/build/tooling-debug/Debug/$executable" \
        "$repo_root/build/tooling-debug/Release/$executable"; do
        if [[ -x "$candidate" ]]; then
            server="$candidate"
            break
        fi
    done
fi
if [[ ! -x "$server" ]]; then
    echo "Language server not found at $server; run the build task first" >&2
    exit 1
fi

runtime_dir="$extension_dir/runtime/$target"
staged_server="$runtime_dir/$executable"
mkdir -p "$runtime_dir" "$(dirname "$output")"
trap 'rm -f "$staged_server"' EXIT
cp "$server" "$staged_server"

(
    cd "$extension_dir"
    npm run package -- --target "$target" --out "$output"
)
bash "$repo_root/scripts/validate_vsix.sh" "$output" "$target"

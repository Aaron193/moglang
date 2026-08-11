#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
LSP_BIN="${1:-$PROJECT_ROOT/build/mog-lsp}"
if [[ -d "$LSP_BIN" ]]; then
    if [[ -x "$LSP_BIN/mog-lsp.exe" ]]; then
        LSP_BIN="$LSP_BIN/mog-lsp.exe"
    else
        LSP_BIN="$LSP_BIN/mog-lsp"
    fi
fi
if [[ ! -x "$LSP_BIN" ]]; then
    echo "LSP binary not found at $LSP_BIN" >&2
    echo "Usage: $0 /path/to/mog-lsp-or-build-directory" >&2
    exit 1
fi

python3 - "$LSP_BIN" <<'PY'
import json
import subprocess
import sys

proc = subprocess.Popen([sys.argv[1]], stdin=subprocess.PIPE,
                        stdout=subprocess.PIPE, stderr=subprocess.PIPE)

def send(message):
    body = json.dumps(message).encode()
    proc.stdin.write(f"Content-Length: {len(body)}\r\n\r\n".encode() + body)
    proc.stdin.flush()

def receive():
    headers = {}
    while True:
        line = proc.stdout.readline()
        if not line:
            raise RuntimeError(proc.stderr.read().decode(errors="replace"))
        if line in (b"\r\n", b"\n"):
            break
        key, value = line.decode().split(":", 1)
        headers[key.lower()] = value.strip()
    return json.loads(proc.stdout.read(int(headers["content-length"])))

send({"jsonrpc": "2.0", "id": 1, "method": "initialize", "params": {}})
reply = receive()
assert reply["id"] == 1 and "capabilities" in reply["result"], reply
assert reply["result"]["capabilities"]["positionEncoding"] == "utf-16", reply
assert reply["result"]["mog"]["toolingProtocolVersion"], reply
send({"jsonrpc": "2.0", "id": 2, "method": "shutdown", "params": {}})
assert receive().get("id") == 2
send({"jsonrpc": "2.0", "method": "exit", "params": {}})
proc.stdin.close()
assert proc.wait(timeout=10) == 0
print("[PASS] mog-lsp initialize/shutdown smoke")
PY

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
[[ -x "$LSP_BIN" ]] || { echo "LSP binary not found: $LSP_BIN" >&2; exit 1; }

python3 - "$LSP_BIN" <<'PY'
import json, subprocess, sys, tempfile
from pathlib import Path

p = subprocess.Popen([sys.argv[1]], stdin=subprocess.PIPE, stdout=subprocess.PIPE)
def frame(value):
    body = json.dumps(value, ensure_ascii=True).encode()
    return f"Content-Length: {len(body)}\r\n\r\n".encode() + body
def recv():
    headers = {}
    while True:
        line = p.stdout.readline()
        assert line
        if line in (b"\n", b"\r\n"): break
        key, value = line.decode().split(":", 1)
        headers[key.lower()] = value.strip()
    return json.loads(p.stdout.read(int(headers["content-length"])))
def until(request_id):
    while True:
        message = recv()
        if message.get("id") == request_id: return message

with tempfile.TemporaryDirectory(prefix="mog lsp unicode ") as tmp:
    root = Path(tmp)
    # Partial transport writes and escaped non-BMP workspace names exercise
    # framing plus JSON surrogate-pair decoding.
    init = frame({"jsonrpc":"2.0","id":1,"method":"initialize","params":{
        "workspaceFolders":[{"uri":root.as_uri(),"name":"Mog \U0001f680"}]}})
    p.stdin.write(init[:13]); p.stdin.flush()
    p.stdin.write(init[13:]); p.stdin.flush()
    initialized = until(1)
    assert initialized["result"]["capabilities"]["positionEncoding"] == "utf-16"

    source = '/*\U0001f680*/ const Value i32 = 1\nprint(Value)\n'
    source_path = root / "\u5de5\u5177.mog"
    source_path.write_text(source, encoding="utf-8")
    p.stdin.write(frame({"jsonrpc":"2.0","method":"textDocument/didOpen","params":{
        "textDocument":{"uri":source_path.as_uri(),"languageId":"mog",
                        "version":1,"text":source}}}))
    p.stdin.flush()
    while recv().get("method") != "textDocument/publishDiagnostics": pass
    value_utf16 = len(source.split("Value", 1)[0].encode("utf-16-le")) // 2
    p.stdin.write(frame({"jsonrpc":"2.0","id":5,"method":"textDocument/hover","params":{
        "textDocument":{"uri":source_path.as_uri()},
        "position":{"line":0,"character":value_utf16}}}))
    p.stdin.flush()
    hover = until(5)
    assert hover.get("result") is not None, hover
    assert hover["result"]["range"]["start"]["character"] == value_utf16, hover

    broken = root / "broken-project"
    broken.mkdir()
    (broken / "mog.toml").write_text(
        'kind = "project"\nname = "broken"\nversion = "0.1.0"\n'
        '[dependencies]\nmissing = { path = "does-not-exist", '
        'package = "test:missing", version = "0.1.0" }\n', encoding="utf-8")
    p.stdin.write(frame({"jsonrpc":"2.0","id":6,
                         "method":"mog/installProjectDependencies",
                         "params":{"projectRoot":str(broken)}}))
    p.stdin.flush()
    install_failure = until(6)
    assert install_failure["error"]["code"] == -32001, install_failure
    # MSYS Python uses /tmp/... while the native Windows server reports the
    # same directory as a drive-qualified path. Verify the stable project
    # identity without requiring one platform's absolute spelling.
    assert broken.name in install_failure["error"]["message"], install_failure

    # Multiple messages in one write must retain their framing boundaries.
    p.stdin.write(frame({"jsonrpc":"2.0","id":2,"method":"mog/unknown","params":{}}) +
                  frame({"jsonrpc":"2.0","method":"$/cancelRequest","params":{"id":3}}) +
                  frame({"jsonrpc":"2.0","id":3,"method":"workspace/symbol","params":{"query":""}}))
    p.stdin.flush()
    assert until(2)["error"]["code"] == -32601
    assert until(3)["error"]["code"] == -32800

    p.stdin.write(b"Content-Length: nope\r\n\r\n"); p.stdin.flush()
    assert recv()["error"]["code"] == -32700
    p.stdin.write(b"Content-Length: 1\r\n\r\n{"); p.stdin.flush()
    assert recv()["error"]["code"] == -32700
    p.stdin.write(frame({"jsonrpc":"2.0","method":"workspace/didChangeWorkspaceFolders",
                         "params":{"event":{"added":[],"removed":[{"uri":root.as_uri(),"name":"x"}]}}}) +
                  frame({"jsonrpc":"2.0","id":4,"method":"shutdown","params":{}}) +
                  frame({"jsonrpc":"2.0","method":"exit","params":{}}))
    p.stdin.flush()
    assert until(4)["result"] is None
    p.stdin.close()
    assert p.wait(timeout=10) == 0

abnormal = subprocess.Popen([sys.argv[1]], stdin=subprocess.PIPE,
                            stdout=subprocess.PIPE, stderr=subprocess.PIPE)
abnormal.stdin.close()
assert abnormal.wait(timeout=10) != 0
print("[PASS] mog-lsp protocol hardening")
PY

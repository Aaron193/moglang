#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
MOG="$PROJECT_ROOT/build/interpreter"

if [[ ! -x "$MOG" ]]; then
    echo "Interpreter not found at $MOG"
    echo "Build first with: $PROJECT_ROOT/build.sh"
    exit 1
fi

TEMP_DIR="$(mktemp -d)"
REMOTE_DIR=""
WORKSPACE_DIR=""
RANGE_DIR=""
ADD_DIR=""
ADD_RANGE_DIR=""
PUBLISH_WORKSPACE=""
PUBLISHED_GREETER_DIR=""
DIGEST_DIR=""
NATIVE_PUBLISH_WORKSPACE=""
NATIVE_EXTERNAL_BUNDLE_DIR=""
NATIVE_CONSUMER_DIR=""
NATIVE_BAD_DIR=""
NATIVE_SOURCE_DIR=""
NATIVE_CROSS_TARGET_DIR=""
NATIVE_CROSS_TARGET_MANIFEST_DIR=""
NATIVE_CROSS_TARGET_OVERRIDE_DIR=""
NATIVE_CROSS_TARGET_BAD_TOOLCHAIN_DIR=""
NATIVE_CROSS_TARGET_NO_BUILD_DIR=""
NATIVE_NO_CMAKE_DIR=""
NATIVE_BUILD_FAIL_DIR=""
NATIVE_SYSDEP_FAIL_DIR=""
NATIVE_TARGET_DIR=""
NATIVE_TARGET_FAIL_DIR=""
WINDOW_PUBLISH_DIR=""
WINDOW_BUNDLE_ROOT=""
NATIVE_CROSS_TARGET_ENV_DIR=""
HOSTED_REGISTRY_DIR=""
HOSTED_PUBLISH_WORKSPACE=""
HOSTED_CONSUMER_DIR=""
GIT_REPO_DIR=""
GIT_CONSUMER_DIR=""
GIT_OFFLINE_FAIL_DIR=""
POLICY_REGISTRY_DIR=""
POLICY_NATIVE_DIR=""
POLICY_CI_DIR=""
REMOVE_DIR=""
REMOVE_DEV_DIR=""
SCRIPT_WORKFLOW_DIR=""
SCRIPT_MISSING_DIR=""
SCRIPT_INVALID_ABS_DIR=""
SCRIPT_INVALID_EXT_DIR=""
SCRIPT_INVALID_ESCAPE_DIR=""
CACHE_STATUS_DIR=""
CACHE_PRUNE_DIR=""
LEGACY_SOURCE_PROJECT=""
HOSTED_SERVER_PID=""
trap 'if [[ -n "${HOSTED_SERVER_PID:-}" ]]; then kill "${HOSTED_SERVER_PID}" >/dev/null 2>&1 || true; fi; rm -rf "${TEMP_DIR:-}" "${REMOTE_DIR:-}" "${WORKSPACE_DIR:-}" "${RANGE_DIR:-}" "${ADD_DIR:-}" "${ADD_RANGE_DIR:-}" "${PUBLISH_WORKSPACE:-}" "${PUBLISHED_GREETER_DIR:-}" "${DIGEST_DIR:-}" "${NATIVE_PUBLISH_WORKSPACE:-}" "${NATIVE_EXTERNAL_BUNDLE_DIR:-}" "${NATIVE_CONSUMER_DIR:-}" "${NATIVE_BAD_DIR:-}" "${NATIVE_SOURCE_DIR:-}" "${NATIVE_CROSS_TARGET_DIR:-}" "${NATIVE_CROSS_TARGET_MANIFEST_DIR:-}" "${NATIVE_CROSS_TARGET_OVERRIDE_DIR:-}" "${NATIVE_CROSS_TARGET_BAD_TOOLCHAIN_DIR:-}" "${NATIVE_CROSS_TARGET_NO_BUILD_DIR:-}" "${NATIVE_NO_CMAKE_DIR:-}" "${NATIVE_BUILD_FAIL_DIR:-}" "${NATIVE_SYSDEP_FAIL_DIR:-}" "${NATIVE_TARGET_DIR:-}" "${NATIVE_TARGET_FAIL_DIR:-}" "${WINDOW_PUBLISH_DIR:-}" "${WINDOW_BUNDLE_ROOT:-}" "${NATIVE_CROSS_TARGET_ENV_DIR:-}" "${HOSTED_REGISTRY_DIR:-}" "${HOSTED_PUBLISH_WORKSPACE:-}" "${HOSTED_CONSUMER_DIR:-}" "${GIT_REPO_DIR:-}" "${GIT_CONSUMER_DIR:-}" "${GIT_OFFLINE_FAIL_DIR:-}" "${POLICY_REGISTRY_DIR:-}" "${POLICY_NATIVE_DIR:-}" "${POLICY_CI_DIR:-}" "${REMOVE_DIR:-}" "${REMOVE_DEV_DIR:-}" "${SCRIPT_WORKFLOW_DIR:-}" "${SCRIPT_MISSING_DIR:-}" "${SCRIPT_INVALID_ABS_DIR:-}" "${SCRIPT_INVALID_EXT_DIR:-}" "${SCRIPT_INVALID_ESCAPE_DIR:-}" "${CACHE_STATUS_DIR:-}" "${CACHE_PRUNE_DIR:-}" "${LEGACY_SOURCE_PROJECT:-}"' EXIT

detect_host_target() {
    local os
    local arch
    case "$(uname -s)" in
        Linux) os="linux" ;;
        Darwin) os="macos" ;;
        MINGW*|MSYS*|CYGWIN*) os="windows" ;;
        *) os="unknown" ;;
    esac

    case "$(uname -m)" in
        x86_64|amd64) arch="x86_64" ;;
        aarch64|arm64) arch="arm64" ;;
        i386|i686) arch="x86" ;;
        armv7l|armv6l|arm) arch="arm" ;;
        *) arch="unknown" ;;
    esac

    if [[ "$os" == "linux" ]]; then
        if command -v ldd >/dev/null 2>&1 && ldd --version 2>&1 | head -n1 | grep -qi musl; then
            printf '%s-%s-musl\n' "$os" "$arch"
            return
        fi
        printf '%s-%s-gnu\n' "$os" "$arch"
        return
    fi

    printf '%s-%s\n' "$os" "$arch"
}

HOST_TARGET="$(detect_host_target)"
ALT_TARGET="linux-arm64-gnu"
if [[ "$ALT_TARGET" == "$HOST_TARGET" ]]; then
    ALT_TARGET="macos-arm64"
fi

WINDOW_PACKAGE_SO="$PROJECT_ROOT/build/packages/mog/window/package.so"
WINDOW_PACKAGE_DYLIB="$PROJECT_ROOT/build/packages/mog/window/package.dylib"
WINDOW_PACKAGE_LIBRARY=""
WINDOW_PUBLISH_SCRIPT="$PROJECT_ROOT/scripts/publish_official_window.sh"
if [[ -f "$WINDOW_PACKAGE_SO" ]]; then
    WINDOW_PACKAGE_LIBRARY="$WINDOW_PACKAGE_SO"
elif [[ -f "$WINDOW_PACKAGE_DYLIB" ]]; then
    WINDOW_PACKAGE_LIBRARY="$WINDOW_PACKAGE_DYLIB"
fi

write_registry_index() {
    local registry_dir="$1"
    local mode="${2:-correct}"
    python3 - "$registry_dir" "$mode" <<'PY'
from pathlib import Path
import hashlib
import sys

registry_dir = Path(sys.argv[1])
mode = sys.argv[2]

def digest_directory(root: Path) -> str:
    files = sorted(path for path in root.rglob("*") if path.is_file())
    seed = bytearray()
    for path in files:
        seed.extend(path.relative_to(root).as_posix().encode("utf-8"))
        seed.extend(b"\n")
        seed.extend(path.read_bytes())
        seed.extend(b"\n")
    return "sha256:" + hashlib.sha256(seed).hexdigest()

records = []
for package_dir in sorted((registry_dir / "packages").glob("*/*/*")):
    namespace = package_dir.parent.parent.name
    package_name = package_dir.parent.name
    version = package_dir.name
    package_id = f"{namespace}:{package_name}"
    digest = digest_directory(package_dir)
    if mode == "digest-mismatch" and package_id == "acme:http" and version == "1.0.0":
        digest = "sha256:" + ("0" * 64)

    dependencies = []
    if package_id == "acme:http":
        dependencies = [f"acme:util@{version}"]

    records.append(
        f'''[[package]]
package_id = "{package_id}"
version = "{version}"
artifact_path = "{package_dir.relative_to(registry_dir).as_posix()}"
artifact_digest = "{digest}"
dependencies = {dependencies!r}
'''
    )

index = 'schema_version = "registry.v1"\n\n' + "\n".join(records)
(registry_dir / "index.toml").write_text(index.replace("'", '"'), encoding="utf-8")
PY
}

strip_registry_index_signature() {
    local registry_dir="$1"
    python3 - "$registry_dir" <<'PY'
from pathlib import Path
import sys

index_path = Path(sys.argv[1]) / "index.toml"
lines = []
for line in index_path.read_text(encoding="utf-8").splitlines():
    stripped = line.strip()
    if stripped.startswith('signing_key_id = ') or stripped.startswith('signature = '):
        continue
    lines.append(line)
index_path.write_text("\n".join(lines) + "\n", encoding="utf-8")
PY
}

create_signing_key() {
    local key_file="$1"
    local key_id="$2"
    local pem_file="${key_file%.toml}.pem"

    openssl genpkey -algorithm Ed25519 -out "$pem_file" >/dev/null 2>&1

    local private_der_b64
    private_der_b64="$(openssl pkey -in "$pem_file" -outform DER | \
        python3 -c 'import base64,sys; sys.stdout.write(base64.b64encode(sys.stdin.buffer.read()).decode("ascii"))')"

    local public_der_b64
    public_der_b64="$(openssl pkey -in "$pem_file" -pubout -outform DER | \
        python3 -c 'import base64,sys; sys.stdout.write(base64.b64encode(sys.stdin.buffer.read()).decode("ascii"))')"

    cat > "$key_file" <<EOF
schema_version = "registry-key.v1"
key_id = "$key_id"
algorithm = "ed25519"
private_key = "$private_der_b64"
public_key = "$public_der_b64"
EOF
}

create_public_key_file() {
    python3 - "$1" "$2" <<'PY'
from pathlib import Path
import sys

source_path = Path(sys.argv[1])
dest_path = Path(sys.argv[2])
fields = {}
for line in source_path.read_text(encoding="utf-8").splitlines():
    if "=" not in line:
        continue
    key, value = line.split("=", 1)
    fields[key.strip()] = value.strip().strip('"')

dest_path.write_text(
    '\n'.join([
        'schema_version = "registry-public-key.v1"',
        f'key_id = "{fields["key_id"]}"',
        f'algorithm = "{fields.get("algorithm", "ed25519")}"',
        f'public_key = "{fields["public_key"]}"',
        '',
    ]),
    encoding="utf-8",
)
PY
}

trusted_key_spec() {
    python3 - "$1" <<'PY'
from pathlib import Path
import sys

key_file = Path(sys.argv[1])
fields = {}
for line in key_file.read_text(encoding="utf-8").splitlines():
    if "=" not in line:
        continue
    key, value = line.split("=", 1)
    fields[key.strip()] = value.strip().strip('"')
print(f'{fields["key_id"]}:{fields["public_key"]}')
PY
}

write_signed_advisories() {
    local registry_dir="$1"
    local key_file="$2"
    local advisory_id="$3"
    local package_id="$4"
    local affected="$5"
    local severity="$6"
    local summary="$7"
    local fixed_version="${8:-}"
    local url="${9:-}"
    local pem_file="${key_file%.toml}.pem"
    local payload_path="$TEMP_DIR/advisories_payload.toml"
    local sig_path="$TEMP_DIR/advisories.sig"
    local key_id
    key_id="$(python3 - "$key_file" <<'PY'
from pathlib import Path
import sys

fields = {}
for line in Path(sys.argv[1]).read_text(encoding="utf-8").splitlines():
    if "=" not in line:
        continue
    key, value = line.split("=", 1)
    fields[key.strip()] = value.strip().strip('"')
print(fields["key_id"])
PY
)"

    python3 - "$payload_path" "$advisory_id" "$package_id" "$affected" \
        "$severity" "$summary" "$fixed_version" "$url" <<'PY'
from pathlib import Path
import sys

payload_path = Path(sys.argv[1])
advisory_id, package_id, affected, severity, summary, fixed_version, url = sys.argv[2:9]

parts = ['schema_version = "advisories.v1"', '', '[[advisory]]']
parts.append(f'id = "{advisory_id}"')
parts.append(f'package_id = "{package_id}"')
parts.append(f'affected = "{affected}"')
parts.append(f'severity = "{severity}"')
parts.append('summary = """')
parts.append(summary)
parts.append('"""')
if fixed_version:
    parts.append(f'fixed_version = "{fixed_version}"')
if url:
    parts.append(f'url = "{url}"')
payload_path.write_text("\n".join(parts) + "\n", encoding="utf-8")
PY

    openssl pkeyutl -sign -inkey "$pem_file" -rawin -in "$payload_path" \
        -out "$sig_path" >/dev/null 2>&1

    local signature_b64
    signature_b64="$(python3 - "$sig_path" <<'PY'
from pathlib import Path
import base64
import sys
sys.stdout.write(base64.b64encode(Path(sys.argv[1]).read_bytes()).decode("ascii"))
PY
)"

    python3 - "$registry_dir/advisories.toml" "$key_id" "$signature_b64" \
        "$payload_path" <<'PY'
from pathlib import Path
import sys

output_path = Path(sys.argv[1])
key_id = sys.argv[2]
signature = sys.argv[3]
payload_path = Path(sys.argv[4])
payload = payload_path.read_text(encoding="utf-8")
body = payload.split("\n", 1)[1] if "\n" in payload else ""
output_path.write_text(
    f'schema_version = "advisories.v1"\n'
    f'signing_key_id = "{key_id}"\n'
    f'signature = "{signature}"\n'
    f'{body}',
    encoding="utf-8",
)
PY
}

write_signed_registry_trust() {
    local output_path="$1"
    local signing_key_file="$2"
    local active_key_file="$3"
    local revoked_key_file="$4"
    local revoked_reason="${5:-}"
    local pem_file="${signing_key_file%.toml}.pem"
    local payload_path="$TEMP_DIR/registry_trust_payload.toml"
    local sig_path="$TEMP_DIR/registry_trust.sig"

    python3 - "$active_key_file" "$revoked_key_file" "$payload_path" \
        "$revoked_reason" <<'PY'
from pathlib import Path
import sys

def read_fields(path_str):
    fields = {}
    for line in Path(path_str).read_text(encoding="utf-8").splitlines():
        if "=" not in line:
            continue
        key, value = line.split("=", 1)
        fields[key.strip()] = value.strip().strip('"')
    return fields

active_fields = read_fields(sys.argv[1])
revoked_fields = read_fields(sys.argv[2])
payload_path = Path(sys.argv[3])
revoked_reason = sys.argv[4]

records = [
    {
        "key_id": active_fields["key_id"],
        "public_key": active_fields["public_key"],
        "status": "active",
        "reason": "",
    },
    {
        "key_id": revoked_fields["key_id"],
        "public_key": revoked_fields["public_key"],
        "status": "revoked",
        "reason": revoked_reason,
    },
]
records.sort(key=lambda record: record["key_id"])

parts = ['schema_version = "registry-trust.v1"']
for record in records:
    parts.extend([
        "",
        "[[key]]",
        f'key_id = "{record["key_id"]}"',
        f'public_key = "{record["public_key"]}"',
        f'status = "{record["status"]}"',
    ])
    if record["reason"]:
        parts.extend([
            'reason = """',
            record["reason"],
            '"""',
        ])
payload_path.write_text("\n".join(parts) + "\n", encoding="utf-8")
PY

    local signing_key_id
    signing_key_id="$(python3 - "$signing_key_file" <<'PY'
from pathlib import Path
import sys

fields = {}
for line in Path(sys.argv[1]).read_text(encoding="utf-8").splitlines():
    if "=" not in line:
        continue
    key, value = line.split("=", 1)
    fields[key.strip()] = value.strip().strip('"')
print(fields["key_id"])
PY
)"

    openssl pkeyutl -sign -inkey "$pem_file" -rawin -in "$payload_path" \
        -out "$sig_path" >/dev/null 2>&1

    local signature_b64
    signature_b64="$(python3 - "$sig_path" <<'PY'
from pathlib import Path
import base64
import sys
sys.stdout.write(base64.b64encode(Path(sys.argv[1]).read_bytes()).decode("ascii"))
PY
)"

    python3 - "$output_path" "$signing_key_id" "$signature_b64" \
        "$payload_path" <<'PY'
from pathlib import Path
import sys

output_path = Path(sys.argv[1])
key_id = sys.argv[2]
signature = sys.argv[3]
payload_path = Path(sys.argv[4])
payload = payload_path.read_text(encoding="utf-8")
body = payload.split("\n", 1)[1] if "\n" in payload else ""
output_path.write_text(
    f'schema_version = "registry-trust.v1"\n'
    f'signing_key_id = "{key_id}"\n'
    f'signature = "{signature}"\n'
    f'{body}',
    encoding="utf-8",
)
PY
}

start_hosted_registry_server() {
    local registry_dir="$1"
    local token="$2"
    local server_script="$TEMP_DIR/hosted_registry_server.py"
    local port
    port="$(python3 - <<'PY'
import socket
s = socket.socket()
s.bind(("127.0.0.1", 0))
print(s.getsockname()[1])
s.close()
PY
)"

    cat > "$server_script" <<'PY'
from http.server import ThreadingHTTPServer, SimpleHTTPRequestHandler
from pathlib import Path
import hashlib
import os
import sys

root = Path(sys.argv[1]).resolve()
port = int(sys.argv[2])
token = sys.argv[3]

class Handler(SimpleHTTPRequestHandler):
    def _relative_path(self):
        return self.path.split("?", 1)[0].split("#", 1)[0].lstrip("/")

    def translate_path(self, path):
        path = path.split("?", 1)[0].split("#", 1)[0]
        path = path.lstrip("/")
        return str((root / path).resolve())

    def _service_enabled(self):
        return (root / "registry-service.v1").is_file()

    def _emit_index_etag(self):
        return self._service_enabled() and not (root / "disable-index-etag").exists()

    def _index_etag(self):
        index_path = root / "index.toml"
        if not index_path.is_file():
            return None
        digest = hashlib.sha256(index_path.read_bytes()).hexdigest()
        return f'"{digest}"'

    def _authorized(self):
        path = self._relative_path()
        if path in ("registry-public-key.v1", "registry-service.v1", "registry-trust.v1"):
            return True
        if path.endswith("/registry-public-key.v1") or \
           path.endswith("/registry-service.v1") or \
           path.endswith("/registry-trust.v1"):
            return True
        return self.headers.get("Authorization", "") == f"Bearer {token}"

    def end_headers(self):
        if self.command == "GET" and self._relative_path() == "index.toml" and self._emit_index_etag():
            etag = self._index_etag()
            if etag is not None:
                self.send_header("ETag", etag)
        super().end_headers()

    def do_GET(self):
        if not self._authorized():
            self.send_response(401)
            self.end_headers()
            self.wfile.write(b"unauthorized")
            return
        super().do_GET()

    def do_PUT(self):
        if not self._authorized():
            self.send_response(401)
            self.end_headers()
            self.wfile.write(b"unauthorized")
            return
        relative_path = self._relative_path()
        target = Path(self.translate_path(self.path))
        if self._service_enabled() and relative_path == "index.toml":
            if (root / "conflict-once").exists():
                (root / "conflict-once").unlink()
                self.send_response(412)
                self.end_headers()
                self.wfile.write(b"stale index etag")
                return
            current_etag = self._index_etag()
            if current_etag is None:
                if self.headers.get("If-None-Match", "").strip() != "*":
                    self.send_response(412)
                    self.end_headers()
                    self.wfile.write(b"missing initial If-None-Match: *")
                    return
            elif self.headers.get("If-Match", "").strip() != current_etag:
                self.send_response(412)
                self.end_headers()
                self.wfile.write(b"stale index etag")
                return
        target.parent.mkdir(parents=True, exist_ok=True)
        length = int(self.headers.get("Content-Length", "0"))
        with open(target, "wb") as handle:
            remaining = length
            while remaining > 0:
                chunk = self.rfile.read(min(65536, remaining))
                if not chunk:
                    break
                handle.write(chunk)
                remaining -= len(chunk)
        self.send_response(201)
        self.end_headers()
        self.wfile.write(b"ok")

    def log_message(self, format, *args):
        pass

server = ThreadingHTTPServer(("127.0.0.1", port), Handler)
server.serve_forever()
PY

    python3 "$server_script" "$registry_dir" "$port" "$token" \
        >"$TEMP_DIR/hosted_registry_server.log" 2>&1 &
    HOSTED_SERVER_PID=$!
    sleep 1
    printf '%s\n' "$port"
}

ln -s "$PROJECT_ROOT/packages" "$TEMP_DIR/packages"
export MOG_CACHE_DIR="$TEMP_DIR/cache-root"
export XDG_CONFIG_HOME="$TEMP_DIR/xdg-config"

pushd "$TEMP_DIR" >/dev/null

"$MOG" init pkg-manager-test

if [[ ! -f "$TEMP_DIR/mog.toml" ]]; then
    echo "[FAIL] init did not create mog.toml"
    exit 1
fi

"$MOG" add math
"$MOG" add hello

if ! grep -Fq 'math = { path = "' "$TEMP_DIR/mog.toml" || \
   ! grep -Fq 'package = "examples:math"' "$TEMP_DIR/mog.toml" || \
   ! grep -Fq 'hello = { path = "' "$TEMP_DIR/mog.toml" || \
   ! grep -Fq 'package = "examples:hello"' "$TEMP_DIR/mog.toml"; then
    echo "[FAIL] add did not write the dependency metadata"
    cat "$TEMP_DIR/mog.toml"
    exit 1
fi

ADD_FLAGS_DIR="$(mktemp -d)"
ln -s "$PROJECT_ROOT/packages" "$ADD_FLAGS_DIR/packages"
mkdir -p "$ADD_FLAGS_DIR/local-build-util/src"
cat > "$ADD_FLAGS_DIR/local-build-util/mog.toml" <<'EOF_ADD_BUILD_MANIFEST'
kind = "source"
import_name = "build_util"
namespace = "acme"
name = "build-util"
version = "0.1.0"
license = "MIT"
description = "build dependency add test"
entry = "src/main.mog"
dependencies = []
EOF_ADD_BUILD_MANIFEST
cat > "$ADD_FLAGS_DIR/local-build-util/src/main.mog" <<'EOF_ADD_BUILD_SRC'
fn Name() str {
    return "build util"
}
EOF_ADD_BUILD_SRC
pushd "$ADD_FLAGS_DIR" >/dev/null
"$MOG" init add-flags-test >/dev/null
"$MOG" add --path packages/examples/hello --dev >/dev/null
"$MOG" add --path local-build-util --build >/dev/null
if ! grep -Fq '[dev-dependencies]' mog.toml || \
   ! grep -Fq 'hello = { path = "packages/examples/hello"' mog.toml || \
   ! grep -Fq '[build-dependencies]' mog.toml || \
   ! grep -Fq 'build_util = { path = "local-build-util"' mog.toml; then
    echo "[FAIL] add should support explicit path dependencies in dev/build groups"
    cat mog.toml
    exit 1
fi

GIT_PACKAGE_DIR="$ADD_FLAGS_DIR/git-package"
mkdir -p "$GIT_PACKAGE_DIR/src"
cat > "$GIT_PACKAGE_DIR/mog.toml" <<'EOF_ADD_GIT_MANIFEST'
kind = "source"
import_name = "git_util"
namespace = "acme"
name = "git-util"
version = "0.1.0"
license = "MIT"
description = "git add dependency"
entry = "src/main.mog"
dependencies = []
EOF_ADD_GIT_MANIFEST
cat > "$GIT_PACKAGE_DIR/src/main.mog" <<'EOF_ADD_GIT_SRC'
fn Name() str {
    return "git util"
}
EOF_ADD_GIT_SRC
git -C "$GIT_PACKAGE_DIR" init >/dev/null
git -C "$GIT_PACKAGE_DIR" config user.email "mog@example.invalid"
git -C "$GIT_PACKAGE_DIR" config user.name "Mog Test"
git -C "$GIT_PACKAGE_DIR" add .
git -C "$GIT_PACKAGE_DIR" commit -m "initial git package" >/dev/null
git -C "$GIT_PACKAGE_DIR" tag v0.1.0
"$MOG" add --git "$GIT_PACKAGE_DIR" --tag v0.1.0 --alias git_util --dev >/dev/null
if ! grep -Fq 'git_util = { package = "acme:git-util", version = "0.1.0", git = "'"$GIT_PACKAGE_DIR"'", tag = "v0.1.0" }' mog.toml; then
    echo "[FAIL] add should auto-discover git package metadata and write git refs"
    cat mog.toml
    exit 1
fi
popd >/dev/null

if [[ ! -f "$TEMP_DIR/.mog/install/registry.toml" ]]; then
    echo "[FAIL] add/install did not create .mog/install/registry.toml"
    exit 1
fi

cat > "$TEMP_DIR/app.mog" <<'EOF_APP'
const math = @import("math")
const hello = @import("hello")
print(math.MEANING_OF_LIFE)
print(hello.Greet())
EOF_APP

rm -f "$TEMP_DIR/.mog/install/registry.toml"

RUN_OUTPUT="$("$MOG" run "$TEMP_DIR/app.mog")"
if [[ "$RUN_OUTPUT" != *"42"* || "$RUN_OUTPUT" != *"hello from source package"* ]]; then
    echo "[FAIL] run did not reinstall packages or produce expected output"
    echo "$RUN_OUTPUT"
    exit 1
fi

if [[ ! -f "$TEMP_DIR/.mog/install/registry.toml" ]]; then
    echo "[FAIL] run did not recreate .mog/install/registry.toml"
    exit 1
fi

if ! grep -Fq 'schema_version = "lock.v4"' "$TEMP_DIR/mog.lock"; then
    echo "[FAIL] lockfile did not write the new lock schema"
    cat "$TEMP_DIR/mog.lock"
    exit 1
fi
if ! grep -Fq 'generator_version = "0.1.0"' "$TEMP_DIR/mog.lock"; then
    echo "[FAIL] lockfile should record generator_version"
    cat "$TEMP_DIR/mog.lock"
    exit 1
fi

if ! grep -Fq 'schema_version = "install.v4"' "$TEMP_DIR/.mog/install/registry.toml"; then
    echo "[FAIL] install registry did not write the new install schema"
    cat "$TEMP_DIR/.mog/install/registry.toml"
    exit 1
fi
if ! grep -Fq 'generator_version = "0.1.0"' "$TEMP_DIR/.mog/install/registry.toml"; then
    echo "[FAIL] install registry should record generator_version"
    cat "$TEMP_DIR/.mog/install/registry.toml"
    exit 1
fi

if grep -Fq 'package_dir = "/home/dev/Desktop/projects/programming-language/packages' \
    "$TEMP_DIR/.mog/install/registry.toml"; then
    echo "[FAIL] install registry should point at project-local installs"
    cat "$TEMP_DIR/.mog/install/registry.toml"
    exit 1
fi

if ! grep -Fq 'package_dir = ".mog/install/packages/examples/math"' \
    "$TEMP_DIR/.mog/install/registry.toml" || \
   ! grep -Fq 'package_dir = ".mog/install/packages/examples/hello"' \
    "$TEMP_DIR/.mog/install/registry.toml"; then
    echo "[FAIL] install registry missing project-local package roots"
    cat "$TEMP_DIR/.mog/install/registry.toml"
    exit 1
fi

if ! grep -Fq 'source_path = "' "$TEMP_DIR/mog.lock" || \
   ! grep -Fq 'package_id = "examples:math"' "$TEMP_DIR/mog.lock" || \
   ! grep -Fq 'package_id = "examples:hello"' "$TEMP_DIR/mog.lock"; then
    echo "[FAIL] lockfile missing source metadata"
    cat "$TEMP_DIR/mog.lock"
    exit 1
fi

if [[ ! -f "$TEMP_DIR/.mog/install/packages/examples/math/package.so" ]]; then
    echo "[FAIL] native package was not materialized into the project install store"
    find "$TEMP_DIR/.mog" -maxdepth 5 -type f | sort
    exit 1
fi

if [[ ! -f "$TEMP_DIR/.mog/install/packages/examples/hello/src/main.mog" ]]; then
    echo "[FAIL] source package was not materialized into the project install store"
    find "$TEMP_DIR/.mog" -maxdepth 5 -type f | sort
    exit 1
fi

if [[ ! -f "$TEMP_DIR/.mog/install/packages/examples/hello/mog.toml" || \
      -f "$TEMP_DIR/.mog/install/packages/examples/hello/package.toml" ]]; then
    echo "[FAIL] installed source packages should materialize a canonical mog.toml manifest"
    find "$TEMP_DIR/.mog/install/packages/examples/hello" -maxdepth 3 -type f | sort
    exit 1
fi

"$MOG" --validate-package "$PROJECT_ROOT/packages/examples/math" >/dev/null

popd >/dev/null

LEGACY_SOURCE_PROJECT="$(mktemp -d)"
mkdir -p "$LEGACY_SOURCE_PROJECT/vendor/examples/legacysource/src"
cat > "$LEGACY_SOURCE_PROJECT/vendor/examples/legacysource/package.toml" <<'EOF_LEGACY_SOURCE_MANIFEST'
kind = "source"
import_name = "legacysource"
namespace = "examples"
name = "legacysource"
version = "0.1.0"
license = "MIT"
description = "Legacy-only source package."
entry = "src/main.mog"
dependencies = []
EOF_LEGACY_SOURCE_MANIFEST

cat > "$LEGACY_SOURCE_PROJECT/vendor/examples/legacysource/package.api.mog" <<'EOF_LEGACY_SOURCE_API'
package legacysource

fn Greet() str
EOF_LEGACY_SOURCE_API

cat > "$LEGACY_SOURCE_PROJECT/vendor/examples/legacysource/src/main.mog" <<'EOF_LEGACY_SOURCE_SRC'
fn Greet() str {
    return "hello from legacy source package"
}
EOF_LEGACY_SOURCE_SRC

cat > "$LEGACY_SOURCE_PROJECT/mog.toml" <<'EOF_LEGACY_SOURCE_PROJECT'
kind = "project"
name = "legacy-source-project"
version = "0.1.0"
description = "legacy source project"

[dependencies]
legacysource = { path = "vendor/examples/legacysource", package = "examples:legacysource", version = "0.1.0" }
EOF_LEGACY_SOURCE_PROJECT

cat > "$LEGACY_SOURCE_PROJECT/app.mog" <<'EOF_LEGACY_SOURCE_APP'
const legacysource = @import("legacysource")
print(legacysource.Greet())
EOF_LEGACY_SOURCE_APP

if [[ "$(cd "$LEGACY_SOURCE_PROJECT" && "$MOG" run app.mog)" != *"hello from legacy source package"* ]]; then
    echo "[FAIL] run should continue to load source packages from legacy package.toml manifests"
    exit 1
fi

if [[ ! -f "$LEGACY_SOURCE_PROJECT/.mog/install/packages/examples/legacysource/mog.toml" || \
      -f "$LEGACY_SOURCE_PROJECT/.mog/install/packages/examples/legacysource/package.toml" ]]; then
    echo "[FAIL] legacy source package installs should normalize manifests to mog.toml"
    find "$LEGACY_SOURCE_PROJECT/.mog/install/packages/examples/legacysource" -maxdepth 3 -type f | sort
    exit 1
fi

if ! find "$MOG_CACHE_DIR" -name ".metadata.toml" -print -quit | grep -q .; then
    echo "[FAIL] install did not write durable cache metadata"
    find "$MOG_CACHE_DIR" -maxdepth 6 -print
    exit 1
fi

cp "$TEMP_DIR/mog.lock" "$TEMP_DIR/mog.lock.before"
(cd "$TEMP_DIR" && "$MOG" install --locked >/dev/null)
if ! cmp -s "$TEMP_DIR/mog.lock.before" "$TEMP_DIR/mog.lock"; then
    echo "[FAIL] install --locked should not rewrite mog.lock"
    exit 1
fi

rm -f "$TEMP_DIR/.mog/install/registry.toml"
LOCKED_RUN_OUTPUT="$("$MOG" run --locked "$TEMP_DIR/app.mog")"
if [[ "$LOCKED_RUN_OUTPUT" != *"42"* || "$LOCKED_RUN_OUTPUT" != *"hello from source package"* ]]; then
    echo "[FAIL] run --locked did not reinstall packages or produce expected output"
    echo "$LOCKED_RUN_OUTPUT"
    exit 1
fi

if [[ ! -f "$TEMP_DIR/.mog/install/registry.toml" ]]; then
    echo "[FAIL] run --locked did not recreate .mog/install/registry.toml"
    exit 1
fi

if ! (cd "$TEMP_DIR" && "$MOG" install --offline >/dev/null); then
    echo "[FAIL] install --offline should succeed for local path dependencies"
    exit 1
fi

python3 - "$TEMP_DIR/mog.toml" <<'PY'
from pathlib import Path
import sys

path = Path(sys.argv[1])
text = path.read_text(encoding="utf-8")
updated = text.replace(
    'hello = { path = "../../home/dev/Desktop/projects/programming-language/packages/examples/hello", package = "examples:hello", version = "0.1.0" }',
    'hello = { path = "../../home/dev/Desktop/projects/programming-language/packages/examples/hello", package = "examples:hello", version = "9.9.9" }',
)
if updated == text:
    raise SystemExit("failed to update hello dependency version")
path.write_text(updated, encoding="utf-8")
PY

if (cd "$TEMP_DIR" && "$MOG" install --locked >/tmp/mog_locked_failure.txt 2>&1); then
    echo "[FAIL] install --locked should reject manifest drift"
    cat /tmp/mog_locked_failure.txt
    exit 1
fi

if ! grep -Eq "out of date|requires version" /tmp/mog_locked_failure.txt; then
    echo "[FAIL] install --locked should explain manifest drift"
    cat /tmp/mog_locked_failure.txt
    exit 1
fi

REMOTE_DIR="$(mktemp -d)"
REGISTRY_DIR="$REMOTE_DIR/registry"
mkdir -p "$REGISTRY_DIR/packages/acme/util/1.0.0/src" \
         "$REGISTRY_DIR/packages/acme/http/1.0.0/src" \
         "$REGISTRY_DIR/packages/acme/native-demo/1.0.0"

cat > "$REGISTRY_DIR/packages/acme/util/1.0.0/mog.toml" <<'EOF_REGISTRY_UTIL_MANIFEST'
kind = "source"
import_name = "util"
namespace = "acme"
name = "util"
version = "1.0.0"
author = "Registry test"
description = "Published utility package."
entry = "src/main.mog"
dependencies = []
EOF_REGISTRY_UTIL_MANIFEST

cat > "$REGISTRY_DIR/packages/acme/util/1.0.0/src/main.mog" <<'EOF_REGISTRY_UTIL_SRC'
const MESSAGE str = "utility from registry"

fn Name() str {
    return MESSAGE
}
EOF_REGISTRY_UTIL_SRC

cat > "$REGISTRY_DIR/packages/acme/http/1.0.0/mog.toml" <<'EOF_REGISTRY_HTTP_MANIFEST'
kind = "source"
import_name = "http"
namespace = "acme"
name = "http"
version = "1.0.0"
author = "Registry test"
description = "Published http package."
entry = "src/main.mog"
[dependencies]
util = { package = "acme:util", version = "^1.0.0" }
EOF_REGISTRY_HTTP_MANIFEST

cat > "$REGISTRY_DIR/packages/acme/http/1.0.0/src/main.mog" <<'EOF_REGISTRY_HTTP_SRC'
const util = @import("util")

fn Fetch() str {
    return util.Name()
}
EOF_REGISTRY_HTTP_SRC

cat > "$REGISTRY_DIR/packages/acme/native-demo/1.0.0/mog.toml" <<'EOF_REGISTRY_NATIVE_MANIFEST'
kind = "native"
import_name = "native-demo"
namespace = "acme"
name = "native-demo"
version = "1.0.0"
abi_version = 1
author = "Registry test"
description = "Published native package placeholder."
dependencies = []
EOF_REGISTRY_NATIVE_MANIFEST

write_registry_index "$REGISTRY_DIR"

REGISTRY_ADD_DIR="$(mktemp -d)"
cat > "$REGISTRY_ADD_DIR/mog.toml" <<EOF_REGISTRY_ADD
kind = "project"
name = "registry-add-test"
version = "0.1.0"
description = "registry add test"

[registries.internal]
index = "$REGISTRY_DIR"
EOF_REGISTRY_ADD

if ! (cd "$REGISTRY_ADD_DIR" && "$MOG" add --registry internal acme/http@^1.0.0 >/dev/null); then
    echo "[FAIL] add should support explicit non-default registry aliases"
    exit 1
fi
if ! grep -Fq 'http = { package = "acme:http", version = "^1.0.0", registry = "internal" }' \
    "$REGISTRY_ADD_DIR/mog.toml"; then
    echo "[FAIL] add should preserve explicit registry aliases in mog.toml"
    cat "$REGISTRY_ADD_DIR/mog.toml"
    exit 1
fi

cat > "$REMOTE_DIR/mog.toml" <<EOF_REMOTE
kind = "project"
name = "remote-test"
version = "0.1.0"
description = "remote source test"

[registries.default]
index = "$REGISTRY_DIR"

[dependencies]
http = { package = "acme:http", version = "1.0.0" }
EOF_REMOTE

if ! (cd "$REMOTE_DIR" && "$MOG" install >/dev/null); then
    echo "[FAIL] install should resolve published source packages from the registry"
    exit 1
fi

if ! grep -Fq 'source_type = "registry"' "$REMOTE_DIR/mog.lock" || \
   ! grep -Fq 'registry = "default"' "$REMOTE_DIR/mog.lock" || \
   ! grep -Fq 'artifact_digest = "' "$REMOTE_DIR/mog.lock"; then
    echo "[FAIL] remote lockfile should record registry source metadata"
    cat "$REMOTE_DIR/mog.lock"
    exit 1
fi

cat > "$REMOTE_DIR/app.mog" <<'EOF_REMOTE_APP'
const http = @import("http")
print(http.Fetch())
EOF_REMOTE_APP

REMOTE_RUN_OUTPUT="$("$MOG" run "$REMOTE_DIR/app.mog")"
if [[ "$REMOTE_RUN_OUTPUT" != *"utility from registry"* ]]; then
    echo "[FAIL] run should execute registry-installed source packages with transitive dependencies"
    echo "$REMOTE_RUN_OUTPUT"
    exit 1
fi

rm -f "$REMOTE_DIR/.mog/install/registry.toml"
if ! (cd "$REMOTE_DIR" && "$MOG" install --offline >/dev/null); then
    echo "[FAIL] install --offline should succeed after a registry package has been cached"
    exit 1
fi

EMPTY_CACHE_DIR="$(mktemp -d)"
if (cd "$REMOTE_DIR" && MOG_CACHE_DIR="$EMPTY_CACHE_DIR" "$MOG" install --offline >/tmp/mog_registry_offline_failure.txt 2>&1); then
    echo "[FAIL] install --offline should reject uncached registry dependencies"
    cat /tmp/mog_registry_offline_failure.txt
    exit 1
fi
rm -rf "$EMPTY_CACHE_DIR"

if ! grep -Eq "offline|cached locally" /tmp/mog_registry_offline_failure.txt; then
    echo "[FAIL] install --offline should explain the missing registry cache"
    cat /tmp/mog_registry_offline_failure.txt
    exit 1
fi

cat > "$REGISTRY_DIR/packages/acme/util/1.0.0/src/main.mog" <<'EOF_REGISTRY_UTIL_SRC_UPDATED'
const MESSAGE str = "utility from registry v2"

fn Name() str {
    return MESSAGE
}
EOF_REGISTRY_UTIL_SRC_UPDATED
write_registry_index "$REGISTRY_DIR"

if ! (cd "$REMOTE_DIR" && "$MOG" install --locked >/dev/null); then
    echo "[FAIL] install --locked should continue to use the pinned registry lockfile"
    exit 1
fi

LOCKED_REMOTE_OUTPUT="$("$MOG" run --locked "$REMOTE_DIR/app.mog")"
if [[ "$LOCKED_REMOTE_OUTPUT" != *"utility from registry"* ]] || \
   [[ "$LOCKED_REMOTE_OUTPUT" == *"utility from registry v2"* ]]; then
    echo "[FAIL] run --locked should continue to use the pinned registry artifact"
    echo "$LOCKED_REMOTE_OUTPUT"
    exit 1
fi

RANGE_DIR="$(mktemp -d)"
cat > "$RANGE_DIR/mog.toml" <<EOF_RANGE
kind = "project"
name = "range-test"
version = "0.1.0"
description = "range source test"

[registries.default]
index = "$REGISTRY_DIR"

[dependencies]
http = { package = "acme:http", version = "^1.0.0" }
EOF_RANGE

if ! (cd "$RANGE_DIR" && "$MOG" install >/dev/null); then
    echo "[FAIL] install should accept published dependency version ranges"
    exit 1
fi

if ! grep -Fq 'version = "1.0.0"' "$RANGE_DIR/mog.lock"; then
    echo "[FAIL] initial ranged install should lock the only available published version"
    cat "$RANGE_DIR/mog.lock"
    exit 1
fi

mkdir -p "$REGISTRY_DIR/packages/acme/util/1.1.0/src" \
         "$REGISTRY_DIR/packages/acme/http/1.1.0/src"

cat > "$REGISTRY_DIR/packages/acme/util/1.1.0/mog.toml" <<'EOF_REGISTRY_UTIL_MANIFEST_110'
kind = "source"
import_name = "util"
namespace = "acme"
name = "util"
version = "1.1.0"
author = "Registry test"
description = "Published utility package."
entry = "src/main.mog"
dependencies = []
EOF_REGISTRY_UTIL_MANIFEST_110

cat > "$REGISTRY_DIR/packages/acme/util/1.1.0/src/main.mog" <<'EOF_REGISTRY_UTIL_SRC_110'
const MESSAGE str = "utility from registry 1.1"

fn Name() str {
    return MESSAGE
}
EOF_REGISTRY_UTIL_SRC_110

cat > "$REGISTRY_DIR/packages/acme/http/1.1.0/mog.toml" <<'EOF_REGISTRY_HTTP_MANIFEST_110'
kind = "source"
import_name = "http"
namespace = "acme"
name = "http"
version = "1.1.0"
author = "Registry test"
description = "Published http package."
entry = "src/main.mog"

[dependencies]
util = { package = "acme:util", version = "^1.1.0" }
EOF_REGISTRY_HTTP_MANIFEST_110

cat > "$REGISTRY_DIR/packages/acme/http/1.1.0/src/main.mog" <<'EOF_REGISTRY_HTTP_SRC_110'
const util = @import("util")

fn Fetch() str {
    return util.Name()
}
EOF_REGISTRY_HTTP_SRC_110

write_registry_index "$REGISTRY_DIR"

if ! (cd "$RANGE_DIR" && "$MOG" install >/dev/null); then
    echo "[FAIL] install should continue to work after new compatible releases are published"
    exit 1
fi

if ! grep -Fq 'version = "1.0.0"' "$RANGE_DIR/mog.lock"; then
    echo "[FAIL] install should keep using the existing lockfile for ranged dependencies"
    cat "$RANGE_DIR/mog.lock"
    exit 1
fi

if ! (cd "$RANGE_DIR" && "$MOG" update >/dev/null); then
    echo "[FAIL] update should refresh ranged published dependencies"
    exit 1
fi

if ! grep -Fq 'version = "1.1.0"' "$RANGE_DIR/mog.lock"; then
    echo "[FAIL] update should upgrade ranged published dependencies to the newest compatible version"
    cat "$RANGE_DIR/mog.lock"
    exit 1
fi

ADD_DIR="$(mktemp -d)"
cat > "$ADD_DIR/mog.toml" <<EOF_ADD
kind = "project"
name = "add-test"
version = "0.1.0"
description = "published add test"

[registries.default]
index = "$REGISTRY_DIR"
EOF_ADD

if ! (cd "$ADD_DIR" && "$MOG" add acme/http >/dev/null); then
    echo "[FAIL] add should support published package specs without an explicit version"
    exit 1
fi

if ! grep -Fq 'http = { package = "acme:http", version = "1.1.0" }' "$ADD_DIR/mog.toml"; then
    echo "[FAIL] add should record the latest exact published version when no version is specified"
    cat "$ADD_DIR/mog.toml"
    exit 1
fi

ADD_RANGE_DIR="$(mktemp -d)"
cat > "$ADD_RANGE_DIR/mog.toml" <<EOF_ADD_RANGE
kind = "project"
name = "add-range-test"
version = "0.1.0"
description = "published add range test"

[registries.default]
index = "$REGISTRY_DIR"
EOF_ADD_RANGE

if ! (cd "$ADD_RANGE_DIR" && "$MOG" add acme/util@^1.0.0 >/dev/null); then
    echo "[FAIL] add should support published package specs with explicit version ranges"
    exit 1
fi

if ! grep -Fq 'util = { package = "acme:util", version = "^1.0.0" }' "$ADD_RANGE_DIR/mog.toml"; then
    echo "[FAIL] add should preserve explicit published version ranges"
    cat "$ADD_RANGE_DIR/mog.toml"
    exit 1
fi

PUBLISH_WORKSPACE="$(mktemp -d)"
PUBLISH_PACKAGE_DIR="$PUBLISH_WORKSPACE/packages/greeter"
mkdir -p "$PUBLISH_PACKAGE_DIR/src"

cat > "$PUBLISH_WORKSPACE/mog.toml" <<EOF_PUBLISH_ROOT
kind = "project"
name = "publish-root"
version = "0.1.0"
description = "publish root"

[registries.default]
index = "$REGISTRY_DIR"
EOF_PUBLISH_ROOT

cat > "$PUBLISH_PACKAGE_DIR/mog.toml" <<'EOF_PUBLISH_PACKAGE'
kind = "source"
import_name = "greeter"
namespace = "demo"
name = "greeter"
version = "0.1.0"
license = "MIT"
author = "Registry test"
description = "Published greeter package."
entry = "src/main.mog"

[dependencies]
util = { package = "acme:util", version = "^1.0.0" }
EOF_PUBLISH_PACKAGE

cat > "$PUBLISH_PACKAGE_DIR/src/main.mog" <<'EOF_PUBLISH_SRC'
const util = @import("util")

fn Greet() str {
    return util.Name()
}
EOF_PUBLISH_SRC

if ! (cd "$PUBLISH_WORKSPACE" && "$MOG" publish "$PUBLISH_PACKAGE_DIR" >/dev/null); then
    echo "[FAIL] publish should create a source package registry entry"
    exit 1
fi

if ! (cd "$PUBLISH_WORKSPACE" && "$MOG" publish "$PUBLISH_PACKAGE_DIR" >/dev/null); then
    echo "[FAIL] publish should allow idempotent re-publish when the artifact and metadata are unchanged"
    exit 1
fi

if (cd "$PUBLISH_WORKSPACE" && \
    "$MOG" publish --target "$ALT_TARGET" "$PUBLISH_PACKAGE_DIR" \
    >/tmp/mog_source_publish_native_flag_failure.txt 2>&1); then
    echo "[FAIL] publish should reject native artifact flags for source packages"
    cat /tmp/mog_source_publish_native_flag_failure.txt
    exit 1
fi

if ! grep -Fq "Only native packages accept --target or --native-artifact-dir." \
    /tmp/mog_source_publish_native_flag_failure.txt; then
    echo "[FAIL] source publish flag failures should explain native-only options"
    cat /tmp/mog_source_publish_native_flag_failure.txt
    exit 1
fi

PRIVATE_SOURCE_PACKAGE_DIR="$PUBLISH_WORKSPACE/packages/private-greeter"
mkdir -p "$PRIVATE_SOURCE_PACKAGE_DIR/src"
cat > "$PRIVATE_SOURCE_PACKAGE_DIR/mog.toml" <<'EOF_PRIVATE_SOURCE'
kind = "source"
import_name = "private_greeter"
namespace = "demo"
name = "private-greeter"
version = "0.1.0"
license = "MIT"
publish = false
author = "Registry test"
description = "Private source package."
entry = "src/main.mog"
dependencies = []
EOF_PRIVATE_SOURCE

cat > "$PRIVATE_SOURCE_PACKAGE_DIR/src/main.mog" <<'EOF_PRIVATE_SOURCE_SRC'
fn Hidden() str {
    return "not published"
}
EOF_PRIVATE_SOURCE_SRC

if (cd "$PUBLISH_WORKSPACE" && \
    "$MOG" publish "$PRIVATE_SOURCE_PACKAGE_DIR" \
    >/tmp/mog_source_publish_private_failure.txt 2>&1); then
    echo "[FAIL] publish should reject source packages marked publish = false"
    cat /tmp/mog_source_publish_private_failure.txt
    exit 1
fi

if ! grep -Fq "publish = false" /tmp/mog_source_publish_private_failure.txt; then
    echo "[FAIL] source publish guard failures should mention publish = false"
    cat /tmp/mog_source_publish_private_failure.txt
    exit 1
fi

if ! grep -Fq 'package_id = "demo:greeter"' "$REGISTRY_DIR/index.toml" || \
   ! grep -Fq 'dependencies = ["acme:util@1.1.0"]' "$REGISTRY_DIR/index.toml"; then
    echo "[FAIL] publish should pin direct published dependencies exactly in the registry index"
    cat "$REGISTRY_DIR/index.toml"
    exit 1
fi

PUBLISHED_GREETER_DIR="$(mktemp -d)"
cat > "$PUBLISHED_GREETER_DIR/mog.toml" <<EOF_PUBLISHED_GREETER
kind = "project"
name = "published-greeter"
version = "0.1.0"
description = "published greeter consumer"

[registries.default]
index = "$REGISTRY_DIR"

[dependencies]
greeter = { package = "demo:greeter", version = "0.1.0" }
EOF_PUBLISHED_GREETER

cat > "$PUBLISHED_GREETER_DIR/app.mog" <<'EOF_PUBLISHED_GREETER_APP'
const greeter = @import("greeter")
print(greeter.Greet())
EOF_PUBLISHED_GREETER_APP

PUBLISHED_GREETER_OUTPUT="$("$MOG" run "$PUBLISHED_GREETER_DIR/app.mog")"
if [[ "$PUBLISHED_GREETER_OUTPUT" != *"utility from registry 1.1"* ]]; then
    echo "[FAIL] published source packages should install and run after mog publish"
    echo "$PUBLISHED_GREETER_OUTPUT"
    exit 1
fi

cat > "$REMOTE_DIR/mog.toml" <<EOF_UNKNOWN_REGISTRY
kind = "project"
name = "remote-test"
version = "0.1.0"
description = "remote source test"

[registries.default]
index = "$REGISTRY_DIR"

[dependencies]
http = { package = "acme:http", version = "1.0.0", registry = "missing" }
EOF_UNKNOWN_REGISTRY

if (cd "$REMOTE_DIR" && "$MOG" install >/tmp/mog_registry_missing_failure.txt 2>&1); then
    echo "[FAIL] install should reject unknown registry aliases"
    cat /tmp/mog_registry_missing_failure.txt
    exit 1
fi

if ! grep -Fq "unknown registry" /tmp/mog_registry_missing_failure.txt; then
    echo "[FAIL] install should explain missing registry aliases"
    cat /tmp/mog_registry_missing_failure.txt
    exit 1
fi

write_registry_index "$REGISTRY_DIR" digest-mismatch
DIGEST_DIR="$(mktemp -d)"
cat > "$DIGEST_DIR/mog.toml" <<EOF_BAD_DIGEST
kind = "project"
name = "digest-test"
version = "0.1.0"
description = "digest source test"

[registries.default]
index = "$REGISTRY_DIR"

[dependencies]
http = { package = "acme:http", version = "1.0.0" }
EOF_BAD_DIGEST

if (cd "$DIGEST_DIR" && "$MOG" install >/tmp/mog_registry_digest_failure.txt 2>&1); then
    echo "[FAIL] install should reject registry artifact digest mismatches"
    cat /tmp/mog_registry_digest_failure.txt
    exit 1
fi

if ! grep -Fq "digest mismatch" /tmp/mog_registry_digest_failure.txt; then
    echo "[FAIL] install should explain registry artifact digest mismatches"
    cat /tmp/mog_registry_digest_failure.txt
    exit 1
fi

write_registry_index "$REGISTRY_DIR"

NATIVE_PUBLISH_WORKSPACE="$(mktemp -d)"
NATIVE_CONSUMER_DIR="$(mktemp -d)"
NATIVE_BAD_DIR="$(mktemp -d)"
NATIVE_SOURCE_DIR="$(mktemp -d)"
NATIVE_NO_CMAKE_DIR="$(mktemp -d)"
NATIVE_BUILD_FAIL_DIR="$(mktemp -d)"
mkdir -p "$NATIVE_PUBLISH_WORKSPACE/packages/examples/counter" \
         "$NATIVE_PUBLISH_WORKSPACE/build/packages/examples/counter"
cp "$PROJECT_ROOT/packages/examples/counter/mog.toml" \
   "$PROJECT_ROOT/packages/examples/counter/package.api.mog" \
   "$PROJECT_ROOT/packages/examples/counter/package.cpp" \
   "$NATIVE_PUBLISH_WORKSPACE/packages/examples/counter/"
cp "$PROJECT_ROOT/build/packages/examples/counter/package.so" \
   "$NATIVE_PUBLISH_WORKSPACE/build/packages/examples/counter/package.so"

cat > "$NATIVE_PUBLISH_WORKSPACE/mog.toml" <<EOF_NATIVE_PUBLISH_ROOT
kind = "project"
name = "native-publish-root"
version = "0.1.0"
description = "native publish root"

[registries.default]
index = "$REGISTRY_DIR"
EOF_NATIVE_PUBLISH_ROOT

if ! (cd "$NATIVE_PUBLISH_WORKSPACE" && \
      "$MOG" publish "$NATIVE_PUBLISH_WORKSPACE/packages/examples/counter" >/dev/null); then
    echo "[FAIL] publish should create a native package registry entry"
    exit 1
fi

if ! (cd "$NATIVE_PUBLISH_WORKSPACE" && \
      "$MOG" publish "$NATIVE_PUBLISH_WORKSPACE/packages/examples/counter" >/dev/null); then
    echo "[FAIL] publish should allow idempotent native re-publish"
    exit 1
fi

NATIVE_EXTERNAL_BUNDLE_DIR="$(mktemp -d)"
cp "$NATIVE_PUBLISH_WORKSPACE/packages/examples/counter/mog.toml" \
   "$NATIVE_PUBLISH_WORKSPACE/packages/examples/counter/package.api.mog" \
   "$NATIVE_EXTERNAL_BUNDLE_DIR/"
cp "$NATIVE_PUBLISH_WORKSPACE/build/packages/examples/counter/package.so" \
   "$NATIVE_EXTERNAL_BUNDLE_DIR/package.so"

if (cd "$NATIVE_PUBLISH_WORKSPACE" && \
    "$MOG" publish \
      --native-artifact-dir "$NATIVE_EXTERNAL_BUNDLE_DIR" \
      "$NATIVE_PUBLISH_WORKSPACE/packages/examples/counter" \
      >/tmp/mog_native_publish_missing_target.txt 2>&1); then
    echo "[FAIL] publish should require --target when --native-artifact-dir is used"
    cat /tmp/mog_native_publish_missing_target.txt
    exit 1
fi

if ! grep -Fq "requires --target" /tmp/mog_native_publish_missing_target.txt; then
    echo "[FAIL] native publish should explain missing --target for external artifact directories"
    cat /tmp/mog_native_publish_missing_target.txt
    exit 1
fi

PRIVATE_NATIVE_PACKAGE_DIR="$NATIVE_PUBLISH_WORKSPACE/packages/examples/private-counter"
mkdir -p "$PRIVATE_NATIVE_PACKAGE_DIR"
cat > "$PRIVATE_NATIVE_PACKAGE_DIR/mog.toml" <<'EOF_PRIVATE_NATIVE'
kind = "native"
namespace = "examples"
name = "private-counter"
version = "0.1.0"
license = "MIT"
publish = false
abi_version = 3
mog_runtime = "^0.1.0"
author = "Mog runtime"
description = "Private native package."
dependencies = []

[native]
build = "cmake"
targets = ["linux-x86_64-gnu"]
EOF_PRIVATE_NATIVE

if (cd "$NATIVE_PUBLISH_WORKSPACE" && \
    "$MOG" publish "$PRIVATE_NATIVE_PACKAGE_DIR" \
    >/tmp/mog_native_publish_private_failure.txt 2>&1); then
    echo "[FAIL] publish should reject native packages marked publish = false"
    cat /tmp/mog_native_publish_private_failure.txt
    exit 1
fi

if ! grep -Fq "publish = false" /tmp/mog_native_publish_private_failure.txt; then
    echo "[FAIL] native publish guard failures should mention publish = false"
    cat /tmp/mog_native_publish_private_failure.txt
    exit 1
fi

if ! (cd "$NATIVE_PUBLISH_WORKSPACE" && \
      "$MOG" publish \
        --target "$ALT_TARGET" \
        --native-artifact-dir "$NATIVE_EXTERNAL_BUNDLE_DIR" \
        "$NATIVE_PUBLISH_WORKSPACE/packages/examples/counter" >/dev/null); then
    echo "[FAIL] publish should accept external native artifact bundles for a second target"
    exit 1
fi

if ! grep -Fq 'package_id = "examples:counter"' "$REGISTRY_DIR/index.toml"; then
    echo "[FAIL] publish should record the native package in the registry index"
    cat "$REGISTRY_DIR/index.toml"
    exit 1
fi

if ! grep -Fq 'artifact_path = "packages/examples/counter/0.1.0/source"' \
      "$REGISTRY_DIR/index.toml" || \
   ! grep -Fq "\"$HOST_TARGET\"" "$REGISTRY_DIR/index.toml" || \
   ! grep -Fq "\"$ALT_TARGET\"" "$REGISTRY_DIR/index.toml" || \
   ! grep -Fq "packages/examples/counter/0.1.0/$HOST_TARGET" "$REGISTRY_DIR/index.toml" || \
   ! grep -Fq "packages/examples/counter/0.1.0/$ALT_TARGET" "$REGISTRY_DIR/index.toml"; then
    echo "[FAIL] publish should record source and target-keyed native artifact metadata"
    cat "$REGISTRY_DIR/index.toml"
    exit 1
fi

if [[ ! -f "$REGISTRY_DIR/packages/examples/counter/0.1.0/source/package.cpp" || \
      ! -f "$REGISTRY_DIR/packages/examples/counter/0.1.0/source/NativePackageAPI.hpp" ]]; then
    echo "[FAIL] publish should create a self-contained native source artifact"
    find "$REGISTRY_DIR/packages/examples/counter/0.1.0" -maxdepth 3 -print
    exit 1
fi

if [[ ! -f "$REGISTRY_DIR/packages/examples/counter/0.1.0/source/mog.toml" || \
      -f "$REGISTRY_DIR/packages/examples/counter/0.1.0/source/package.toml" || \
      ! -f "$REGISTRY_DIR/packages/examples/counter/0.1.0/$HOST_TARGET/mog.toml" || \
      -f "$REGISTRY_DIR/packages/examples/counter/0.1.0/$HOST_TARGET/package.toml" || \
      ! -f "$REGISTRY_DIR/packages/examples/counter/0.1.0/$ALT_TARGET/mog.toml" || \
      -f "$REGISTRY_DIR/packages/examples/counter/0.1.0/$ALT_TARGET/package.toml" ]]; then
    echo "[FAIL] published native artifacts should normalize manifests to mog.toml"
    find "$REGISTRY_DIR/packages/examples/counter/0.1.0" -maxdepth 3 -type f | sort
    exit 1
fi

python3 - "$NATIVE_PUBLISH_WORKSPACE/packages/examples/counter/mog.toml" <<'PY'
from pathlib import Path
import sys

path = Path(sys.argv[1])
text = path.read_text(encoding="utf-8")
updated = text.replace(
    'description = "Reference opaque handle package."',
    'description = "Conflicting native publish contents."',
)
if updated == text:
    raise SystemExit("failed to update native package description")
path.write_text(updated, encoding="utf-8")
PY

if (cd "$NATIVE_PUBLISH_WORKSPACE" && \
    "$MOG" publish "$NATIVE_PUBLISH_WORKSPACE/packages/examples/counter" \
    >/tmp/mog_native_publish_conflict.txt 2>&1); then
    echo "[FAIL] publish should reject conflicting native re-publishes"
    cat /tmp/mog_native_publish_conflict.txt
    exit 1
fi

if ! grep -Fq "different published contents" /tmp/mog_native_publish_conflict.txt; then
    echo "[FAIL] publish should explain native re-publish conflicts"
    cat /tmp/mog_native_publish_conflict.txt
    exit 1
fi

if [[ ! -x "$WINDOW_PUBLISH_SCRIPT" ]]; then
    echo "[FAIL] official window publish script should be executable"
    exit 1
fi

if [[ -n "$WINDOW_PACKAGE_LIBRARY" ]]; then
    mv "$WINDOW_PACKAGE_LIBRARY" "$WINDOW_PACKAGE_LIBRARY.bak"
    if "$WINDOW_PUBLISH_SCRIPT" --registry-path "$REGISTRY_DIR" \
        >/tmp/mog_window_publish_missing_artifact.txt 2>&1; then
        echo "[FAIL] official window publish script should reject a missing build artifact"
        cat /tmp/mog_window_publish_missing_artifact.txt
        mv "$WINDOW_PACKAGE_LIBRARY.bak" "$WINDOW_PACKAGE_LIBRARY"
        exit 1
    fi
    mv "$WINDOW_PACKAGE_LIBRARY.bak" "$WINDOW_PACKAGE_LIBRARY"

    if ! grep -Fq "Built mog:window library not found" \
        /tmp/mog_window_publish_missing_artifact.txt; then
        echo "[FAIL] official window publish script should explain missing build artifacts"
        cat /tmp/mog_window_publish_missing_artifact.txt
        exit 1
    fi

    if ! "$WINDOW_PUBLISH_SCRIPT" --registry-path "$REGISTRY_DIR" >/dev/null; then
        echo "[FAIL] publish script should accept the official mog:window package"
        exit 1
    fi

    if ! MOG_PUBLISH_REGISTRY_PATH="$REGISTRY_DIR" \
        "$WINDOW_PUBLISH_SCRIPT" >/dev/null; then
        echo "[FAIL] publish script should support CI-style registry-path configuration via environment"
        exit 1
    fi

    WINDOW_BUNDLE_ROOT="$(mktemp -d)"
    mkdir -p "$WINDOW_BUNDLE_ROOT/host" "$WINDOW_BUNDLE_ROOT/alt"
    cp "$PROJECT_ROOT/packages/mog/window/mog.toml" \
       "$PROJECT_ROOT/packages/mog/window/package.api.mog" \
       "$WINDOW_BUNDLE_ROOT/host/"
    cp "$PROJECT_ROOT/packages/mog/window/mog.toml" \
       "$PROJECT_ROOT/packages/mog/window/package.api.mog" \
       "$WINDOW_BUNDLE_ROOT/alt/"
    cp "$WINDOW_PACKAGE_LIBRARY" "$WINDOW_BUNDLE_ROOT/host/$(basename "$WINDOW_PACKAGE_LIBRARY")"
    cp "$WINDOW_PACKAGE_LIBRARY" "$WINDOW_BUNDLE_ROOT/alt/$(basename "$WINDOW_PACKAGE_LIBRARY")"
    printf '%s\n' "$HOST_TARGET" > "$WINDOW_BUNDLE_ROOT/host/publish-target.txt"
    printf '%s\n' "$ALT_TARGET" > "$WINDOW_BUNDLE_ROOT/alt/publish-target.txt"

    if ! "$WINDOW_PUBLISH_SCRIPT" --registry-path "$REGISTRY_DIR" \
        --bundle-root "$WINDOW_BUNDLE_ROOT" >/dev/null; then
        echo "[FAIL] publish script should accept prepared bundle roots"
        exit 1
    fi

    if ! grep -Fq "\"$ALT_TARGET\"" "$REGISTRY_DIR/index.toml" || \
       ! grep -Fq "packages/mog/window/0.1.0/$ALT_TARGET" "$REGISTRY_DIR/index.toml"; then
        echo "[FAIL] publish script bundle mode should add additional target artifacts"
        cat "$REGISTRY_DIR/index.toml"
        exit 1
    fi

    WINDOW_PUBLISH_DIR="$(mktemp -d)"
    mkdir -p "$WINDOW_PUBLISH_DIR/app"
    cat > "$WINDOW_PUBLISH_DIR/app/mog.toml" <<EOF_WINDOW_CONSUMER
kind = "project"
name = "window-consumer"
version = "0.1.0"
description = "window consumer"

[registries.default]
index = "$REGISTRY_DIR"

[dependencies]
window = { package = "mog:window", version = "0.1.0" }
EOF_WINDOW_CONSUMER
    cp "$PROJECT_ROOT/tests/sample_mog_window.mog" \
       "$WINDOW_PUBLISH_DIR/app/app.mog"

    if ! (cd "$WINDOW_PUBLISH_DIR/app" && "$MOG" install >/dev/null); then
        echo "[FAIL] install should resolve a published mog:window package"
        exit 1
    fi

    WINDOW_RUN_OUTPUT="$(SDL_VIDEODRIVER=dummy "$MOG" run "$WINDOW_PUBLISH_DIR/app/app.mog")"
    if [[ "$WINDOW_RUN_OUTPUT" != *"true"* || \
          "$WINDOW_RUN_OUTPUT" != *"false"* ]]; then
        echo "[FAIL] run should execute a published mog:window package"
        echo "$WINDOW_RUN_OUTPUT"
        exit 1
    fi
else
    if "$WINDOW_PUBLISH_SCRIPT" --registry-path "$REGISTRY_DIR" \
        >/tmp/mog_window_publish_missing_artifact.txt 2>&1; then
        echo "[FAIL] official window publish script should fail when mog:window is not built"
        exit 1
    fi

    if ! grep -Fq "Built mog:window library not found" \
        /tmp/mog_window_publish_missing_artifact.txt; then
        echo "[FAIL] official window publish script should explain missing build artifacts"
        cat /tmp/mog_window_publish_missing_artifact.txt
        exit 1
    fi
fi

cat > "$NATIVE_CONSUMER_DIR/mog.toml" <<EOF_NATIVE_CONSUMER
kind = "project"
name = "native-consumer"
version = "0.1.0"
description = "native consumer"

[registries.default]
index = "$REGISTRY_DIR"

[dependencies]
counter = { package = "examples:counter", version = "0.1.0" }
EOF_NATIVE_CONSUMER

cat > "$NATIVE_CONSUMER_DIR/app.mog" <<'EOF_NATIVE_CONSUMER_APP'
const counter = @import("counter")

const value = counter.create(10i64)
print(counter.PACKAGE_ID)
print(counter.add(value, 5i64))
EOF_NATIVE_CONSUMER_APP

if ! (cd "$NATIVE_CONSUMER_DIR" && "$MOG" install >/dev/null); then
    echo "[FAIL] install should resolve published native packages from the registry"
    exit 1
fi

NATIVE_RUN_OUTPUT="$("$MOG" run "$NATIVE_CONSUMER_DIR/app.mog")"
if [[ "$NATIVE_RUN_OUTPUT" != *"examples:counter"* || "$NATIVE_RUN_OUTPUT" != *"15"* ]]; then
    echo "[FAIL] run should execute registry-installed native packages"
    echo "$NATIVE_RUN_OUTPUT"
    exit 1
fi

if ! grep -Fq 'package_id = "examples:counter"' "$NATIVE_CONSUMER_DIR/mog.lock" || \
   ! grep -Fq 'source_type = "registry"' "$NATIVE_CONSUMER_DIR/mog.lock" || \
   ! grep -Fq 'kind = "native"' "$NATIVE_CONSUMER_DIR/mog.lock" || \
   ! grep -Fq "selected_target = \"$HOST_TARGET\"" "$NATIVE_CONSUMER_DIR/mog.lock"; then
    echo "[FAIL] native registry installs should be recorded in mog.lock"
    cat "$NATIVE_CONSUMER_DIR/mog.lock"
    exit 1
fi

if ! grep -Fq "selected_target = \"$HOST_TARGET\"" \
    "$NATIVE_CONSUMER_DIR/.mog/install/registry.toml"; then
    echo "[FAIL] install registry should record the selected native target"
    cat "$NATIVE_CONSUMER_DIR/.mog/install/registry.toml"
    exit 1
fi

if [[ ! -f "$NATIVE_CONSUMER_DIR/.mog/install/packages/examples/counter/package.so" ]]; then
    echo "[FAIL] native registry installs should materialize the shared library"
    find "$NATIVE_CONSUMER_DIR/.mog" -maxdepth 6 -print
    exit 1
fi

rm -f "$NATIVE_CONSUMER_DIR/.mog/install/registry.toml"
if ! (cd "$NATIVE_CONSUMER_DIR" && \
      "$MOG" install --prefer-prebuilt --target "$HOST_TARGET" >/dev/null); then
    echo "[FAIL] install should accept explicit native target selection flags"
    exit 1
fi

rm -f "$NATIVE_CONSUMER_DIR/.mog/install/registry.toml"
if ! (cd "$NATIVE_CONSUMER_DIR" && "$MOG" install --offline >/dev/null); then
    echo "[FAIL] install --offline should succeed for cached native registry packages"
    exit 1
fi

python3 - "$REGISTRY_DIR" <<'PY'
from pathlib import Path
import hashlib
import sys
import tomllib

registry_dir = Path(sys.argv[1])
index_path = registry_dir / "index.toml"
data = tomllib.loads(index_path.read_text(encoding="utf-8"))

for package in data.get("package", []):
    if package.get("package_id") == "examples:counter" and package.get("version") == "0.1.0":
        package.pop("native_targets", None)
        package.pop("native_artifact_paths", None)
        package.pop("native_artifact_digests", None)
        break
else:
    raise SystemExit("missing examples:counter@0.1.0 in registry index")

parts = ['schema_version = "registry.v1"']
for package in data.get("package", []):
    parts.append("")
    parts.append("[[package]]")
    parts.append(f'package_id = "{package["package_id"]}"')
    parts.append(f'version = "{package["version"]}"')
    if "artifact_path" in package:
        parts.append(f'artifact_path = "{package["artifact_path"]}"')
    if "artifact_digest" in package:
        parts.append(f'artifact_digest = "{package["artifact_digest"]}"')
    if "native_targets" in package:
        targets = ", ".join(f'"{value}"' for value in package["native_targets"])
        paths = ", ".join(f'"{value}"' for value in package["native_artifact_paths"])
        digests = ", ".join(f'"{value}"' for value in package["native_artifact_digests"])
        parts.append(f"native_targets = [{targets}]")
        parts.append(f"native_artifact_paths = [{paths}]")
        parts.append(f"native_artifact_digests = [{digests}]")
    deps = ", ".join(f'"{value}"' for value in package.get("dependencies", []))
    parts.append(f"dependencies = [{deps}]")

index_path.write_text("\n".join(parts) + "\n", encoding="utf-8")
PY

cat > "$NATIVE_SOURCE_DIR/mog.toml" <<EOF_NATIVE_SOURCE
kind = "project"
name = "native-source-consumer"
version = "0.1.0"
description = "native source consumer"

[registries.default]
index = "$REGISTRY_DIR"

[dependencies]
counter = { package = "examples:counter", version = "0.1.0" }
EOF_NATIVE_SOURCE

cp "$NATIVE_CONSUMER_DIR/app.mog" "$NATIVE_SOURCE_DIR/app.mog"

if ! (cd "$NATIVE_SOURCE_DIR" && "$MOG" install >/dev/null); then
    echo "[FAIL] install should source-build a native package when the registry only publishes a source artifact"
    exit 1
fi

if ! grep -Fq 'build_from_source = true' "$NATIVE_SOURCE_DIR/mog.lock"; then
    echo "[FAIL] lockfile should record native source-build installs"
    cat "$NATIVE_SOURCE_DIR/mog.lock"
    exit 1
fi

NATIVE_SOURCE_OUTPUT="$("$MOG" run "$NATIVE_SOURCE_DIR/app.mog")"
if [[ "$NATIVE_SOURCE_OUTPUT" != *"examples:counter"* || "$NATIVE_SOURCE_OUTPUT" != *"15"* ]]; then
    echo "[FAIL] run should execute source-built native registry packages"
    echo "$NATIVE_SOURCE_OUTPUT"
    exit 1
fi

rm -f "$NATIVE_SOURCE_DIR/.mog/install/registry.toml"
if ! (cd "$NATIVE_SOURCE_DIR" && "$MOG" install --offline >/dev/null); then
    echo "[FAIL] install --offline should succeed for cached source-built native packages"
    exit 1
fi

NATIVE_CROSS_TARGET_DIR="$(mktemp -d)"
cat > "$NATIVE_CROSS_TARGET_DIR/mog.toml" <<EOF_NATIVE_CROSS_TARGET
kind = "project"
name = "native-cross-target"
version = "0.1.0"
description = "native cross target"

[registries.default]
index = "$REGISTRY_DIR"

[dependencies]
counter = { package = "examples:counter", version = "0.1.0" }
EOF_NATIVE_CROSS_TARGET

cp "$NATIVE_CONSUMER_DIR/app.mog" "$NATIVE_CROSS_TARGET_DIR/app.mog"

if (cd "$NATIVE_CROSS_TARGET_DIR" && \
    MOG_CACHE_DIR="$TEMP_DIR/cross-target-missing-toolchain-cache" \
    "$MOG" install --target "$ALT_TARGET" \
    >/tmp/mog_native_cross_target_toolchain_failure.txt 2>&1); then
    echo "[FAIL] install should require --cmake-toolchain for non-host source fallback"
    cat /tmp/mog_native_cross_target_toolchain_failure.txt
    exit 1
fi

if ! grep -Fq -- "--cmake-toolchain" \
    /tmp/mog_native_cross_target_toolchain_failure.txt; then
    echo "[FAIL] install should explain how to enable non-host source fallback"
    cat /tmp/mog_native_cross_target_toolchain_failure.txt
    exit 1
fi

printf '# host toolchain passthrough for package-manager tests\n' \
    > "$TEMP_DIR/cross-target-toolchain.cmake"

if ! (cd "$NATIVE_CROSS_TARGET_DIR" && \
      "$MOG" install --target "$ALT_TARGET" \
      --cmake-toolchain "$TEMP_DIR/cross-target-toolchain.cmake" >/dev/null); then
    echo "[FAIL] install should allow non-host native source fallback with --cmake-toolchain"
    exit 1
fi

if ! grep -Fq 'build_from_source = true' "$NATIVE_CROSS_TARGET_DIR/mog.lock" || \
   ! grep -Fq "selected_target = \"$ALT_TARGET\"" "$NATIVE_CROSS_TARGET_DIR/mog.lock"; then
    echo "[FAIL] lockfile should pin non-host source-built native installs"
    cat "$NATIVE_CROSS_TARGET_DIR/mog.lock"
    exit 1
fi

rm -f "$NATIVE_CROSS_TARGET_DIR/.mog/install/registry.toml"
CROSS_TARGET_OUTPUT="$("$MOG" run --locked --target "$ALT_TARGET" \
    "$NATIVE_CROSS_TARGET_DIR/app.mog")"
if [[ "$CROSS_TARGET_OUTPUT" != *"examples:counter"* || \
      "$CROSS_TARGET_OUTPUT" != *"15"* ]]; then
    echo "[FAIL] run --locked should reuse cached non-host source-built native packages"
    echo "$CROSS_TARGET_OUTPUT"
    exit 1
fi

NATIVE_CROSS_TARGET_MANIFEST_DIR="$(mktemp -d)"
cat > "$NATIVE_CROSS_TARGET_MANIFEST_DIR/mog.toml" <<EOF_NATIVE_CROSS_TARGET_MANIFEST
kind = "project"
name = "native-cross-target-manifest"
version = "0.1.0"
description = "native cross target manifest"

[registries.default]
index = "$REGISTRY_DIR"

[native.toolchains."$ALT_TARGET"]
cmake_toolchain = "$TEMP_DIR/cross-target-toolchain.cmake"
generator = "Unix Makefiles"
build_type = "RelWithDebInfo"
configure_args = ["--log-level=NOTICE"]
build_args = ["--verbose"]
env = { "MOG_NATIVE_TEST_ENV" = "manifest-value" }

[dependencies]
counter = { package = "examples:counter", version = "0.1.0" }
EOF_NATIVE_CROSS_TARGET_MANIFEST

cp "$NATIVE_CONSUMER_DIR/app.mog" "$NATIVE_CROSS_TARGET_MANIFEST_DIR/app.mog"

if ! (cd "$NATIVE_CROSS_TARGET_MANIFEST_DIR" && \
      MOG_CACHE_DIR="$TEMP_DIR/manifest-target-cache" \
      "$MOG" install --target "$ALT_TARGET" >/dev/null); then
    echo "[FAIL] install should allow non-host native source fallback from manifest-configured toolchains"
    exit 1
fi

MANIFEST_BUILD_LOG="$(find "$TEMP_DIR/manifest-target-cache" -name .build.log -print -quit)"
if [[ -z "$MANIFEST_BUILD_LOG" ]]; then
    echo "[FAIL] manifest-configured non-host native source builds should retain a build log"
    find "$TEMP_DIR/manifest-target-cache" -maxdepth 6 -print
    exit 1
fi

if ! grep -Fq '"MOG_NATIVE_TEST_ENV=manifest-value" cmake' "$MANIFEST_BUILD_LOG" || \
   ! grep -Fq -- '-G "Unix Makefiles"' "$MANIFEST_BUILD_LOG" || \
   ! grep -Fq -- '-DCMAKE_BUILD_TYPE="RelWithDebInfo"' "$MANIFEST_BUILD_LOG" || \
   ! grep -Fq -- '"--log-level=NOTICE"' "$MANIFEST_BUILD_LOG" || \
   ! grep -Fq -- '"--verbose"' "$MANIFEST_BUILD_LOG"; then
    echo "[FAIL] manifest-configured native toolchain settings should propagate into the CMake configure/build commands"
    cat "$MANIFEST_BUILD_LOG"
    exit 1
fi

if ! grep -Fq 'build_from_source = true' \
    "$NATIVE_CROSS_TARGET_MANIFEST_DIR/mog.lock" || \
   ! grep -Fq "selected_target = \"$ALT_TARGET\"" \
    "$NATIVE_CROSS_TARGET_MANIFEST_DIR/mog.lock"; then
    echo "[FAIL] lockfile should pin manifest-configured non-host native installs"
    cat "$NATIVE_CROSS_TARGET_MANIFEST_DIR/mog.lock"
    exit 1
fi

rm -f "$NATIVE_CROSS_TARGET_MANIFEST_DIR/.mog/install/registry.toml"
MANIFEST_CROSS_TARGET_OUTPUT="$("$MOG" run --locked --target "$ALT_TARGET" \
    "$NATIVE_CROSS_TARGET_MANIFEST_DIR/app.mog")"
if [[ "$MANIFEST_CROSS_TARGET_OUTPUT" != *"examples:counter"* || \
      "$MANIFEST_CROSS_TARGET_OUTPUT" != *"15"* ]]; then
    echo "[FAIL] run --locked should reuse manifest-configured non-host native installs"
    echo "$MANIFEST_CROSS_TARGET_OUTPUT"
    exit 1
fi

printf '# host toolchain override for package-manager tests\n' \
    > "$TEMP_DIR/cross-target-override-toolchain.cmake"

NATIVE_CROSS_TARGET_OVERRIDE_DIR="$(mktemp -d)"
cat > "$NATIVE_CROSS_TARGET_OVERRIDE_DIR/mog.toml" <<EOF_NATIVE_CROSS_TARGET_OVERRIDE
kind = "project"
name = "native-cross-target-override"
version = "0.1.0"
description = "native cross target override"

[registries.default]
index = "$REGISTRY_DIR"

[native.toolchains."$ALT_TARGET"]
cmake_toolchain = "missing-manifest-toolchain.cmake"

[dependencies]
counter = { package = "examples:counter", version = "0.1.0" }
EOF_NATIVE_CROSS_TARGET_OVERRIDE

cp "$NATIVE_CONSUMER_DIR/app.mog" "$NATIVE_CROSS_TARGET_OVERRIDE_DIR/app.mog"

if ! (cd "$NATIVE_CROSS_TARGET_OVERRIDE_DIR" && \
      MOG_CACHE_DIR="$TEMP_DIR/override-target-cache" \
      "$MOG" install --target "$ALT_TARGET" \
      --cmake-toolchain "$TEMP_DIR/cross-target-override-toolchain.cmake" \
      >/dev/null); then
    echo "[FAIL] install should let --cmake-toolchain override manifest native toolchain configuration"
    exit 1
fi

NATIVE_CROSS_TARGET_BAD_TOOLCHAIN_DIR="$(mktemp -d)"
cat > "$NATIVE_CROSS_TARGET_BAD_TOOLCHAIN_DIR/mog.toml" <<EOF_NATIVE_CROSS_TARGET_BAD
kind = "project"
name = "native-cross-target-bad-toolchain"
version = "0.1.0"
description = "native cross target bad toolchain"

[registries.default]
index = "$REGISTRY_DIR"

[native.toolchains."$ALT_TARGET"]
cmake_toolchain = "missing-manifest-toolchain.cmake"

[dependencies]
counter = { package = "examples:counter", version = "0.1.0" }
EOF_NATIVE_CROSS_TARGET_BAD

cp "$NATIVE_CONSUMER_DIR/app.mog" "$NATIVE_CROSS_TARGET_BAD_TOOLCHAIN_DIR/app.mog"

if (cd "$NATIVE_CROSS_TARGET_BAD_TOOLCHAIN_DIR" && \
    MOG_CACHE_DIR="$TEMP_DIR/bad-manifest-toolchain-cache" \
    "$MOG" install --target "$ALT_TARGET" \
    >/tmp/mog_native_bad_manifest_toolchain_failure.txt 2>&1); then
    echo "[FAIL] install should reject missing manifest-configured native toolchains"
    cat /tmp/mog_native_bad_manifest_toolchain_failure.txt
    exit 1
fi

if ! grep -Fq "missing-manifest-toolchain.cmake" \
    /tmp/mog_native_bad_manifest_toolchain_failure.txt || \
   ! grep -Fq '[native.toolchains."'$ALT_TARGET'"].cmake_toolchain' \
    /tmp/mog_native_bad_manifest_toolchain_failure.txt; then
    echo "[FAIL] install should identify missing manifest-configured native toolchains"
    cat /tmp/mog_native_bad_manifest_toolchain_failure.txt
    exit 1
fi

if ! (cd "$NATIVE_CROSS_TARGET_BAD_TOOLCHAIN_DIR" && \
      MOG_CACHE_DIR="$TEMP_DIR/bad-manifest-host-cache" \
      "$MOG" install >/dev/null); then
    echo "[FAIL] host-target installs should ignore unrelated manifest native toolchain entries"
    exit 1
fi

NATIVE_CROSS_TARGET_ENV_DIR="$(mktemp -d)"
cat > "$NATIVE_CROSS_TARGET_ENV_DIR/mog.toml" <<EOF_NATIVE_CROSS_TARGET_ENV
kind = "project"
name = "native-cross-target-env"
version = "0.1.0"
description = "native cross target env"

[registries.default]
index = "$REGISTRY_DIR"

[dependencies]
counter = { package = "examples:counter", version = "0.1.0" }
EOF_NATIVE_CROSS_TARGET_ENV

mkdir -p "$NATIVE_CROSS_TARGET_ENV_DIR/.mog/toolchains"
printf '# env-discovered toolchain for package-manager tests\n' \
    > "$TEMP_DIR/env-cross-target-toolchain.cmake"
cp "$NATIVE_CONSUMER_DIR/app.mog" "$NATIVE_CROSS_TARGET_ENV_DIR/app.mog"

ENV_TOOLCHAIN_NAME="MOG_CMAKE_TOOLCHAIN_$(printf '%s' "$ALT_TARGET" | tr '[:lower:]-.' '[:upper:]__')"
if ! (cd "$NATIVE_CROSS_TARGET_ENV_DIR" && \
      env "$ENV_TOOLCHAIN_NAME=$TEMP_DIR/env-cross-target-toolchain.cmake" \
      MOG_CACHE_DIR="$TEMP_DIR/env-target-cache" \
      "$MOG" install --target "$ALT_TARGET" >/dev/null); then
    echo "[FAIL] install should auto-discover non-host native toolchains from the environment"
    exit 1
fi

NATIVE_CROSS_TARGET_NO_BUILD_DIR="$(mktemp -d)"
cat > "$NATIVE_CROSS_TARGET_NO_BUILD_DIR/mog.toml" <<EOF_NATIVE_CROSS_TARGET_NO_BUILD
kind = "project"
name = "native-cross-target-no-build"
version = "0.1.0"
description = "native cross target no build"

[registries.default]
index = "$REGISTRY_DIR"

[dependencies]
counter = { package = "examples:counter", version = "0.1.0" }
EOF_NATIVE_CROSS_TARGET_NO_BUILD

cp "$NATIVE_CONSUMER_DIR/app.mog" "$NATIVE_CROSS_TARGET_NO_BUILD_DIR/app.mog"

if (cd "$NATIVE_CROSS_TARGET_NO_BUILD_DIR" && \
    MOG_CACHE_DIR="$TEMP_DIR/cross-target-no-build-cache" "$MOG" install \
    --target "$ALT_TARGET" --no-native-build \
    --cmake-toolchain "$TEMP_DIR/cross-target-toolchain.cmake" \
    >/tmp/mog_native_cross_target_no_build_failure.txt 2>&1); then
    echo "[FAIL] install --no-native-build should still reject non-host source-only native packages"
    cat /tmp/mog_native_cross_target_no_build_failure.txt
    exit 1
fi

if ! grep -Fq -- "--no-native-build forbids using it" \
    /tmp/mog_native_cross_target_no_build_failure.txt; then
    echo "[FAIL] install --no-native-build should still explain non-host source-fallback rejection"
    cat /tmp/mog_native_cross_target_no_build_failure.txt
    exit 1
fi

cat > "$NATIVE_NO_CMAKE_DIR/mog.toml" <<EOF_NATIVE_NO_CMAKE
kind = "project"
name = "native-no-cmake"
version = "0.1.0"
description = "native no cmake"

[registries.default]
index = "$REGISTRY_DIR"

[dependencies]
counter = { package = "examples:counter", version = "0.1.0" }
EOF_NATIVE_NO_CMAKE

cp "$NATIVE_CONSUMER_DIR/app.mog" "$NATIVE_NO_CMAKE_DIR/app.mog"

if (cd "$NATIVE_NO_CMAKE_DIR" && MOG_CACHE_DIR="$TEMP_DIR/no-native-build-cache" \
    "$MOG" install --no-native-build >/tmp/mog_native_no_build_failure.txt 2>&1); then
    echo "[FAIL] install --no-native-build should reject source-only native registry packages"
    cat /tmp/mog_native_no_build_failure.txt
    exit 1
fi

if ! grep -Fq -- "--no-native-build forbids using it" /tmp/mog_native_no_build_failure.txt; then
    echo "[FAIL] install --no-native-build should explain source-fallback rejection"
    cat /tmp/mog_native_no_build_failure.txt
    exit 1
fi

if (cd "$NATIVE_NO_CMAKE_DIR" && MOG_CACHE_DIR="$TEMP_DIR/source-offline-cache" \
    "$MOG" install --offline >/tmp/mog_native_source_offline_failure.txt 2>&1); then
    echo "[FAIL] install --offline should reject uncached source-built native packages"
    cat /tmp/mog_native_source_offline_failure.txt
    exit 1
fi

if ! grep -Eq "offline|cached locally" /tmp/mog_native_source_offline_failure.txt; then
    echo "[FAIL] install --offline should explain missing cached source-built native packages"
    cat /tmp/mog_native_source_offline_failure.txt
    exit 1
fi

if (cd "$NATIVE_NO_CMAKE_DIR" && PATH="" MOG_CACHE_DIR="$TEMP_DIR/missing-cmake-cache" \
    "$MOG" install >/tmp/mog_native_missing_cmake_failure.txt 2>&1); then
    echo "[FAIL] install should report missing cmake for native source fallback"
    cat /tmp/mog_native_missing_cmake_failure.txt
    exit 1
fi

if ! grep -Fq "requires CMake" /tmp/mog_native_missing_cmake_failure.txt; then
    echo "[FAIL] install should explain missing cmake for native source fallback"
    cat /tmp/mog_native_missing_cmake_failure.txt
    exit 1
fi

cat > "$NATIVE_BUILD_FAIL_DIR/mog.toml" <<EOF_NATIVE_BUILD_FAIL
kind = "project"
name = "native-build-fail"
version = "0.1.0"
description = "native build fail"

[registries.default]
index = "$REGISTRY_DIR"

[dependencies]
counter = { package = "examples:counter", version = "0.1.2" }
EOF_NATIVE_BUILD_FAIL

cp "$NATIVE_CONSUMER_DIR/app.mog" "$NATIVE_BUILD_FAIL_DIR/app.mog"

mkdir -p "$REGISTRY_DIR/packages/examples/counter/0.1.2/source"
cp "$REGISTRY_DIR/packages/examples/counter/0.1.0/source/mog.toml" \
   "$REGISTRY_DIR/packages/examples/counter/0.1.0/source/package.api.mog" \
   "$REGISTRY_DIR/packages/examples/counter/0.1.0/source/NativePackageAPI.hpp" \
   "$REGISTRY_DIR/packages/examples/counter/0.1.2/source/"
python3 - "$REGISTRY_DIR/packages/examples/counter/0.1.2/source/mog.toml" <<'PY'
from pathlib import Path
import sys

path = Path(sys.argv[1])
text = path.read_text(encoding="utf-8")
updated = text.replace('version = "0.1.0"', 'version = "0.1.2"', 1)
if updated == text:
    raise SystemExit("failed to update source-build failure test manifest version")
path.write_text(updated, encoding="utf-8")
PY
cat > "$REGISTRY_DIR/packages/examples/counter/0.1.2/source/package.cpp" <<'EOF_BAD_BUILD_CPP'
#include "NativePackageAPI.hpp"
this is not valid c++
EOF_BAD_BUILD_CPP

python3 - "$REGISTRY_DIR" <<'PY'
from pathlib import Path
import hashlib
import sys
import tomllib

registry_dir = Path(sys.argv[1])
index_path = registry_dir / "index.toml"
data = tomllib.loads(index_path.read_text(encoding="utf-8"))

def digest_directory(root: Path) -> str:
    files = sorted(path for path in root.rglob("*") if path.is_file())
    seed = bytearray()
    for path in files:
        seed.extend(path.relative_to(root).as_posix().encode("utf-8"))
        seed.extend(b"\n")
        seed.extend(path.read_bytes())
        seed.extend(b"\n")
    return "sha256:" + hashlib.sha256(seed).hexdigest()

packages = data.get("package", [])
packages.append({
    "package_id": "examples:counter",
    "version": "0.1.2",
    "artifact_path": "packages/examples/counter/0.1.2/source",
    "artifact_digest": digest_directory(registry_dir / "packages" / "examples" / "counter" / "0.1.2" / "source"),
    "dependencies": [],
})

parts = ['schema_version = "registry.v1"']
for package in packages:
    parts.append("")
    parts.append("[[package]]")
    parts.append(f'package_id = "{package["package_id"]}"')
    parts.append(f'version = "{package["version"]}"')
    if "artifact_path" in package:
        parts.append(f'artifact_path = "{package["artifact_path"]}"')
    if "artifact_digest" in package:
        parts.append(f'artifact_digest = "{package["artifact_digest"]}"')
    if "native_targets" in package:
        targets = ", ".join(f'"{value}"' for value in package["native_targets"])
        paths = ", ".join(f'"{value}"' for value in package["native_artifact_paths"])
        digests = ", ".join(f'"{value}"' for value in package["native_artifact_digests"])
        parts.append(f"native_targets = [{targets}]")
        parts.append(f"native_artifact_paths = [{paths}]")
        parts.append(f"native_artifact_digests = [{digests}]")
    deps = ", ".join(f'"{value}"' for value in package.get("dependencies", []))
    parts.append(f"dependencies = [{deps}]")

index_path.write_text("\n".join(parts) + "\n", encoding="utf-8")
PY

if (cd "$NATIVE_BUILD_FAIL_DIR" && MOG_CACHE_DIR="$TEMP_DIR/build-fail-cache" \
    "$MOG" install >/tmp/mog_native_build_failure.txt 2>&1); then
    echo "[FAIL] install should report native source-build failures"
    cat /tmp/mog_native_build_failure.txt
    exit 1
fi

if ! grep -Fq "source-build fallback for target '$HOST_TARGET' failed." \
    /tmp/mog_native_build_failure.txt; then
    echo "[FAIL] install should explain native source-build failures"
    cat /tmp/mog_native_build_failure.txt
    exit 1
fi

NATIVE_SYSDEP_FAIL_DIR="$(mktemp -d)"
cat > "$NATIVE_SYSDEP_FAIL_DIR/mog.toml" <<EOF_NATIVE_SYSDEP_FAIL
kind = "project"
name = "native-sysdep-fail"
version = "0.1.0"
description = "native sysdep fail"

[registries.default]
index = "$REGISTRY_DIR"

[dependencies]
sysdep = { package = "acme:sysdep-demo", version = "1.0.0" }
EOF_NATIVE_SYSDEP_FAIL

cat > "$NATIVE_SYSDEP_FAIL_DIR/app.mog" <<'EOF_NATIVE_SYSDEP_FAIL_APP'
const sysdep = @import("sysdep")
print(sysdep.PACKAGE_ID)
EOF_NATIVE_SYSDEP_FAIL_APP

mkdir -p "$REGISTRY_DIR/packages/acme/sysdep-demo/1.0.0/source"
cat > "$REGISTRY_DIR/packages/acme/sysdep-demo/1.0.0/source/mog.toml" <<'EOF_SYSDEP_MANIFEST'
kind = "native"
import_name = "sysdep"
namespace = "acme"
name = "sysdep-demo"
version = "1.0.0"
abi_version = 3
author = "Registry test"
description = "Published native package with system dependency diagnostics."
dependencies = []

[system-dependencies]
libmagic = { version = ">=1.0", required = true }
EOF_SYSDEP_MANIFEST

cat > "$REGISTRY_DIR/packages/acme/sysdep-demo/1.0.0/source/package.api.mog" <<'EOF_SYSDEP_API'
package sysdep

const PACKAGE_ID str
EOF_SYSDEP_API

cat > "$REGISTRY_DIR/packages/acme/sysdep-demo/1.0.0/source/CMakeLists.txt" <<'EOF_SYSDEP_CMAKE'
cmake_minimum_required(VERSION 3.10)
project(sysdep_demo LANGUAGES CXX)
message(FATAL_ERROR "libmagic not found for sysdep demo package")
EOF_SYSDEP_CMAKE

python3 - "$REGISTRY_DIR" <<'PY'
from pathlib import Path
import hashlib
import sys
import tomllib

registry_dir = Path(sys.argv[1])
index_path = registry_dir / "index.toml"
data = tomllib.loads(index_path.read_text(encoding="utf-8"))

def digest_directory(root: Path) -> str:
    files = sorted(path for path in root.rglob("*") if path.is_file())
    seed = bytearray()
    for path in files:
        seed.extend(path.relative_to(root).as_posix().encode("utf-8"))
        seed.extend(b"\n")
        seed.extend(path.read_bytes())
        seed.extend(b"\n")
    return "sha256:" + hashlib.sha256(seed).hexdigest()

packages = data.get("package", [])
packages.append({
    "package_id": "acme:sysdep-demo",
    "version": "1.0.0",
    "artifact_path": "packages/acme/sysdep-demo/1.0.0/source",
    "artifact_digest": digest_directory(registry_dir / "packages" / "acme" / "sysdep-demo" / "1.0.0" / "source"),
    "dependencies": [],
})

parts = ['schema_version = "registry.v1"']
for package in packages:
    parts.append("")
    parts.append("[[package]]")
    parts.append(f'package_id = "{package["package_id"]}"')
    parts.append(f'version = "{package["version"]}"')
    if "artifact_path" in package:
        parts.append(f'artifact_path = "{package["artifact_path"]}"')
    if "artifact_digest" in package:
        parts.append(f'artifact_digest = "{package["artifact_digest"]}"')
    if "native_targets" in package:
        targets = ", ".join(f'"{value}"' for value in package["native_targets"])
        paths = ", ".join(f'"{value}"' for value in package["native_artifact_paths"])
        digests = ", ".join(f'"{value}"' for value in package["native_artifact_digests"])
        parts.append(f"native_targets = [{targets}]")
        parts.append(f"native_artifact_paths = [{paths}]")
        parts.append(f"native_artifact_digests = [{digests}]")
    deps = ", ".join(f'"{value}"' for value in package.get("dependencies", []))
    parts.append(f"dependencies = [{deps}]")

index_path.write_text("\n".join(parts) + "\n", encoding="utf-8")
PY

if (cd "$NATIVE_SYSDEP_FAIL_DIR" && \
    MOG_CACHE_DIR="$TEMP_DIR/sysdep-fail-cache" "$MOG" install \
    >/tmp/mog_native_sysdep_failure.txt 2>&1); then
    echo "[FAIL] install should report missing declared system dependencies"
    cat /tmp/mog_native_sysdep_failure.txt
    exit 1
fi

if ! grep -Fq "could not find required system dependency 'libmagic'" \
    /tmp/mog_native_sysdep_failure.txt || \
   ! grep -Fq "Required system dependencies: libmagic (>=1.0)." \
    /tmp/mog_native_sysdep_failure.txt; then
    echo "[FAIL] install should surface declared system dependency diagnostics"
    cat /tmp/mog_native_sysdep_failure.txt
    exit 1
fi

mkdir -p "$REGISTRY_DIR/packages/examples/counter/0.1.0/$ALT_TARGET"
cp "$REGISTRY_DIR/packages/examples/counter/0.1.0/$HOST_TARGET/mog.toml" \
   "$REGISTRY_DIR/packages/examples/counter/0.1.0/$ALT_TARGET/mog.toml"
cp "$REGISTRY_DIR/packages/examples/counter/0.1.0/$HOST_TARGET/package.api.mog" \
   "$REGISTRY_DIR/packages/examples/counter/0.1.0/$ALT_TARGET/package.api.mog"
cp "$REGISTRY_DIR/packages/examples/counter/0.1.0/$HOST_TARGET/package.so" \
   "$REGISTRY_DIR/packages/examples/counter/0.1.0/$ALT_TARGET/package.so"

python3 - "$REGISTRY_DIR" "$HOST_TARGET" "$ALT_TARGET" <<'PY'
from pathlib import Path
import hashlib
import sys
import tomllib

registry_dir = Path(sys.argv[1])
host_target = sys.argv[2]
alt_target = sys.argv[3]
index_path = registry_dir / "index.toml"
data = tomllib.loads(index_path.read_text(encoding="utf-8"))

def digest_directory(root: Path) -> str:
    files = sorted(path for path in root.rglob("*") if path.is_file())
    seed = bytearray()
    for path in files:
        seed.extend(path.relative_to(root).as_posix().encode("utf-8"))
        seed.extend(b"\n")
        seed.extend(path.read_bytes())
        seed.extend(b"\n")
    return "sha256:" + hashlib.sha256(seed).hexdigest()

packages = data.get("package", [])
for package in packages:
    if package.get("package_id") == "examples:counter" and package.get("version") == "0.1.0":
        host_dir = registry_dir / "packages" / "examples" / "counter" / "0.1.0" / host_target
        alt_dir = registry_dir / "packages" / "examples" / "counter" / "0.1.0" / alt_target
        package["native_targets"] = [host_target, alt_target]
        package["native_artifact_paths"] = [
            host_dir.relative_to(registry_dir).as_posix(),
            alt_dir.relative_to(registry_dir).as_posix(),
        ]
        package["native_artifact_digests"] = [
            digest_directory(host_dir),
            digest_directory(alt_dir),
        ]
        break
else:
    raise SystemExit("missing examples:counter@0.1.0 in registry index")

parts = ['schema_version = "registry.v1"']
for package in packages:
    parts.append("")
    parts.append("[[package]]")
    parts.append(f'package_id = "{package["package_id"]}"')
    parts.append(f'version = "{package["version"]}"')
    if "artifact_path" in package:
        parts.append(f'artifact_path = "{package["artifact_path"]}"')
    if "artifact_digest" in package:
        parts.append(f'artifact_digest = "{package["artifact_digest"]}"')
    if "native_targets" in package:
        targets = ", ".join(f'"{value}"' for value in package["native_targets"])
        paths = ", ".join(f'"{value}"' for value in package["native_artifact_paths"])
        digests = ", ".join(f'"{value}"' for value in package["native_artifact_digests"])
        parts.append(f"native_targets = [{targets}]")
        parts.append(f"native_artifact_paths = [{paths}]")
        parts.append(f"native_artifact_digests = [{digests}]")
    deps = ", ".join(f'"{value}"' for value in package.get("dependencies", []))
    parts.append(f"dependencies = [{deps}]")

index_path.write_text("\n".join(parts) + "\n", encoding="utf-8")
PY

NATIVE_TARGET_DIR="$(mktemp -d)"
cat > "$NATIVE_TARGET_DIR/mog.toml" <<EOF_NATIVE_TARGET
kind = "project"
name = "native-target-consumer"
version = "0.1.0"
description = "native target consumer"

[registries.default]
index = "$REGISTRY_DIR"

[dependencies]
counter = { package = "examples:counter", version = "0.1.0" }
EOF_NATIVE_TARGET

cp "$NATIVE_CONSUMER_DIR/app.mog" "$NATIVE_TARGET_DIR/app.mog"

if ! (cd "$NATIVE_TARGET_DIR" && \
      "$MOG" install --target "$ALT_TARGET" --prefer-prebuilt >/dev/null); then
    echo "[FAIL] install should select a non-host native artifact when --target is provided"
    exit 1
fi

if ! grep -Fq "selected_target = \"$ALT_TARGET\"" "$NATIVE_TARGET_DIR/mog.lock"; then
    echo "[FAIL] lockfile should pin the explicitly selected native target"
    cat "$NATIVE_TARGET_DIR/mog.lock"
    exit 1
fi

ALT_TARGET_OUTPUT="$("$MOG" run --locked --target "$ALT_TARGET" "$NATIVE_TARGET_DIR/app.mog")"
if [[ "$ALT_TARGET_OUTPUT" != *"examples:counter"* || "$ALT_TARGET_OUTPUT" != *"15"* ]]; then
    echo "[FAIL] run --locked should use the explicitly selected native target artifact"
    echo "$ALT_TARGET_OUTPUT"
    exit 1
fi

NATIVE_TARGET_FAIL_DIR="$(mktemp -d)"
cat > "$NATIVE_TARGET_FAIL_DIR/mog.toml" <<EOF_NATIVE_TARGET_FAIL
kind = "project"
name = "native-target-fail"
version = "0.1.0"
description = "native target fail"

[registries.default]
index = "$REGISTRY_DIR"

[dependencies]
counter = { package = "examples:counter", version = "0.1.0" }
EOF_NATIVE_TARGET_FAIL

if (cd "$NATIVE_TARGET_FAIL_DIR" && \
    "$MOG" install --target "unsupported-target" >/tmp/mog_native_target_failure.txt 2>&1); then
    echo "[FAIL] install should reject unsupported native target selections"
    cat /tmp/mog_native_target_failure.txt
    exit 1
fi

if ! grep -Eq "does not publish a prebuilt native artifact for target|source-build fallback currently supports only the host target" /tmp/mog_native_target_failure.txt; then
    echo "[FAIL] install should explain unsupported native target selections"
    cat /tmp/mog_native_target_failure.txt
    exit 1
fi

printf 'not a valid native package\n' > \
    "$REGISTRY_DIR/packages/examples/counter/0.1.0/$HOST_TARGET/package.so"
rm -f "$NATIVE_CONSUMER_DIR/.mog/install/registry.toml"
LOCKED_NATIVE_OUTPUT="$("$MOG" run --locked --target "$HOST_TARGET" "$NATIVE_CONSUMER_DIR/app.mog")"
if [[ "$LOCKED_NATIVE_OUTPUT" != *"examples:counter"* || "$LOCKED_NATIVE_OUTPUT" != *"15"* ]]; then
    echo "[FAIL] run --locked should continue to use the pinned native artifact"
    echo "$LOCKED_NATIVE_OUTPUT"
    exit 1
fi

mkdir -p "$REGISTRY_DIR/packages/examples/counter/0.1.1"
cat > "$REGISTRY_DIR/packages/examples/counter/0.1.1/mog.toml" <<'EOF_BAD_NATIVE_API_MANIFEST'
kind = "native"
import_name = "counter"
namespace = "examples"
name = "counter"
version = "0.1.1"
abi_version = 3
author = "Registry test"
description = "Published native package with a bad API."
dependencies = []
EOF_BAD_NATIVE_API_MANIFEST
cat > "$REGISTRY_DIR/packages/examples/counter/0.1.1/package.api.mog" <<'EOF_BAD_NATIVE_API'
package counter

@doc("GC-managed opaque counter handle.")
@native_handle("CounterHandle")
opaque type Counter

@doc("Canonical namespaced package identifier.")
const PACKAGE_ID str

@doc("Create a new counter handle.")
fn create(initial i64) Counter

@doc("Read the current counter value.")
fn read(counter Counter) i64

@doc("Add to the counter and return the updated value.")
fn add(counter Counter, delta str) i64
EOF_BAD_NATIVE_API
cp "$PROJECT_ROOT/build/packages/examples/counter/package.so" \
   "$REGISTRY_DIR/packages/examples/counter/0.1.1/package.so"

mkdir -p "$REGISTRY_DIR/packages/acme/native-missing/1.0.0"
cat > "$REGISTRY_DIR/packages/acme/native-missing/1.0.0/mog.toml" <<'EOF_MISSING_NATIVE_MANIFEST'
kind = "native"
import_name = "native_missing"
namespace = "acme"
name = "native-missing"
version = "1.0.0"
abi_version = 3
author = "Registry test"
description = "Published native package missing its library."
dependencies = []
EOF_MISSING_NATIVE_MANIFEST
cat > "$REGISTRY_DIR/packages/acme/native-missing/1.0.0/package.api.mog" <<'EOF_MISSING_NATIVE_API'
package native_missing

const PACKAGE_ID str
EOF_MISSING_NATIVE_API

python3 - "$REGISTRY_DIR" "$HOST_TARGET" <<'PY'
from pathlib import Path
import hashlib
import sys
import tomllib

registry_dir = Path(sys.argv[1])
host_target = sys.argv[2]
index_path = registry_dir / "index.toml"
data = tomllib.loads(index_path.read_text(encoding="utf-8"))

def digest_directory(root: Path) -> str:
    files = sorted(path for path in root.rglob("*") if path.is_file())
    seed = bytearray()
    for path in files:
        seed.extend(path.relative_to(root).as_posix().encode("utf-8"))
        seed.extend(b"\n")
        seed.extend(path.read_bytes())
        seed.extend(b"\n")
    return "sha256:" + hashlib.sha256(seed).hexdigest()

packages = data.get("package", [])
packages.append({
    "package_id": "examples:counter",
    "version": "0.1.1",
    "native_targets": [host_target],
    "native_artifact_paths": ["packages/examples/counter/0.1.1"],
    "native_artifact_digests": [digest_directory(registry_dir / "packages" / "examples" / "counter" / "0.1.1")],
    "dependencies": [],
})
packages.append({
    "package_id": "acme:native-missing",
    "version": "1.0.0",
    "native_targets": [host_target],
    "native_artifact_paths": ["packages/acme/native-missing/1.0.0"],
    "native_artifact_digests": [digest_directory(registry_dir / "packages" / "acme" / "native-missing" / "1.0.0")],
    "dependencies": [],
})

parts = ['schema_version = "registry.v1"']
for package in packages:
    parts.append("")
    parts.append("[[package]]")
    parts.append(f'package_id = "{package["package_id"]}"')
    parts.append(f'version = "{package["version"]}"')
    if "artifact_path" in package:
        parts.append(f'artifact_path = "{package["artifact_path"]}"')
    if "artifact_digest" in package:
        parts.append(f'artifact_digest = "{package["artifact_digest"]}"')
    if "native_targets" in package:
        targets = ", ".join(f'"{value}"' for value in package["native_targets"])
        paths = ", ".join(f'"{value}"' for value in package["native_artifact_paths"])
        digests = ", ".join(f'"{value}"' for value in package["native_artifact_digests"])
        parts.append(f"native_targets = [{targets}]")
        parts.append(f"native_artifact_paths = [{paths}]")
        parts.append(f"native_artifact_digests = [{digests}]")
    deps = ", ".join(f'"{value}"' for value in package.get("dependencies", []))
    parts.append(f"dependencies = [{deps}]")

index_path.write_text("\n".join(parts) + "\n", encoding="utf-8")
PY

cat > "$NATIVE_BAD_DIR/mog.toml" <<EOF_BAD_NATIVE_API_CONSUMER
kind = "project"
name = "bad-native-api"
version = "0.1.0"
description = "bad native api"

[registries.default]
index = "$REGISTRY_DIR"

[dependencies]
counter = { package = "examples:counter", version = "0.1.1" }
EOF_BAD_NATIVE_API_CONSUMER

if (cd "$NATIVE_BAD_DIR" && "$MOG" install >/tmp/mog_native_bad_api_failure.txt 2>&1); then
    echo "[FAIL] install should reject published native packages with invalid APIs"
    cat /tmp/mog_native_bad_api_failure.txt
    exit 1
fi

if ! grep -Fq "type mismatch" /tmp/mog_native_bad_api_failure.txt; then
    echo "[FAIL] install should explain native API validation failures"
    cat /tmp/mog_native_bad_api_failure.txt
    exit 1
fi

cat > "$NATIVE_BAD_DIR/mog.toml" <<EOF_MISSING_NATIVE_CONSUMER
kind = "project"
name = "missing-native"
version = "0.1.0"
description = "missing native library"

[registries.default]
index = "$REGISTRY_DIR"

[dependencies]
missing = { package = "acme:native-missing", version = "1.0.0" }
EOF_MISSING_NATIVE_CONSUMER

if (cd "$NATIVE_BAD_DIR" && "$MOG" install >/tmp/mog_native_missing_failure.txt 2>&1); then
    echo "[FAIL] install should reject published native packages without a shared library"
    cat /tmp/mog_native_missing_failure.txt
    exit 1
fi

if ! grep -Eq "built library|shared library" /tmp/mog_native_missing_failure.txt; then
    echo "[FAIL] install should explain missing native shared libraries"
    cat /tmp/mog_native_missing_failure.txt
    exit 1
fi

HOSTED_REGISTRY_DIR="$(mktemp -d)"
HOSTED_TOKEN="secret-token"
HOSTED_PORT="$(start_hosted_registry_server "$HOSTED_REGISTRY_DIR" "$HOSTED_TOKEN")"

HOSTED_PUBLISH_WORKSPACE="$(mktemp -d)"
HOSTED_KEY_FILE="$HOSTED_PUBLISH_WORKSPACE/hosted-registry-key.toml"
create_signing_key "$HOSTED_KEY_FILE" "hosted-registry"
HOSTED_PUBLIC_KEY_FILE="$HOSTED_PUBLISH_WORKSPACE/hosted-registry-public-key.toml"
create_public_key_file "$HOSTED_KEY_FILE" "$HOSTED_PUBLIC_KEY_FILE"
cp "$HOSTED_PUBLIC_KEY_FILE" "$HOSTED_REGISTRY_DIR/registry-public-key.v1"
cat > "$HOSTED_REGISTRY_DIR/registry-service.v1" <<'EOF_HOSTED_SERVICE'
schema_version = "registry-service.v1"
artifact_upload_mode = "content-addressed"
index_update_mode = "etag-if-match"
EOF_HOSTED_SERVICE
HOSTED_TRUSTED_KEY="$(trusted_key_spec "$HOSTED_KEY_FILE")"
HOSTED_PUBLISH_CONFIG="$TEMP_DIR/hosted-publish-config"
mkdir -p "$HOSTED_PUBLISH_WORKSPACE/pkg/src"
cat > "$HOSTED_PUBLISH_WORKSPACE/mog.toml" <<EOF_HOSTED_PUBLISH_ROOT
kind = "project"
name = "hosted-publish-root"
version = "0.1.0"
description = "hosted publish root"

[registries.default]
index = "http://127.0.0.1:$HOSTED_PORT/index.toml"
trusted_keys = ["$HOSTED_TRUSTED_KEY"]
EOF_HOSTED_PUBLISH_ROOT

cat > "$HOSTED_PUBLISH_WORKSPACE/pkg/mog.toml" <<'EOF_HOSTED_PACKAGE'
kind = "source"
import_name = "hosted_util"
namespace = "acme"
name = "hosted-util"
version = "1.0.0"
license = "MIT"
author = "Hosted registry test"
description = "Hosted utility package."
entry = "src/main.mog"
dependencies = []
EOF_HOSTED_PACKAGE

cat > "$HOSTED_PUBLISH_WORKSPACE/pkg/src/main.mog" <<'EOF_HOSTED_PACKAGE_SRC'
const MESSAGE str = "utility from hosted registry"

fn Name() str {
    return MESSAGE
}
EOF_HOSTED_PACKAGE_SRC

if ! (cd "$HOSTED_PUBLISH_WORKSPACE" && \
    XDG_CONFIG_HOME="$HOSTED_PUBLISH_CONFIG" \
    "$MOG" login default --token "$HOSTED_TOKEN" >/dev/null); then
    echo "[FAIL] login should store a hosted registry token"
    exit 1
fi

if [[ ! -f "$HOSTED_PUBLISH_CONFIG/mog/registries.toml" ]]; then
    echo "[FAIL] login should store hosted registry credentials in registries.toml"
    exit 1
fi

if [[ -f "$HOSTED_PUBLISH_CONFIG/mog/auth.toml" ]]; then
    echo "[FAIL] login should stop writing new credentials to auth.toml"
    exit 1
fi

if ! grep -Fq 'token = "'"$HOSTED_TOKEN"'"' "$HOSTED_PUBLISH_CONFIG/mog/registries.toml"; then
    echo "[FAIL] login should persist the hosted registry token in registries.toml"
    cat "$HOSTED_PUBLISH_CONFIG/mog/registries.toml"
    exit 1
fi

if ! (cd "$HOSTED_PUBLISH_WORKSPACE" && \
    XDG_CONFIG_HOME="$HOSTED_PUBLISH_CONFIG" \
    "$MOG" publish --signing-key "$HOSTED_KEY_FILE" pkg >/dev/null); then
    echo "[FAIL] publish should upload a hosted registry package"
    exit 1
fi

if ! grep -Fq 'artifact_path = "blobs/sha256/' "$HOSTED_REGISTRY_DIR/index.toml"; then
    echo "[FAIL] registry-service.v1 publish should store content-addressed artifact paths"
    cat "$HOSTED_REGISTRY_DIR/index.toml"
    exit 1
fi

if ! (cd "$HOSTED_PUBLISH_WORKSPACE" && \
    XDG_CONFIG_HOME="$HOSTED_PUBLISH_CONFIG" \
    "$MOG" publish --signing-key "$HOSTED_KEY_FILE" pkg >/dev/null); then
    echo "[FAIL] repeated hosted publish with identical contents should remain idempotent"
    exit 1
fi

touch "$HOSTED_REGISTRY_DIR/conflict-once"
if (cd "$HOSTED_PUBLISH_WORKSPACE" && \
    XDG_CONFIG_HOME="$HOSTED_PUBLISH_CONFIG" \
    "$MOG" publish --signing-key "$HOSTED_KEY_FILE" pkg \
    >/tmp/mog_hosted_conflict_failure.txt 2>&1); then
    echo "[FAIL] hosted publish should fail when the registry index changes concurrently"
    cat /tmp/mog_hosted_conflict_failure.txt
    exit 1
fi

if ! grep -Eq "index.toml changed|Rerun 'mog publish'|412" \
    /tmp/mog_hosted_conflict_failure.txt; then
    echo "[FAIL] hosted publish conflict should explain the stale registry index"
    cat /tmp/mog_hosted_conflict_failure.txt
    exit 1
fi

touch "$HOSTED_REGISTRY_DIR/disable-index-etag"
if (cd "$HOSTED_PUBLISH_WORKSPACE" && \
    XDG_CONFIG_HOME="$HOSTED_PUBLISH_CONFIG" \
    "$MOG" publish --signing-key "$HOSTED_KEY_FILE" pkg \
    >/tmp/mog_hosted_missing_etag_failure.txt 2>&1); then
    echo "[FAIL] registry-service.v1 publish should require an ETag on index downloads"
    cat /tmp/mog_hosted_missing_etag_failure.txt
    exit 1
fi
rm -f "$HOSTED_REGISTRY_DIR/disable-index-etag"

if ! grep -Eq "ETag|registry-service.v1" /tmp/mog_hosted_missing_etag_failure.txt; then
    echo "[FAIL] missing ETag failure should mention the hosted protocol requirement"
    cat /tmp/mog_hosted_missing_etag_failure.txt
    exit 1
fi

HOSTED_POLICY_REGISTRY_DIR="$(mktemp -d)"
HOSTED_POLICY_PORT="$(start_hosted_registry_server "$HOSTED_POLICY_REGISTRY_DIR" "$HOSTED_TOKEN")"
cp "$HOSTED_PUBLIC_KEY_FILE" "$HOSTED_POLICY_REGISTRY_DIR/registry-public-key.v1"
cat > "$HOSTED_POLICY_REGISTRY_DIR/registry-service.v1" <<'EOF_HOSTED_POLICY_SERVICE'
schema_version = "registry-service.v1"
artifact_upload_mode = "content-addressed"
index_update_mode = "etag-if-match"
publish_policy = "registry-publish-policy.v1"
EOF_HOSTED_POLICY_SERVICE
cat > "$HOSTED_POLICY_REGISTRY_DIR/registry-publish-policy.v1" <<'EOF_HOSTED_POLICY'
schema_version = "registry-publish-policy.v1"
require_signed_publish = true
require_clean_git = true
require_tag = true
allowed_namespaces = ["acme"]
EOF_HOSTED_POLICY

HOSTED_POLICY_WORKSPACE="$(mktemp -d)"
HOSTED_POLICY_CONFIG="$TEMP_DIR/hosted-policy-config"
mkdir -p "$HOSTED_POLICY_WORKSPACE/pkg/src"
cat > "$HOSTED_POLICY_WORKSPACE/mog.toml" <<EOF_HOSTED_POLICY_ROOT
kind = "project"
name = "hosted-policy-root"
version = "0.1.0"
description = "hosted policy root"

[registries.default]
index = "http://127.0.0.1:$HOSTED_POLICY_PORT/index.toml"
allow_insecure = true
EOF_HOSTED_POLICY_ROOT
cat > "$HOSTED_POLICY_WORKSPACE/pkg/mog.toml" <<'EOF_HOSTED_POLICY_PACKAGE'
kind = "source"
import_name = "policy_util"
namespace = "acme"
name = "policy-util"
version = "1.0.0"
license = "MIT"
description = "Hosted publish policy package."
entry = "src/main.mog"
dependencies = []
EOF_HOSTED_POLICY_PACKAGE
cat > "$HOSTED_POLICY_WORKSPACE/pkg/src/main.mog" <<'EOF_HOSTED_POLICY_SRC'
fn Name() str {
    return "policy util"
}
EOF_HOSTED_POLICY_SRC
mkdir -p "$HOSTED_POLICY_WORKSPACE/bad-pkg/src"
cat > "$HOSTED_POLICY_WORKSPACE/bad-pkg/mog.toml" <<'EOF_HOSTED_POLICY_BAD_PACKAGE'
kind = "source"
import_name = "bad_policy_util"
namespace = "other"
name = "bad-policy-util"
version = "1.0.0"
license = "MIT"
description = "Hosted publish policy disallowed package."
entry = "src/main.mog"
dependencies = []
EOF_HOSTED_POLICY_BAD_PACKAGE
cat > "$HOSTED_POLICY_WORKSPACE/bad-pkg/src/main.mog" <<'EOF_HOSTED_POLICY_BAD_SRC'
fn Name() str {
    return "bad policy util"
}
EOF_HOSTED_POLICY_BAD_SRC
git -C "$HOSTED_POLICY_WORKSPACE" init >/dev/null
git -C "$HOSTED_POLICY_WORKSPACE" config user.email "mog@example.invalid"
git -C "$HOSTED_POLICY_WORKSPACE" config user.name "Mog Test"
git -C "$HOSTED_POLICY_WORKSPACE" add .
git -C "$HOSTED_POLICY_WORKSPACE" commit -m "initial hosted policy package" >/dev/null
git -C "$HOSTED_POLICY_WORKSPACE" tag v1.0.0

if ! (cd "$HOSTED_POLICY_WORKSPACE" && \
    XDG_CONFIG_HOME="$HOSTED_POLICY_CONFIG" \
    "$MOG" login default --token "$HOSTED_TOKEN" >/dev/null); then
    echo "[FAIL] hosted policy test should store registry credentials"
    exit 1
fi

if (cd "$HOSTED_POLICY_WORKSPACE" && \
    XDG_CONFIG_HOME="$HOSTED_POLICY_CONFIG" \
    "$MOG" publish --tag v1.0.0 pkg \
    >/tmp/mog_hosted_policy_unsigned_failure.txt 2>&1); then
    echo "[FAIL] hosted publish policy should reject unsigned publishes"
    cat /tmp/mog_hosted_policy_unsigned_failure.txt
    exit 1
fi
if ! grep -Fq "requires signed publishes" /tmp/mog_hosted_policy_unsigned_failure.txt; then
    echo "[FAIL] unsigned publish policy failure should mention signed publishes"
    cat /tmp/mog_hosted_policy_unsigned_failure.txt
    exit 1
fi

if (cd "$HOSTED_POLICY_WORKSPACE" && \
    XDG_CONFIG_HOME="$HOSTED_POLICY_CONFIG" \
    "$MOG" publish --signing-key "$HOSTED_KEY_FILE" pkg \
    >/tmp/mog_hosted_policy_tag_failure.txt 2>&1); then
    echo "[FAIL] hosted publish policy should require version tags"
    cat /tmp/mog_hosted_policy_tag_failure.txt
    exit 1
fi
if ! grep -Fq "requires a version tag" /tmp/mog_hosted_policy_tag_failure.txt; then
    echo "[FAIL] tag policy failure should mention --tag"
    cat /tmp/mog_hosted_policy_tag_failure.txt
    exit 1
fi

if (cd "$HOSTED_POLICY_WORKSPACE" && \
    XDG_CONFIG_HOME="$HOSTED_POLICY_CONFIG" \
    "$MOG" publish --signing-key "$HOSTED_KEY_FILE" --tag v1.0.0 bad-pkg \
    >/tmp/mog_hosted_policy_namespace_failure.txt 2>&1); then
    echo "[FAIL] hosted publish policy should reject disallowed namespaces"
    cat /tmp/mog_hosted_policy_namespace_failure.txt
    exit 1
fi
if ! grep -Fq "disallows package namespace" /tmp/mog_hosted_policy_namespace_failure.txt; then
    echo "[FAIL] namespace policy failure should mention the disallowed namespace"
    cat /tmp/mog_hosted_policy_namespace_failure.txt
    exit 1
fi

if ! (cd "$HOSTED_POLICY_WORKSPACE" && \
    XDG_CONFIG_HOME="$HOSTED_POLICY_CONFIG" \
    "$MOG" publish --signing-key "$HOSTED_KEY_FILE" --tag v1.0.0 pkg >/dev/null); then
    echo "[FAIL] hosted publish policy should allow signed clean tagged publishes"
    exit 1
fi

HOSTED_CONSUMER_DIR="$(mktemp -d)"
cat > "$HOSTED_CONSUMER_DIR/mog.toml" <<EOF_HOSTED_CONSUMER
kind = "project"
name = "hosted-consumer"
version = "0.1.0"
description = "hosted consumer"

[registries.default]
index = "http://127.0.0.1:$HOSTED_PORT/index.toml"
trusted_keys = ["$HOSTED_TRUSTED_KEY"]

[dependencies]
hosted_util = { package = "acme:hosted-util", version = "1.0.0" }
EOF_HOSTED_CONSUMER

cat > "$HOSTED_CONSUMER_DIR/app.mog" <<'EOF_HOSTED_APP'
const hosted_util = @import("hosted_util")
print(hosted_util.Name())
EOF_HOSTED_APP

if ! (cd "$HOSTED_CONSUMER_DIR" && \
    XDG_CONFIG_HOME="$HOSTED_PUBLISH_CONFIG" \
    "$MOG" install >/dev/null); then
    echo "[FAIL] install should download hosted registry packages"
    exit 1
fi

HOSTED_OUTPUT="$("$MOG" run "$HOSTED_CONSUMER_DIR/app.mog")"
if [[ "$HOSTED_OUTPUT" != *"utility from hosted registry"* ]]; then
    echo "[FAIL] run should execute hosted registry packages"
    echo "$HOSTED_OUTPUT"
    exit 1
fi

HOSTED_UNTRUSTED_DIR="$TEMP_DIR/hosted-untrusted"
mkdir -p "$HOSTED_UNTRUSTED_DIR"
cat > "$HOSTED_UNTRUSTED_DIR/mog.toml" <<EOF_HOSTED_UNTRUSTED
kind = "project"
name = "hosted-untrusted"
version = "0.1.0"
description = "hosted untrusted"

[registries.default]
index = "http://127.0.0.1:$HOSTED_PORT/index.toml"

[dependencies]
hosted_util = { package = "acme:hosted-util", version = "1.0.0" }
EOF_HOSTED_UNTRUSTED
cp "$HOSTED_CONSUMER_DIR/app.mog" "$HOSTED_UNTRUSTED_DIR/app.mog"

if (cd "$HOSTED_UNTRUSTED_DIR" && \
    XDG_CONFIG_HOME="$HOSTED_PUBLISH_CONFIG" \
    "$MOG" install \
    >/tmp/mog_hosted_untrusted_failure.txt 2>&1); then
    echo "[FAIL] hosted registries should require trusted_keys by default"
    cat /tmp/mog_hosted_untrusted_failure.txt
    exit 1
fi

if ! grep -Eq "trusted_keys|signed registry" /tmp/mog_hosted_untrusted_failure.txt; then
    echo "[FAIL] hosted trust failure should explain the missing trusted_keys requirement"
    cat /tmp/mog_hosted_untrusted_failure.txt
    exit 1
fi

HOSTED_BOOTSTRAP_DIR="$TEMP_DIR/hosted-bootstrap"
HOSTED_BOOTSTRAP_CONFIG="$TEMP_DIR/hosted-bootstrap-config"
mkdir -p "$HOSTED_BOOTSTRAP_DIR"
cat > "$HOSTED_BOOTSTRAP_DIR/mog.toml" <<EOF_HOSTED_BOOTSTRAP
kind = "project"
name = "hosted-bootstrap"
version = "0.1.0"
description = "hosted bootstrap"

[registries.default]
index = "http://127.0.0.1:$HOSTED_PORT/index.toml"

[dependencies]
hosted_util = { package = "acme:hosted-util", version = "1.0.0" }
EOF_HOSTED_BOOTSTRAP
cp "$HOSTED_CONSUMER_DIR/app.mog" "$HOSTED_BOOTSTRAP_DIR/app.mog"

if ! (cd "$HOSTED_BOOTSTRAP_DIR" && \
    XDG_CONFIG_HOME="$HOSTED_BOOTSTRAP_CONFIG" \
    "$MOG" registry trust default --bootstrap >/dev/null); then
    echo "[FAIL] registry trust --bootstrap should import hosted registry public keys from the hosted registry root"
    exit 1
fi

HOSTED_BOOTSTRAP_STATUS="$(
    cd "$HOSTED_BOOTSTRAP_DIR" && \
    XDG_CONFIG_HOME="$HOSTED_BOOTSTRAP_CONFIG" \
    "$MOG" registry status default
)"
if [[ "$HOSTED_BOOTSTRAP_STATUS" != *"trust = user"* ]] || \
   [[ "$HOSTED_BOOTSTRAP_STATUS" != *"trusted_key_ids = hosted-registry"* ]] || \
   [[ "$HOSTED_BOOTSTRAP_STATUS" != *"token = no"* ]]; then
    echo "[FAIL] registry status should report user-scoped hosted trust before login"
    echo "$HOSTED_BOOTSTRAP_STATUS"
    exit 1
fi

if ! (cd "$HOSTED_BOOTSTRAP_DIR" && \
    XDG_CONFIG_HOME="$HOSTED_BOOTSTRAP_CONFIG" \
    "$MOG" registry login default --token "$HOSTED_TOKEN" >/dev/null); then
    echo "[FAIL] registry login should store hosted registry tokens"
    exit 1
fi

HOSTED_LIST_OUTPUT="$(
    cd "$HOSTED_BOOTSTRAP_DIR" && \
    XDG_CONFIG_HOME="$HOSTED_BOOTSTRAP_CONFIG" \
    "$MOG" registry list
)"
if [[ "$HOSTED_LIST_OUTPUT" != *"index = http://127.0.0.1:$HOSTED_PORT/index.toml"* ]] || \
   [[ "$HOSTED_LIST_OUTPUT" != *"trusted_key_ids = hosted-registry"* ]] || \
   [[ "$HOSTED_LIST_OUTPUT" != *"token = yes"* ]]; then
    echo "[FAIL] registry list should report stored registry trust and token state"
    echo "$HOSTED_LIST_OUTPUT"
    exit 1
fi

if ! (cd "$HOSTED_BOOTSTRAP_DIR" && \
    XDG_CONFIG_HOME="$HOSTED_BOOTSTRAP_CONFIG" \
    MOG_CACHE_DIR="$TEMP_DIR/hosted-bootstrap-cache" \
    "$MOG" install >/dev/null); then
    echo "[FAIL] registry trust/login should bootstrap hosted installs without project trusted_keys"
    exit 1
fi

if [[ "$(cd "$HOSTED_BOOTSTRAP_DIR" && "$MOG" run app.mog)" != *"utility from hosted registry"* ]]; then
    echo "[FAIL] bootstrap-installed hosted packages should execute normally"
    exit 1
fi

HOSTED_BOOTSTRAP_MISSING_KEY_DIR="$TEMP_DIR/hosted-bootstrap-missing-key"
mkdir -p "$HOSTED_BOOTSTRAP_MISSING_KEY_DIR"
cat > "$HOSTED_BOOTSTRAP_MISSING_KEY_DIR/mog.toml" <<EOF_HOSTED_BOOTSTRAP_MISSING_KEY
kind = "project"
name = "hosted-bootstrap-missing-key"
version = "0.1.0"
description = "hosted bootstrap missing key"

[registries.default]
index = "http://127.0.0.1:$HOSTED_PORT/missing/index.toml"
EOF_HOSTED_BOOTSTRAP_MISSING_KEY

if (cd "$HOSTED_BOOTSTRAP_MISSING_KEY_DIR" && \
    XDG_CONFIG_HOME="$TEMP_DIR/hosted-bootstrap-missing-key-config" \
    "$MOG" registry trust default --bootstrap \
    >/tmp/mog_hosted_bootstrap_missing_key_failure.txt 2>&1); then
    echo "[FAIL] registry trust --bootstrap should fail when registry-public-key.v1 is missing"
    cat /tmp/mog_hosted_bootstrap_missing_key_failure.txt
    exit 1
fi

if ! grep -Eq "registry-public-key.v1|404|bootstrap trust" \
    /tmp/mog_hosted_bootstrap_missing_key_failure.txt; then
    echo "[FAIL] missing hosted bootstrap key failure should mention the missing hosted key file"
    cat /tmp/mog_hosted_bootstrap_missing_key_failure.txt
    exit 1
fi

mkdir -p "$HOSTED_REGISTRY_DIR/bad-key"
cat > "$HOSTED_REGISTRY_DIR/bad-key/registry-public-key.v1" <<'EOF_BAD_HOSTED_KEY'
schema_version = "registry-public-key.v1"
key_id = "broken"
EOF_BAD_HOSTED_KEY

HOSTED_BOOTSTRAP_BAD_KEY_DIR="$TEMP_DIR/hosted-bootstrap-bad-key"
mkdir -p "$HOSTED_BOOTSTRAP_BAD_KEY_DIR"
cat > "$HOSTED_BOOTSTRAP_BAD_KEY_DIR/mog.toml" <<EOF_HOSTED_BOOTSTRAP_BAD_KEY
kind = "project"
name = "hosted-bootstrap-bad-key"
version = "0.1.0"
description = "hosted bootstrap bad key"

[registries.default]
index = "http://127.0.0.1:$HOSTED_PORT/bad-key/index.toml"
EOF_HOSTED_BOOTSTRAP_BAD_KEY

if (cd "$HOSTED_BOOTSTRAP_BAD_KEY_DIR" && \
    XDG_CONFIG_HOME="$TEMP_DIR/hosted-bootstrap-bad-key-config" \
    "$MOG" registry trust default --bootstrap \
    >/tmp/mog_hosted_bootstrap_bad_key_failure.txt 2>&1); then
    echo "[FAIL] registry trust --bootstrap should fail when the hosted public key file is malformed"
    cat /tmp/mog_hosted_bootstrap_bad_key_failure.txt
    exit 1
fi

if ! grep -Eq "public key|key_id|bootstrap trust" \
    /tmp/mog_hosted_bootstrap_bad_key_failure.txt; then
    echo "[FAIL] malformed hosted bootstrap key failure should explain the invalid public key file"
    cat /tmp/mog_hosted_bootstrap_bad_key_failure.txt
    exit 1
fi

HOSTED_ALIAS_REUSE_DIR="$TEMP_DIR/hosted-alias-reuse"
mkdir -p "$HOSTED_ALIAS_REUSE_DIR"
cat > "$HOSTED_ALIAS_REUSE_DIR/mog.toml" <<EOF_HOSTED_ALIAS
kind = "project"
name = "hosted-alias-reuse"
version = "0.1.0"
description = "hosted alias reuse"

[registries.internal]
index = "http://127.0.0.1:$HOSTED_PORT/index.toml"

[dependencies]
hosted_util = { package = "acme:hosted-util", version = "1.0.0", registry = "internal" }
EOF_HOSTED_ALIAS
cp "$HOSTED_CONSUMER_DIR/app.mog" "$HOSTED_ALIAS_REUSE_DIR/app.mog"

if ! (cd "$HOSTED_ALIAS_REUSE_DIR" && \
    XDG_CONFIG_HOME="$HOSTED_BOOTSTRAP_CONFIG" \
    MOG_CACHE_DIR="$TEMP_DIR/hosted-alias-cache" \
    "$MOG" install >/dev/null); then
    echo "[FAIL] stored hosted trust and tokens should be reused across aliases for the same registry URL"
    exit 1
fi

HOSTED_ALIAS_STATUS="$(
    cd "$HOSTED_ALIAS_REUSE_DIR" && \
    XDG_CONFIG_HOME="$HOSTED_BOOTSTRAP_CONFIG" \
    "$MOG" registry status internal
)"
if [[ "$HOSTED_ALIAS_STATUS" != *"trust = user"* ]] || \
   [[ "$HOSTED_ALIAS_STATUS" != *"token = yes"* ]]; then
    echo "[FAIL] registry status should reuse user-scoped trust and tokens across aliases"
    echo "$HOSTED_ALIAS_STATUS"
    exit 1
fi

if ! (cd "$HOSTED_ALIAS_REUSE_DIR" && \
    XDG_CONFIG_HOME="$HOSTED_BOOTSTRAP_CONFIG" \
    "$MOG" registry untrust internal --key-id hosted-registry >/dev/null); then
    echo "[FAIL] registry untrust should remove stored user trust"
    exit 1
fi

HOSTED_AFTER_UNTRUST_DIR="$TEMP_DIR/hosted-after-untrust"
mkdir -p "$HOSTED_AFTER_UNTRUST_DIR"
cp "$HOSTED_ALIAS_REUSE_DIR/mog.toml" "$HOSTED_AFTER_UNTRUST_DIR/mog.toml"
cp "$HOSTED_ALIAS_REUSE_DIR/app.mog" "$HOSTED_AFTER_UNTRUST_DIR/app.mog"

if (cd "$HOSTED_AFTER_UNTRUST_DIR" && \
    XDG_CONFIG_HOME="$HOSTED_BOOTSTRAP_CONFIG" \
    MOG_CACHE_DIR="$TEMP_DIR/hosted-after-untrust-cache" \
    "$MOG" install >/tmp/mog_hosted_after_untrust_failure.txt 2>&1); then
    echo "[FAIL] registry untrust should cause hosted installs to fail again when no project trust remains"
    cat /tmp/mog_hosted_after_untrust_failure.txt
    exit 1
fi

if ! grep -Eq "trusted_keys|unknown key|signed registry" /tmp/mog_hosted_after_untrust_failure.txt; then
    echo "[FAIL] hosted installs after untrust should explain the missing registry trust"
    cat /tmp/mog_hosted_after_untrust_failure.txt
    exit 1
fi

if ! (cd "$HOSTED_ALIAS_REUSE_DIR" && \
    XDG_CONFIG_HOME="$HOSTED_BOOTSTRAP_CONFIG" \
    "$MOG" registry trust internal --key-file "$HOSTED_KEY_FILE" >/dev/null); then
    echo "[FAIL] registry trust should also accept registry-key.v1 files"
    exit 1
fi

if ! (cd "$HOSTED_AFTER_UNTRUST_DIR" && \
    XDG_CONFIG_HOME="$HOSTED_BOOTSTRAP_CONFIG" \
    MOG_CACHE_DIR="$TEMP_DIR/hosted-restored-trust-cache" \
    "$MOG" install >/dev/null); then
    echo "[FAIL] restoring trust from registry-key.v1 should allow hosted installs again"
    exit 1
fi

HOSTED_ROTATED_KEY_FILE="$TEMP_DIR/hosted-rotated-key.toml"
ROTATION_REGISTRY_A="$TEMP_DIR/rotation-registry-a"
ROTATION_REGISTRY_B="$TEMP_DIR/rotation-registry-b"
ROTATION_PUBLISH_A="$TEMP_DIR/rotation-publish-a"
ROTATION_PUBLISH_B="$TEMP_DIR/rotation-publish-b"
ROTATION_HOSTED_B_DIR="$HOSTED_REGISTRY_DIR/rotation-b"
ROTATION_HOSTED_REVOKED_DIR="$HOSTED_REGISTRY_DIR/rotation-revoked-a"
create_signing_key "$HOSTED_ROTATED_KEY_FILE" "hosted-rotated"
HOSTED_ROTATED_TRUSTED_KEY="$(trusted_key_spec "$HOSTED_ROTATED_KEY_FILE")"

mkdir -p "$ROTATION_REGISTRY_A" "$ROTATION_REGISTRY_B"
mkdir -p "$ROTATION_PUBLISH_A/pkg/src" "$ROTATION_PUBLISH_B/pkg/src"

cat > "$ROTATION_PUBLISH_A/mog.toml" <<EOF_ROTATION_PUBLISH_A
kind = "project"
name = "rotation-publish-a"
version = "0.1.0"
description = "rotation publish a"

[registries.default]
index = "$ROTATION_REGISTRY_A/index.toml"
trusted_keys = ["$HOSTED_TRUSTED_KEY"]
EOF_ROTATION_PUBLISH_A

cat > "$ROTATION_PUBLISH_B/mog.toml" <<EOF_ROTATION_PUBLISH_B
kind = "project"
name = "rotation-publish-b"
version = "0.1.0"
description = "rotation publish b"

[registries.default]
index = "$ROTATION_REGISTRY_B/index.toml"
trusted_keys = ["$HOSTED_ROTATED_TRUSTED_KEY"]
EOF_ROTATION_PUBLISH_B

cat > "$ROTATION_PUBLISH_A/pkg/mog.toml" <<'EOF_ROTATION_PACKAGE'
kind = "source"
import_name = "rotation_util"
namespace = "acme"
name = "rotation-util"
version = "1.0.0"
license = "MIT"
author = "Rotation test"
description = "Rotation utility package."
entry = "src/main.mog"
dependencies = []
EOF_ROTATION_PACKAGE
cp "$ROTATION_PUBLISH_A/pkg/mog.toml" "$ROTATION_PUBLISH_B/pkg/mog.toml"

cat > "$ROTATION_PUBLISH_A/pkg/src/main.mog" <<'EOF_ROTATION_PACKAGE_SRC'
const MESSAGE str = "utility from rotated hosted registry"

fn Name() str {
    return MESSAGE
}
EOF_ROTATION_PACKAGE_SRC
cp "$ROTATION_PUBLISH_A/pkg/src/main.mog" "$ROTATION_PUBLISH_B/pkg/src/main.mog"

if ! (cd "$ROTATION_PUBLISH_A" && \
    "$MOG" publish --signing-key "$HOSTED_KEY_FILE" pkg >/dev/null); then
    echo "[FAIL] rotation test setup should publish a source package signed by the original key"
    exit 1
fi

if ! (cd "$ROTATION_PUBLISH_B" && \
    "$MOG" publish --signing-key "$HOSTED_ROTATED_KEY_FILE" pkg >/dev/null); then
    echo "[FAIL] rotation test setup should publish a source package signed by the rotated key"
    exit 1
fi

rm -rf "$ROTATION_HOSTED_B_DIR" "$ROTATION_HOSTED_REVOKED_DIR"
mkdir -p "$ROTATION_HOSTED_B_DIR" "$ROTATION_HOSTED_REVOKED_DIR"
cp -R "$ROTATION_REGISTRY_B"/. "$ROTATION_HOSTED_B_DIR/"
cp -R "$ROTATION_REGISTRY_A"/. "$ROTATION_HOSTED_REVOKED_DIR/"
create_public_key_file "$HOSTED_KEY_FILE" "$ROTATION_HOSTED_B_DIR/registry-public-key.v1"
create_public_key_file "$HOSTED_KEY_FILE" "$ROTATION_HOSTED_REVOKED_DIR/registry-public-key.v1"
write_signed_registry_trust \
    "$ROTATION_HOSTED_B_DIR/registry-trust.v1" \
    "$HOSTED_KEY_FILE" \
    "$HOSTED_ROTATED_KEY_FILE" \
    "$HOSTED_KEY_FILE" \
    "rotated to hosted-rotated"
write_signed_registry_trust \
    "$ROTATION_HOSTED_REVOKED_DIR/registry-trust.v1" \
    "$HOSTED_KEY_FILE" \
    "$HOSTED_ROTATED_KEY_FILE" \
    "$HOSTED_KEY_FILE" \
    "hosted-registry revoked"

ROTATION_AUTO_DIR="$TEMP_DIR/rotation-auto"
ROTATION_OFFLINE_DIR="$TEMP_DIR/rotation-offline"
ROTATION_REVOKED_DIR="$TEMP_DIR/rotation-revoked"
ROTATION_REFRESH_DIR="$TEMP_DIR/rotation-refresh"
ROTATION_REFRESH_USER_DIR="$TEMP_DIR/rotation-refresh-user"
ROTATION_REFRESH_CONFIG="$TEMP_DIR/rotation-refresh-config"
ROTATION_CACHE_DIR="$TEMP_DIR/rotation-cache"
ROTATION_NO_METADATA_DIR="$TEMP_DIR/rotation-no-metadata"
mkdir -p "$ROTATION_AUTO_DIR" "$ROTATION_OFFLINE_DIR" "$ROTATION_REVOKED_DIR" \
    "$ROTATION_REFRESH_DIR" "$ROTATION_REFRESH_USER_DIR" "$ROTATION_NO_METADATA_DIR"

cat > "$ROTATION_AUTO_DIR/mog.toml" <<EOF_ROTATION_AUTO
kind = "project"
name = "rotation-auto"
version = "0.1.0"
description = "rotation auto"

[registries.default]
index = "http://127.0.0.1:$HOSTED_PORT/rotation-b/index.toml"
trusted_keys = ["$HOSTED_TRUSTED_KEY"]

[dependencies]
rotation_util = { package = "acme:rotation-util", version = "1.0.0" }
EOF_ROTATION_AUTO
cp "$ROTATION_AUTO_DIR/mog.toml" "$ROTATION_OFFLINE_DIR/mog.toml"

cat > "$ROTATION_AUTO_DIR/app.mog" <<'EOF_ROTATION_APP'
const rotation_util = @import("rotation_util")
print(rotation_util.Name())
EOF_ROTATION_APP
cp "$ROTATION_AUTO_DIR/app.mog" "$ROTATION_OFFLINE_DIR/app.mog"

if ! (cd "$ROTATION_AUTO_DIR" && \
    MOG_CACHE_DIR="$ROTATION_CACHE_DIR" \
    MOG_REGISTRY_TOKEN="$HOSTED_TOKEN" \
    "$MOG" install >/dev/null); then
    echo "[FAIL] hosted installs should automatically apply signed trust metadata for rotated keys"
    exit 1
fi

if [[ "$(cd "$ROTATION_AUTO_DIR" && "$MOG" run app.mog)" != *"utility from rotated hosted registry"* ]]; then
    echo "[FAIL] rotated hosted packages should execute normally after automatic trust metadata application"
    exit 1
fi

if ! (cd "$ROTATION_OFFLINE_DIR" && \
    MOG_CACHE_DIR="$ROTATION_CACHE_DIR" \
    "$MOG" install --offline >/dev/null); then
    echo "[FAIL] offline hosted installs should reuse cached registry trust metadata"
    exit 1
fi

cat > "$ROTATION_REVOKED_DIR/mog.toml" <<EOF_ROTATION_REVOKED
kind = "project"
name = "rotation-revoked"
version = "0.1.0"
description = "rotation revoked"

[registries.default]
index = "http://127.0.0.1:$HOSTED_PORT/rotation-revoked-a/index.toml"
trusted_keys = ["$HOSTED_TRUSTED_KEY"]

[dependencies]
rotation_util = { package = "acme:rotation-util", version = "1.0.0" }
EOF_ROTATION_REVOKED
cp "$ROTATION_AUTO_DIR/app.mog" "$ROTATION_REVOKED_DIR/app.mog"

if (cd "$ROTATION_REVOKED_DIR" && \
    MOG_CACHE_DIR="$TEMP_DIR/rotation-revoked-cache" \
    MOG_REGISTRY_TOKEN="$HOSTED_TOKEN" \
    "$MOG" install >/tmp/mog_rotation_revoked_failure.txt 2>&1); then
    echo "[FAIL] registry installs should reject indexes signed by revoked keys"
    cat /tmp/mog_rotation_revoked_failure.txt
    exit 1
fi

if ! grep -Eq "revoked key|unknown key" /tmp/mog_rotation_revoked_failure.txt; then
    echo "[FAIL] revoked-key install failures should explain the rejected signing key"
    cat /tmp/mog_rotation_revoked_failure.txt
    exit 1
fi

cat > "$ROTATION_NO_METADATA_DIR/mog.toml" <<EOF_ROTATION_NO_METADATA
kind = "project"
name = "rotation-no-metadata"
version = "0.1.0"
description = "rotation no metadata"

[registries.default]
index = "http://127.0.0.1:$HOSTED_PORT/index.toml"
trusted_keys = ["$HOSTED_TRUSTED_KEY"]
EOF_ROTATION_NO_METADATA

if (cd "$ROTATION_NO_METADATA_DIR" && \
    XDG_CONFIG_HOME="$ROTATION_REFRESH_CONFIG" \
    "$MOG" registry trust default --refresh \
    >/tmp/mog_rotation_refresh_missing_failure.txt 2>&1); then
    echo "[FAIL] registry trust --refresh should fail when registry-trust.v1 is missing"
    cat /tmp/mog_rotation_refresh_missing_failure.txt
    exit 1
fi

if ! grep -Eq "registry-trust.v1|trust refresh" \
    /tmp/mog_rotation_refresh_missing_failure.txt; then
    echo "[FAIL] missing trust metadata failures should mention registry-trust.v1"
    cat /tmp/mog_rotation_refresh_missing_failure.txt
    exit 1
fi

cat > "$ROTATION_REFRESH_DIR/mog.toml" <<EOF_ROTATION_REFRESH
kind = "project"
name = "rotation-refresh"
version = "0.1.0"
description = "rotation refresh"

[registries.default]
index = "http://127.0.0.1:$HOSTED_PORT/rotation-b/index.toml"
trusted_keys = ["$HOSTED_TRUSTED_KEY"]
EOF_ROTATION_REFRESH

ROTATION_REFRESH_OUTPUT="$(
    cd "$ROTATION_REFRESH_DIR" && \
    XDG_CONFIG_HOME="$ROTATION_REFRESH_CONFIG" \
    "$MOG" registry trust default --refresh
)"
if [[ "$ROTATION_REFRESH_OUTPUT" != *"trusted_key_ids = hosted-rotated"* ]] || \
   [[ "$ROTATION_REFRESH_OUTPUT" != *"revoked_key_ids = hosted-registry"* ]]; then
    echo "[FAIL] registry trust --refresh should report the active and revoked key IDs"
    echo "$ROTATION_REFRESH_OUTPUT"
    exit 1
fi

if ! grep -Fq 'hosted-rotated' "$ROTATION_REFRESH_CONFIG/mog/registries.toml" || \
   grep -Fq 'hosted-registry' "$ROTATION_REFRESH_CONFIG/mog/registries.toml"; then
    echo "[FAIL] registry trust --refresh should rewrite stored user trust to the active key set"
    cat "$ROTATION_REFRESH_CONFIG/mog/registries.toml"
    exit 1
fi

write_signed_registry_trust \
    "$ROTATION_HOSTED_B_DIR/registry-trust.v1" \
    "$HOSTED_ROTATED_KEY_FILE" \
    "$HOSTED_ROTATED_KEY_FILE" \
    "$HOSTED_KEY_FILE" \
    "rotated to hosted-rotated"

cat > "$ROTATION_REFRESH_USER_DIR/mog.toml" <<EOF_ROTATION_REFRESH_USER
kind = "project"
name = "rotation-refresh-user"
version = "0.1.0"
description = "rotation refresh user"

[registries.default]
index = "http://127.0.0.1:$HOSTED_PORT/rotation-b/index.toml"

[dependencies]
rotation_util = { package = "acme:rotation-util", version = "1.0.0" }
EOF_ROTATION_REFRESH_USER
cp "$ROTATION_AUTO_DIR/app.mog" "$ROTATION_REFRESH_USER_DIR/app.mog"

if ! (cd "$ROTATION_REFRESH_USER_DIR" && \
    XDG_CONFIG_HOME="$ROTATION_REFRESH_CONFIG" \
    MOG_CACHE_DIR="$TEMP_DIR/rotation-refresh-user-cache" \
    MOG_REGISTRY_TOKEN="$HOSTED_TOKEN" \
    "$MOG" install >/dev/null); then
    echo "[FAIL] refreshed user trust should allow hosted installs without project trusted_keys"
    exit 1
fi

ROTATION_REFRESH_STATUS="$(
    cd "$ROTATION_REFRESH_USER_DIR" && \
    XDG_CONFIG_HOME="$ROTATION_REFRESH_CONFIG" \
    "$MOG" registry status default
)"
if [[ "$ROTATION_REFRESH_STATUS" != *"trust = user"* ]] || \
   [[ "$ROTATION_REFRESH_STATUS" != *"trusted_key_ids = hosted-rotated"* ]]; then
    echo "[FAIL] registry status should report the refreshed user trust"
    echo "$ROTATION_REFRESH_STATUS"
    exit 1
fi

if ! (cd "$HOSTED_PUBLISH_WORKSPACE" && \
    XDG_CONFIG_HOME="$HOSTED_PUBLISH_CONFIG" \
    "$MOG" logout default >/dev/null); then
    echo "[FAIL] logout should clear a hosted registry token"
    exit 1
fi

HOSTED_UNAUTH_DIR="$TEMP_DIR/hosted-unauth"
mkdir -p "$HOSTED_UNAUTH_DIR"
cp "$HOSTED_CONSUMER_DIR/mog.toml" "$HOSTED_UNAUTH_DIR/mog.toml"
cp "$HOSTED_CONSUMER_DIR/app.mog" "$HOSTED_UNAUTH_DIR/app.mog"
if (cd "$HOSTED_UNAUTH_DIR" && \
    XDG_CONFIG_HOME="$TEMP_DIR/hosted-empty-config" \
    MOG_CACHE_DIR="$TEMP_DIR/hosted-empty-cache" \
    "$MOG" install >/tmp/mog_hosted_auth_failure.txt 2>&1); then
    echo "[FAIL] install should reject hosted registry downloads without credentials"
    cat /tmp/mog_hosted_auth_failure.txt
    exit 1
fi

if ! grep -Eq "401|download failed|unauthorized" /tmp/mog_hosted_auth_failure.txt; then
    echo "[FAIL] install should surface hosted registry auth failures"
    cat /tmp/mog_hosted_auth_failure.txt
    exit 1
fi

HOSTED_SIGNED_INDEX_BACKUP="$TEMP_DIR/hosted-signed-index.toml"
cp "$HOSTED_REGISTRY_DIR/index.toml" "$HOSTED_SIGNED_INDEX_BACKUP"
strip_registry_index_signature "$HOSTED_REGISTRY_DIR"

HOSTED_INSECURE_DIR="$TEMP_DIR/hosted-insecure"
mkdir -p "$HOSTED_INSECURE_DIR"
cat > "$HOSTED_INSECURE_DIR/mog.toml" <<EOF_HOSTED_INSECURE
kind = "project"
name = "hosted-insecure"
version = "0.1.0"
description = "hosted insecure"

[registries.default]
index = "http://127.0.0.1:$HOSTED_PORT/index.toml"
allow_insecure = true

[dependencies]
hosted_util = { package = "acme:hosted-util", version = "1.0.0" }
EOF_HOSTED_INSECURE
cp "$HOSTED_CONSUMER_DIR/app.mog" "$HOSTED_INSECURE_DIR/app.mog"

if ! (cd "$HOSTED_INSECURE_DIR" && \
    XDG_CONFIG_HOME="$TEMP_DIR/xdg-config" \
    "$MOG" login default --token "$HOSTED_TOKEN" >/dev/null && \
    XDG_CONFIG_HOME="$TEMP_DIR/xdg-config" \
    MOG_CACHE_DIR="$TEMP_DIR/hosted-insecure-cache" \
    "$MOG" install >/dev/null); then
    echo "[FAIL] allow_insecure should permit unsigned hosted registry installs"
    exit 1
fi

HOSTED_INSECURE_OUTPUT="$("$MOG" run "$HOSTED_INSECURE_DIR/app.mog")"
if [[ "$HOSTED_INSECURE_OUTPUT" != *"utility from hosted registry"* ]]; then
    echo "[FAIL] allow_insecure hosted install should still run downloaded packages"
    echo "$HOSTED_INSECURE_OUTPUT"
    exit 1
fi

cp "$HOSTED_SIGNED_INDEX_BACKUP" "$HOSTED_REGISTRY_DIR/index.toml"

rm -f "$HOSTED_REGISTRY_DIR/registry-service.v1"
mkdir -p "$HOSTED_PUBLISH_WORKSPACE/legacy-pkg/src"
cat > "$HOSTED_PUBLISH_WORKSPACE/legacy-pkg/mog.toml" <<'EOF_HOSTED_LEGACY_PACKAGE'
kind = "source"
import_name = "legacy_util"
namespace = "acme"
name = "legacy-util"
version = "1.0.0"
license = "MIT"
author = "Hosted registry legacy test"
description = "Legacy hosted utility package."
entry = "src/main.mog"
dependencies = []
EOF_HOSTED_LEGACY_PACKAGE

cat > "$HOSTED_PUBLISH_WORKSPACE/legacy-pkg/src/main.mog" <<'EOF_HOSTED_LEGACY_SRC'
const MESSAGE str = "utility from legacy hosted registry"

fn Name() str {
    return MESSAGE
}
EOF_HOSTED_LEGACY_SRC

if ! (cd "$HOSTED_PUBLISH_WORKSPACE" && \
    XDG_CONFIG_HOME="$HOSTED_PUBLISH_CONFIG" \
    "$MOG" login default --token "$HOSTED_TOKEN" >/dev/null && \
    "$MOG" publish --signing-key "$HOSTED_KEY_FILE" legacy-pkg >/dev/null); then
    echo "[FAIL] hosted publish should fall back to the legacy transport when registry-service.v1 is absent"
    exit 1
fi

if ! grep -Fq 'artifact_path = "packages/acme/legacy-util/1.0.0"' \
    "$HOSTED_REGISTRY_DIR/index.toml"; then
    echo "[FAIL] legacy hosted publish should keep the classic package path layout"
    cat "$HOSTED_REGISTRY_DIR/index.toml"
    exit 1
fi

HOSTED_LEGACY_CONSUMER_DIR="$TEMP_DIR/hosted-legacy-consumer"
mkdir -p "$HOSTED_LEGACY_CONSUMER_DIR"
cat > "$HOSTED_LEGACY_CONSUMER_DIR/mog.toml" <<EOF_HOSTED_LEGACY_CONSUMER
kind = "project"
name = "hosted-legacy-consumer"
version = "0.1.0"
description = "hosted legacy consumer"

[registries.default]
index = "http://127.0.0.1:$HOSTED_PORT/index.toml"
trusted_keys = ["$HOSTED_TRUSTED_KEY"]

[dependencies]
legacy_util = { package = "acme:legacy-util", version = "1.0.0" }
EOF_HOSTED_LEGACY_CONSUMER

cat > "$HOSTED_LEGACY_CONSUMER_DIR/app.mog" <<'EOF_HOSTED_LEGACY_APP'
const legacy_util = @import("legacy_util")
print(legacy_util.Name())
EOF_HOSTED_LEGACY_APP

if ! (cd "$HOSTED_LEGACY_CONSUMER_DIR" && \
    XDG_CONFIG_HOME="$HOSTED_PUBLISH_CONFIG" \
    "$MOG" install >/dev/null); then
    echo "[FAIL] legacy hosted fallback should still produce installable packages"
    exit 1
fi

if [[ "$(cd "$HOSTED_LEGACY_CONSUMER_DIR" && "$MOG" run app.mog)" != *"utility from legacy hosted registry"* ]]; then
    echo "[FAIL] legacy hosted fallback packages should execute normally"
    exit 1
fi

AUDIT_ROOT="$TEMP_DIR/audit-root"
AUDIT_REGISTRY_DIR="$AUDIT_ROOT/registry"
AUDIT_PUBLISH_WORKSPACE="$AUDIT_ROOT/publish"
AUDIT_CONSUMER_DIR="$AUDIT_ROOT/consumer"
AUDIT_KEY_FILE="$AUDIT_ROOT/audit-registry-key.toml"
mkdir -p "$AUDIT_PUBLISH_WORKSPACE/pkg/src" "$AUDIT_CONSUMER_DIR"
mkdir -p "$AUDIT_REGISTRY_DIR"
create_signing_key "$AUDIT_KEY_FILE" "audit-registry"
AUDIT_TRUSTED_KEY="$(trusted_key_spec "$AUDIT_KEY_FILE")"

cat > "$AUDIT_PUBLISH_WORKSPACE/mog.toml" <<EOF_AUDIT_PUBLISH_ROOT
kind = "project"
name = "audit-publish-root"
version = "0.1.0"
description = "audit publish root"

[registries.default]
index = "$AUDIT_REGISTRY_DIR/index.toml"
trusted_keys = ["$AUDIT_TRUSTED_KEY"]
EOF_AUDIT_PUBLISH_ROOT

cat > "$AUDIT_PUBLISH_WORKSPACE/pkg/mog.toml" <<'EOF_AUDIT_PACKAGE'
kind = "source"
import_name = "audit_util"
namespace = "acme"
name = "audit-util"
version = "1.0.0"
license = "MIT"
author = "Audit registry test"
description = "Audit utility package."
entry = "src/main.mog"
dependencies = []
EOF_AUDIT_PACKAGE

cat > "$AUDIT_PUBLISH_WORKSPACE/pkg/src/main.mog" <<'EOF_AUDIT_PACKAGE_SRC'
const MESSAGE str = "utility from audit registry"

fn Name() str {
    return MESSAGE
}
EOF_AUDIT_PACKAGE_SRC

if ! (cd "$AUDIT_PUBLISH_WORKSPACE" && \
    "$MOG" publish --signing-key "$AUDIT_KEY_FILE" pkg >/dev/null); then
    echo "[FAIL] signed local registry publish should succeed for audit tests"
    exit 1
fi

PUBLISH_GIT_SOURCE_CLEAN="$TEMP_DIR/publish-git-source-clean"
mkdir -p "$PUBLISH_GIT_SOURCE_CLEAN/pkg/src"
cat > "$PUBLISH_GIT_SOURCE_CLEAN/mog.toml" <<EOF_PUBLISH_GIT_SOURCE_ROOT
kind = "project"
name = "publish-git-source-root"
version = "0.1.0"
description = "git publish source root"

[registries.default]
index = "$AUDIT_REGISTRY_DIR/index.toml"
trusted_keys = ["$AUDIT_TRUSTED_KEY"]
EOF_PUBLISH_GIT_SOURCE_ROOT

cat > "$PUBLISH_GIT_SOURCE_CLEAN/pkg/mog.toml" <<'EOF_PUBLISH_GIT_SOURCE_PACKAGE'
kind = "source"
import_name = "publish_git_source"
namespace = "acme"
name = "git-source-publish"
version = "1.2.3"
license = "MIT"
author = "Publish git test"
description = "Git-guarded source publish package."
entry = "src/main.mog"
dependencies = []
EOF_PUBLISH_GIT_SOURCE_PACKAGE

cat > "$PUBLISH_GIT_SOURCE_CLEAN/pkg/src/main.mog" <<'EOF_PUBLISH_GIT_SOURCE_SRC'
const MESSAGE str = "publish source"

fn Name() str {
    return MESSAGE
}
EOF_PUBLISH_GIT_SOURCE_SRC

git -C "$PUBLISH_GIT_SOURCE_CLEAN" init --initial-branch=main >/dev/null
git -C "$PUBLISH_GIT_SOURCE_CLEAN" config user.email "mog-tests@example.com"
git -C "$PUBLISH_GIT_SOURCE_CLEAN" config user.name "Mog Tests"
git -C "$PUBLISH_GIT_SOURCE_CLEAN" add . >/dev/null
git -C "$PUBLISH_GIT_SOURCE_CLEAN" commit -m "init" >/dev/null
git -C "$PUBLISH_GIT_SOURCE_CLEAN" tag v1.2.3

PUBLISH_GIT_SOURCE_SUCCESS="$TEMP_DIR/publish-git-source-success"
cp -R "$PUBLISH_GIT_SOURCE_CLEAN" "$PUBLISH_GIT_SOURCE_SUCCESS"
printf '%s\n' "unrelated dirty file" > "$PUBLISH_GIT_SOURCE_SUCCESS/outside.txt"

if ! (cd "$PUBLISH_GIT_SOURCE_SUCCESS" && \
    "$MOG" publish --signing-key "$AUDIT_KEY_FILE" \
      --require-clean-git --tag v1.2.3 pkg >/dev/null); then
    echo "[FAIL] publish --require-clean-git should ignore unrelated dirty files outside the package directory"
    exit 1
fi

PUBLISH_GIT_SOURCE_TRACKED_DIRTY="$TEMP_DIR/publish-git-source-tracked-dirty"
cp -R "$PUBLISH_GIT_SOURCE_CLEAN" "$PUBLISH_GIT_SOURCE_TRACKED_DIRTY"
printf '\nconst EXTRA str = "dirty tracked change"\n' >> \
    "$PUBLISH_GIT_SOURCE_TRACKED_DIRTY/pkg/src/main.mog"

if (cd "$PUBLISH_GIT_SOURCE_TRACKED_DIRTY" && \
    "$MOG" publish --signing-key "$AUDIT_KEY_FILE" \
      --require-clean-git --tag v1.2.3 pkg \
      >/tmp/mog_publish_clean_git_tracked_failure.txt 2>&1); then
    echo "[FAIL] publish --require-clean-git should reject tracked changes under the package directory"
    cat /tmp/mog_publish_clean_git_tracked_failure.txt
    exit 1
fi

if ! grep -Fq "clean git tree" /tmp/mog_publish_clean_git_tracked_failure.txt; then
    echo "[FAIL] tracked publish clean-tree failures should mention the clean git requirement"
    cat /tmp/mog_publish_clean_git_tracked_failure.txt
    exit 1
fi

PUBLISH_GIT_SOURCE_UNTRACKED_DIRTY="$TEMP_DIR/publish-git-source-untracked-dirty"
cp -R "$PUBLISH_GIT_SOURCE_CLEAN" "$PUBLISH_GIT_SOURCE_UNTRACKED_DIRTY"
printf '%s\n' "untracked package file" > \
    "$PUBLISH_GIT_SOURCE_UNTRACKED_DIRTY/pkg/UNTRACKED.txt"

if (cd "$PUBLISH_GIT_SOURCE_UNTRACKED_DIRTY" && \
    "$MOG" publish --signing-key "$AUDIT_KEY_FILE" \
      --require-clean-git --tag v1.2.3 pkg \
      >/tmp/mog_publish_clean_git_untracked_failure.txt 2>&1); then
    echo "[FAIL] publish --require-clean-git should reject untracked files under the package directory"
    cat /tmp/mog_publish_clean_git_untracked_failure.txt
    exit 1
fi

if ! grep -Fq "clean git tree" /tmp/mog_publish_clean_git_untracked_failure.txt; then
    echo "[FAIL] untracked publish clean-tree failures should mention the clean git requirement"
    cat /tmp/mog_publish_clean_git_untracked_failure.txt
    exit 1
fi

PUBLISH_GIT_SOURCE_MISSING_TAG="$TEMP_DIR/publish-git-source-missing-tag"
cp -R "$PUBLISH_GIT_SOURCE_CLEAN" "$PUBLISH_GIT_SOURCE_MISSING_TAG"

if (cd "$PUBLISH_GIT_SOURCE_MISSING_TAG" && \
    "$MOG" publish --signing-key "$AUDIT_KEY_FILE" \
      --tag missing-tag pkg \
      >/tmp/mog_publish_missing_tag_failure.txt 2>&1); then
    echo "[FAIL] publish --tag should reject missing git tags"
    cat /tmp/mog_publish_missing_tag_failure.txt
    exit 1
fi

if ! grep -Fq "Could not resolve git tag 'missing-tag'" \
    /tmp/mog_publish_missing_tag_failure.txt; then
    echo "[FAIL] missing publish tag failures should mention the unresolved tag"
    cat /tmp/mog_publish_missing_tag_failure.txt
    exit 1
fi

PUBLISH_GIT_SOURCE_VERSION_MISMATCH="$TEMP_DIR/publish-git-source-version-mismatch"
cp -R "$PUBLISH_GIT_SOURCE_CLEAN" "$PUBLISH_GIT_SOURCE_VERSION_MISMATCH"
git -C "$PUBLISH_GIT_SOURCE_VERSION_MISMATCH" tag v9.9.9

if (cd "$PUBLISH_GIT_SOURCE_VERSION_MISMATCH" && \
    "$MOG" publish --signing-key "$AUDIT_KEY_FILE" \
      --tag v9.9.9 pkg \
      >/tmp/mog_publish_tag_version_failure.txt 2>&1); then
    echo "[FAIL] publish --tag should reject tags that do not match the manifest version"
    cat /tmp/mog_publish_tag_version_failure.txt
    exit 1
fi

if ! grep -Fq "match manifest version" /tmp/mog_publish_tag_version_failure.txt; then
    echo "[FAIL] publish tag/version mismatch failures should mention the manifest version"
    cat /tmp/mog_publish_tag_version_failure.txt
    exit 1
fi

PUBLISH_GIT_SOURCE_STALE_TAG="$TEMP_DIR/publish-git-source-stale-tag"
cp -R "$PUBLISH_GIT_SOURCE_CLEAN" "$PUBLISH_GIT_SOURCE_STALE_TAG"
printf '%s\n' "head moved" > "$PUBLISH_GIT_SOURCE_STALE_TAG/commit-after-tag.txt"
git -C "$PUBLISH_GIT_SOURCE_STALE_TAG" add commit-after-tag.txt >/dev/null
git -C "$PUBLISH_GIT_SOURCE_STALE_TAG" commit -m "move head" >/dev/null

if (cd "$PUBLISH_GIT_SOURCE_STALE_TAG" && \
    "$MOG" publish --signing-key "$AUDIT_KEY_FILE" \
      --tag v1.2.3 pkg \
      >/tmp/mog_publish_stale_tag_failure.txt 2>&1); then
    echo "[FAIL] publish --tag should reject tags that are not at HEAD"
    cat /tmp/mog_publish_stale_tag_failure.txt
    exit 1
fi

if ! grep -Fq "to point at HEAD" /tmp/mog_publish_stale_tag_failure.txt; then
    echo "[FAIL] stale publish tag failures should mention the HEAD requirement"
    cat /tmp/mog_publish_stale_tag_failure.txt
    exit 1
fi

COUNTER_PUBLISH_LIBRARY=""
if [[ -f "$PROJECT_ROOT/build/packages/examples/counter/package.so" ]]; then
    COUNTER_PUBLISH_LIBRARY="$PROJECT_ROOT/build/packages/examples/counter/package.so"
elif [[ -f "$PROJECT_ROOT/build/packages/examples/counter/package.dylib" ]]; then
    COUNTER_PUBLISH_LIBRARY="$PROJECT_ROOT/build/packages/examples/counter/package.dylib"
fi

if [[ -z "$COUNTER_PUBLISH_LIBRARY" ]]; then
    echo "[FAIL] native publish git tests require a built counter package library"
    exit 1
fi

PUBLISH_GIT_NATIVE="$TEMP_DIR/publish-git-native"
PUBLISH_GIT_NATIVE_REGISTRY="$TEMP_DIR/publish-git-native-registry"
mkdir -p "$PUBLISH_GIT_NATIVE_REGISTRY"
mkdir -p "$PUBLISH_GIT_NATIVE/examples/counter"
cat > "$PUBLISH_GIT_NATIVE/mog.toml" <<EOF_PUBLISH_GIT_NATIVE_ROOT
kind = "project"
name = "publish-git-native-root"
version = "0.1.0"
description = "git publish native root"

[registries.default]
index = "$PUBLISH_GIT_NATIVE_REGISTRY/index.toml"
trusted_keys = ["$AUDIT_TRUSTED_KEY"]
EOF_PUBLISH_GIT_NATIVE_ROOT

cp "$PROJECT_ROOT/packages/examples/counter/mog.toml" \
    "$PUBLISH_GIT_NATIVE/examples/counter/mog.toml"
cp "$PROJECT_ROOT/packages/examples/counter/package.api.mog" \
    "$PUBLISH_GIT_NATIVE/examples/counter/package.api.mog"
cp "$COUNTER_PUBLISH_LIBRARY" \
    "$PUBLISH_GIT_NATIVE/examples/counter/$(basename "$COUNTER_PUBLISH_LIBRARY")"

git -C "$PUBLISH_GIT_NATIVE" init --initial-branch=main >/dev/null
git -C "$PUBLISH_GIT_NATIVE" config user.email "mog-tests@example.com"
git -C "$PUBLISH_GIT_NATIVE" config user.name "Mog Tests"
git -C "$PUBLISH_GIT_NATIVE" add . >/dev/null
git -C "$PUBLISH_GIT_NATIVE" commit -m "init" >/dev/null
git -C "$PUBLISH_GIT_NATIVE" tag v0.1.0

if ! (cd "$PUBLISH_GIT_NATIVE" && \
    "$MOG" publish --signing-key "$AUDIT_KEY_FILE" \
      --require-clean-git --tag v0.1.0 \
      --target "$HOST_TARGET" \
      --native-artifact-dir examples/counter \
      examples/counter >/dev/null); then
    echo "[FAIL] native publish should support git preflight checks with --target and --native-artifact-dir"
    exit 1
fi

cat > "$AUDIT_CONSUMER_DIR/mog.toml" <<EOF_AUDIT_CONSUMER
kind = "project"
name = "audit-consumer"
version = "0.1.0"
description = "audit consumer"

[registries.default]
index = "$AUDIT_REGISTRY_DIR/index.toml"
trusted_keys = ["$AUDIT_TRUSTED_KEY"]

[dependencies]
audit_util = { package = "acme:audit-util", version = "1.0.0" }
EOF_AUDIT_CONSUMER

cat > "$AUDIT_CONSUMER_DIR/app.mog" <<'EOF_AUDIT_APP'
const audit_util = @import("audit_util")
print(audit_util.Name())
EOF_AUDIT_APP

if ! (cd "$AUDIT_CONSUMER_DIR" && "$MOG" install >/dev/null); then
    echo "[FAIL] signed local registry install should succeed for audit tests"
    exit 1
fi

if ! grep -Fq 'schema_version = "registry.v4"' "$AUDIT_REGISTRY_DIR/index.toml" || \
   ! grep -Fq 'artifact_signature = "' "$AUDIT_REGISTRY_DIR/index.toml"; then
    echo "[FAIL] signed publish should emit registry.v4 artifact signatures"
    cat "$AUDIT_REGISTRY_DIR/index.toml"
    exit 1
fi

if ! grep -Fq 'artifact_signature = "' "$AUDIT_CONSUMER_DIR/mog.lock" || \
   ! grep -Fq 'artifact_signature = "' "$AUDIT_CONSUMER_DIR/.mog/install/registry.toml"; then
    echo "[FAIL] signed registry installs should pin artifact signatures in lock/install metadata"
    cat "$AUDIT_CONSUMER_DIR/mog.lock"
    cat "$AUDIT_CONSUMER_DIR/.mog/install/registry.toml"
    exit 1
fi

POLICY_SIGNED_DIR="$TEMP_DIR/policy-signed"
mkdir -p "$POLICY_SIGNED_DIR"
cat > "$POLICY_SIGNED_DIR/mog.toml" <<EOF_POLICY_SIGNED
kind = "project"
name = "policy-signed-test"
version = "0.1.0"
description = "policy signed test"

[policy]
require_signed_artifacts = true

[registries.default]
index = "$REGISTRY_DIR"

[dependencies]
http = { package = "acme:http", version = "1.0.0" }
EOF_POLICY_SIGNED

if (cd "$POLICY_SIGNED_DIR" && "$MOG" install >/tmp/mog_policy_signed_failure.txt 2>&1); then
    echo "[FAIL] signed-artifact policy should reject unsigned registry packages"
    cat /tmp/mog_policy_signed_failure.txt
    exit 1
fi

if ! grep -Fq "requires signed artifacts" /tmp/mog_policy_signed_failure.txt; then
    echo "[FAIL] signed-artifact policy failures should mention signed artifacts"
    cat /tmp/mog_policy_signed_failure.txt
    exit 1
fi

POLICY_SIGNED_OK_DIR="$TEMP_DIR/policy-signed-ok"
mkdir -p "$POLICY_SIGNED_OK_DIR"
cat > "$POLICY_SIGNED_OK_DIR/mog.toml" <<EOF_POLICY_SIGNED_OK
kind = "project"
name = "policy-signed-ok"
version = "0.1.0"
description = "policy signed ok"

[policy]
require_signed_artifacts = true

[registries.default]
index = "$AUDIT_REGISTRY_DIR/index.toml"
trusted_keys = ["$AUDIT_TRUSTED_KEY"]

[dependencies]
audit_util = { package = "acme:audit-util", version = "1.0.0" }
EOF_POLICY_SIGNED_OK

cat > "$POLICY_SIGNED_OK_DIR/app.mog" <<'EOF_POLICY_SIGNED_OK_APP'
const audit_util = @import("audit_util")
print(audit_util.Name())
EOF_POLICY_SIGNED_OK_APP

if ! (cd "$POLICY_SIGNED_OK_DIR" && "$MOG" install >/dev/null); then
    echo "[FAIL] signed-artifact policy should allow signed source packages"
    exit 1
fi

if [[ "$(cd "$POLICY_SIGNED_OK_DIR" && "$MOG" run app.mog)" != *"utility from audit registry"* ]]; then
    echo "[FAIL] signed-artifact policy should still run signed source packages"
    exit 1
fi

if ! (cd "$AUDIT_PUBLISH_WORKSPACE" && \
    "$MOG" publish --signing-key "$AUDIT_KEY_FILE" \
      "$NATIVE_PUBLISH_WORKSPACE/packages/examples/counter" >/dev/null); then
    echo "[FAIL] signed local registry publish should support native packages"
    exit 1
fi

POLICY_SIGNED_NATIVE_DIR="$TEMP_DIR/policy-signed-native"
mkdir -p "$POLICY_SIGNED_NATIVE_DIR"
cat > "$POLICY_SIGNED_NATIVE_DIR/mog.toml" <<EOF_POLICY_SIGNED_NATIVE
kind = "project"
name = "policy-signed-native"
version = "0.1.0"
description = "policy signed native"

[policy]
require_signed_artifacts = true

[registries.default]
index = "$AUDIT_REGISTRY_DIR/index.toml"
trusted_keys = ["$AUDIT_TRUSTED_KEY"]

[dependencies]
counter = { package = "examples:counter", version = "0.1.0" }
EOF_POLICY_SIGNED_NATIVE

cat > "$POLICY_SIGNED_NATIVE_DIR/app.mog" <<'EOF_POLICY_SIGNED_NATIVE_APP'
const counter = @import("counter")

const value = counter.create(10i64)
print(counter.add(value, 5i64))
EOF_POLICY_SIGNED_NATIVE_APP

if ! (cd "$POLICY_SIGNED_NATIVE_DIR" && "$MOG" install >/dev/null); then
    echo "[FAIL] signed-artifact policy should allow signed native packages"
    exit 1
fi

if [[ "$(cd "$POLICY_SIGNED_NATIVE_DIR" && "$MOG" run app.mog)" != *"15"* ]]; then
    echo "[FAIL] signed-artifact policy should still run signed native packages"
    exit 1
fi

AUDIT_TAMPER_DIR="$AUDIT_ROOT/tamper"
rm -rf "$AUDIT_TAMPER_DIR"
cp -R "$AUDIT_CONSUMER_DIR" "$AUDIT_TAMPER_DIR"
python3 - "$AUDIT_TAMPER_DIR/mog.lock" <<'PY'
from pathlib import Path
import sys

path = Path(sys.argv[1])
text = path.read_text(encoding="utf-8")
updated = text.replace(
    'artifact_signature = "',
    'artifact_signature = "tampered-',
    1,
)
if updated == text:
    raise SystemExit("failed to tamper with artifact_signature")
path.write_text(updated, encoding="utf-8")
PY

if (cd "$AUDIT_TAMPER_DIR" && "$MOG" install --locked >/tmp/mog_artifact_signature_failure.txt 2>&1); then
    echo "[FAIL] locked installs should reject tampered artifact signatures"
    cat /tmp/mog_artifact_signature_failure.txt
    exit 1
fi

if ! grep -Fq "artifact signature verification failed" /tmp/mog_artifact_signature_failure.txt; then
    echo "[FAIL] tampered artifact signature failures should explain signature verification"
    cat /tmp/mog_artifact_signature_failure.txt
    exit 1
fi

AUDIT_CLEAN_OUTPUT="$(
    cd "$AUDIT_CONSUMER_DIR" && "$MOG" audit
)"
if [[ "$AUDIT_CLEAN_OUTPUT" != *"No known vulnerable packages found."* ]]; then
    echo "[FAIL] audit should report a clean result when no advisories match"
    echo "$AUDIT_CLEAN_OUTPUT"
    exit 1
fi

write_signed_advisories \
    "$AUDIT_REGISTRY_DIR" \
    "$AUDIT_KEY_FILE" \
    "MOG-2026-0001" \
    "acme:audit-util" \
    "1.0.0" \
    "high" \
    "Audit test advisory." \
    "1.0.1" \
    "https://example.invalid/advisories/MOG-2026-0001"

set +e
AUDIT_FINDINGS_OUTPUT="$(
    cd "$AUDIT_CONSUMER_DIR" && "$MOG" audit
)"
AUDIT_FINDINGS_STATUS=$?
set -e

if [[ $AUDIT_FINDINGS_STATUS -eq 0 ]]; then
    echo "[FAIL] audit should exit non-zero when a locked package is vulnerable"
    echo "$AUDIT_FINDINGS_OUTPUT"
    exit 1
fi

if [[ "$AUDIT_FINDINGS_OUTPUT" != *"MOG-2026-0001 [high] acme:audit-util@1.0.0"* ]] || \
   [[ "$AUDIT_FINDINGS_OUTPUT" != *"Fixed in 1.0.1."* ]]; then
    echo "[FAIL] audit should report advisory id, severity, package, and remediation"
    echo "$AUDIT_FINDINGS_OUTPUT"
    exit 1
fi

GIT_REPO_DIR="$(mktemp -d)"
mkdir -p "$GIT_REPO_DIR/src"
cat > "$GIT_REPO_DIR/mog.toml" <<'EOF_GIT_PACKAGE'
kind = "source"
import_name = "githello"
namespace = "acme"
name = "git-hello"
version = "1.0.0"
author = "Git dependency test"
description = "Git-sourced package."
entry = "src/main.mog"
dependencies = []
EOF_GIT_PACKAGE

cat > "$GIT_REPO_DIR/src/main.mog" <<'EOF_GIT_PACKAGE_SRC'
const MESSAGE str = "hello from git dependency"

fn Name() str {
    return MESSAGE
}
EOF_GIT_PACKAGE_SRC

git -C "$GIT_REPO_DIR" init --initial-branch=main >/dev/null
git -C "$GIT_REPO_DIR" config user.email "mog-tests@example.com"
git -C "$GIT_REPO_DIR" config user.name "Mog Tests"
git -C "$GIT_REPO_DIR" add . >/dev/null
git -C "$GIT_REPO_DIR" commit -m "init" >/dev/null

GIT_CONSUMER_DIR="$(mktemp -d)"
cat > "$GIT_CONSUMER_DIR/mog.toml" <<EOF_GIT_CONSUMER
kind = "project"
name = "git-consumer"
version = "0.1.0"
description = "git consumer"

[dependencies]
githello = { git = "$GIT_REPO_DIR", branch = "main", package = "acme:git-hello", version = "1.0.0" }
EOF_GIT_CONSUMER

cat > "$GIT_CONSUMER_DIR/app.mog" <<'EOF_GIT_APP'
const githello = @import("githello")
print(githello.Name())
EOF_GIT_APP

if ! (cd "$GIT_CONSUMER_DIR" && "$MOG" install >/dev/null); then
    echo "[FAIL] install should resolve git dependencies"
    exit 1
fi

GIT_OUTPUT="$("$MOG" run "$GIT_CONSUMER_DIR/app.mog")"
if [[ "$GIT_OUTPUT" != *"hello from git dependency"* ]]; then
    echo "[FAIL] run should execute git dependencies"
    echo "$GIT_OUTPUT"
    exit 1
fi

if ! grep -Fq 'source_type = "git"' "$GIT_CONSUMER_DIR/mog.lock" || \
   ! grep -Fq 'git_commit = "' "$GIT_CONSUMER_DIR/mog.lock"; then
    echo "[FAIL] git dependencies should be recorded in mog.lock"
    cat "$GIT_CONSUMER_DIR/mog.lock"
    exit 1
fi

if ! (cd "$GIT_CONSUMER_DIR" && "$MOG" install --offline >/dev/null); then
    echo "[FAIL] install --offline should succeed for cached git dependencies"
    exit 1
fi

GIT_OFFLINE_FAIL_DIR="$(mktemp -d)"
cp "$GIT_CONSUMER_DIR/mog.toml" "$GIT_OFFLINE_FAIL_DIR/mog.toml"
cp "$GIT_CONSUMER_DIR/app.mog" "$GIT_OFFLINE_FAIL_DIR/app.mog"
if (cd "$GIT_OFFLINE_FAIL_DIR" && \
    MOG_CACHE_DIR="$TEMP_DIR/git-empty-cache" \
    "$MOG" install --offline >/tmp/mog_git_offline_failure.txt 2>&1); then
    echo "[FAIL] install --offline should reject uncached git dependencies"
    cat /tmp/mog_git_offline_failure.txt
    exit 1
fi

if ! grep -Eq "offline|cached locally" /tmp/mog_git_offline_failure.txt; then
    echo "[FAIL] install --offline should explain missing cached git dependencies"
    cat /tmp/mog_git_offline_failure.txt
    exit 1
fi

POLICY_REGISTRY_DIR="$(mktemp -d)"
cat > "$POLICY_REGISTRY_DIR/mog.toml" <<EOF_POLICY_REGISTRY
kind = "project"
name = "policy-registry-test"
version = "0.1.0"
description = "policy registry test"

[policy]
allowed_registries = ["internal"]

[registries.default]
index = "$REGISTRY_DIR"

[dependencies]
http = { package = "acme:http", version = "1.0.0" }
EOF_POLICY_REGISTRY

if (cd "$POLICY_REGISTRY_DIR" && "$MOG" install >/tmp/mog_policy_registry_failure.txt 2>&1); then
    echo "[FAIL] install should reject dependencies from registries outside policy allowlists"
    cat /tmp/mog_policy_registry_failure.txt
    exit 1
fi

if ! grep -Fq "Project policy disallows registry 'default' for package 'acme:http'." /tmp/mog_policy_registry_failure.txt; then
    echo "[FAIL] registry policy failure should name the rejected registry and package"
    cat /tmp/mog_policy_registry_failure.txt
    exit 1
fi

POLICY_NATIVE_DIR="$(mktemp -d)"
cat > "$POLICY_NATIVE_DIR/mog.toml" <<EOF_POLICY_NATIVE
kind = "project"
name = "policy-native-test"
version = "0.1.0"
description = "policy native test"

[policy]
allowed_native_namespaces = ["mog"]

[dependencies]
math = { path = "$PROJECT_ROOT/packages/examples/math", package = "examples:math", version = "0.1.0" }
EOF_POLICY_NATIVE

if (cd "$POLICY_NATIVE_DIR" && "$MOG" install >/tmp/mog_policy_native_failure.txt 2>&1); then
    echo "[FAIL] install should reject native packages outside allowed namespaces"
    cat /tmp/mog_policy_native_failure.txt
    exit 1
fi

if ! grep -Fq "Project policy disallows native package 'examples:math' from namespace 'examples'." /tmp/mog_policy_native_failure.txt; then
    echo "[FAIL] native namespace policy failure should name the rejected package"
    cat /tmp/mog_policy_native_failure.txt
    exit 1
fi

POLICY_CI_DIR="$(mktemp -d)"
cat > "$POLICY_CI_DIR/mog.toml" <<EOF_POLICY_CI
kind = "project"
name = "policy-ci-test"
version = "0.1.0"
description = "policy ci test"

[policy]
require_locked_in_ci = true

[dependencies]
hello = { path = "$PROJECT_ROOT/packages/examples/hello", package = "examples:hello", version = "0.1.0" }
EOF_POLICY_CI

cat > "$POLICY_CI_DIR/app.mog" <<'EOF_POLICY_CI_APP'
const hello = @import("hello")
print(hello.Greet())
EOF_POLICY_CI_APP

if ! (cd "$POLICY_CI_DIR" && "$MOG" install >/dev/null); then
    echo "[FAIL] baseline install should succeed before CI locked policy is enforced"
    exit 1
fi

if (cd "$POLICY_CI_DIR" && CI=1 "$MOG" install >/tmp/mog_policy_ci_install_failure.txt 2>&1); then
    echo "[FAIL] CI installs should require --locked when policy enables it"
    cat /tmp/mog_policy_ci_install_failure.txt
    exit 1
fi

if ! grep -Fq "Project policy requires --locked installs when CI is set in the environment." /tmp/mog_policy_ci_install_failure.txt; then
    echo "[FAIL] CI locked-policy failure should explain the required flag"
    cat /tmp/mog_policy_ci_install_failure.txt
    exit 1
fi

if ! (cd "$POLICY_CI_DIR" && CI=1 "$MOG" install --locked >/dev/null); then
    echo "[FAIL] install --locked should satisfy the CI locked policy"
    exit 1
fi

if (cd "$POLICY_CI_DIR" && CI=1 "$MOG" run app.mog >/tmp/mog_policy_ci_run_failure.txt 2>&1); then
    echo "[FAIL] CI runs should require --locked when policy enables it"
    cat /tmp/mog_policy_ci_run_failure.txt
    exit 1
fi

if ! grep -Fq "Project policy requires --locked installs when CI is set in the environment." /tmp/mog_policy_ci_run_failure.txt; then
    echo "[FAIL] CI run failure should explain the required flag"
    cat /tmp/mog_policy_ci_run_failure.txt
    exit 1
fi

if [[ "$(cd "$POLICY_CI_DIR" && CI=1 "$MOG" run --locked app.mog)" != *"hello from source package"* ]]; then
    echo "[FAIL] run --locked should satisfy the CI locked policy"
    exit 1
fi

SCRIPT_WORKFLOW_DIR="$(mktemp -d)"
mkdir -p "$SCRIPT_WORKFLOW_DIR/tests" "$SCRIPT_WORKFLOW_DIR/tools" \
    "$SCRIPT_WORKFLOW_DIR/packages/examples/build-helper/src"
cat > "$SCRIPT_WORKFLOW_DIR/mog.toml" <<EOF_SCRIPTS
kind = "project"
name = "script-workflow"
version = "0.1.0"
description = "script workflow test"

[scripts]
test = "./tests/main.mog"
build = "tools/build.mog"

[dependencies]
math = { path = "$PROJECT_ROOT/packages/examples/math", package = "examples:math", version = "0.1.0" }

[dev-dependencies]
hello = { path = "$PROJECT_ROOT/packages/examples/hello", package = "examples:hello", version = "0.1.0" }

[build-dependencies]
build_helper = { path = "packages/examples/build-helper", package = "examples:build-helper", version = "0.1.0" }
EOF_SCRIPTS

cat > "$SCRIPT_WORKFLOW_DIR/packages/examples/build-helper/src/main.mog" <<'EOF_BUILD_HELPER_SRC'
fn Name() str {
    return "build-helper"
}
EOF_BUILD_HELPER_SRC

cat > "$SCRIPT_WORKFLOW_DIR/packages/examples/build-helper/mog.toml" <<'EOF_BUILD_HELPER_MANIFEST'
kind = "source"
import_name = "build_helper"
namespace = "examples"
name = "build-helper"
version = "0.1.0"
license = "MIT"
description = "Build-only helper package."
entry = "src/main.mog"
dependencies = []
EOF_BUILD_HELPER_MANIFEST

cat > "$SCRIPT_WORKFLOW_DIR/tests/main.mog" <<'EOF_SCRIPT_TEST'
const hello = @import("hello")
print("script test")
print(hello.Greet())
EOF_SCRIPT_TEST

cat > "$SCRIPT_WORKFLOW_DIR/tools/build.mog" <<'EOF_SCRIPT_BUILD'
const build_helper = @import("build_helper")
print("script build")
print(build_helper.Name())
EOF_SCRIPT_BUILD

if ! (cd "$SCRIPT_WORKFLOW_DIR" && "$MOG" remove math >/dev/null); then
    echo "[FAIL] script workflow setup should preserve [scripts] through manifest rewrites"
    exit 1
fi

if ! grep -Fq '[scripts]' "$SCRIPT_WORKFLOW_DIR/mog.toml" || \
   ! grep -Fq 'test = "tests/main.mog"' "$SCRIPT_WORKFLOW_DIR/mog.toml" || \
   ! grep -Fq 'build = "tools/build.mog"' "$SCRIPT_WORKFLOW_DIR/mog.toml"; then
    echo "[FAIL] project manifest rewrites should round-trip the [scripts] table"
    cat "$SCRIPT_WORKFLOW_DIR/mog.toml"
    exit 1
fi

SCRIPT_TEST_OUTPUT="$(cd "$SCRIPT_WORKFLOW_DIR" && "$MOG" test)"
if [[ "$SCRIPT_TEST_OUTPUT" != *"script test"* || \
      "$SCRIPT_TEST_OUTPUT" != *"hello from source package"* ]]; then
    echo "[FAIL] mog test should run the configured script and install dev dependencies"
    echo "$SCRIPT_TEST_OUTPUT"
    exit 1
fi
if grep -Fq 'examples:build-helper' "$SCRIPT_WORKFLOW_DIR/.mog/install/registry.toml"; then
    echo "[FAIL] mog test should not install build-only dependencies"
    cat "$SCRIPT_WORKFLOW_DIR/.mog/install/registry.toml"
    exit 1
fi
if ! (cd "$SCRIPT_WORKFLOW_DIR" && "$MOG" install --offline >/dev/null); then
    echo "[FAIL] mog install should restore build-only dependencies for the full developer graph"
    exit 1
fi

SCRIPT_BUILD_OUTPUT="$(cd "$SCRIPT_WORKFLOW_DIR" && "$MOG" build --locked --offline)"
if [[ "$SCRIPT_BUILD_OUTPUT" != *"script build"* || \
      "$SCRIPT_BUILD_OUTPUT" != *"build-helper"* ]]; then
    echo "[FAIL] mog build should honor locked/offline execution for configured scripts"
    echo "$SCRIPT_BUILD_OUTPUT"
    exit 1
fi
if ! grep -Fq 'examples:build-helper' "$SCRIPT_WORKFLOW_DIR/.mog/install/registry.toml"; then
    echo "[FAIL] mog build should install build-only dependencies"
    cat "$SCRIPT_WORKFLOW_DIR/.mog/install/registry.toml"
    exit 1
fi

SCRIPT_MISSING_DIR="$(mktemp -d)"
cat > "$SCRIPT_MISSING_DIR/mog.toml" <<'EOF_SCRIPT_MISSING'
kind = "project"
name = "script-missing"
version = "0.1.0"
description = "missing script"
EOF_SCRIPT_MISSING

if (cd "$SCRIPT_MISSING_DIR" && "$MOG" test >/tmp/mog_script_missing_failure.txt 2>&1); then
    echo "[FAIL] mog test should reject projects without [scripts].test"
    cat /tmp/mog_script_missing_failure.txt
    exit 1
fi

if ! grep -Fq '[scripts].test' /tmp/mog_script_missing_failure.txt; then
    echo "[FAIL] missing test-script failures should mention [scripts].test"
    cat /tmp/mog_script_missing_failure.txt
    exit 1
fi

SCRIPT_INVALID_ABS_DIR="$(mktemp -d)"
cat > "$SCRIPT_INVALID_ABS_DIR/mog.toml" <<EOF_SCRIPT_INVALID_ABS
kind = "project"
name = "script-invalid-abs"
version = "0.1.0"
description = "invalid absolute script"

[scripts]
test = "$PROJECT_ROOT/tests/sample.mog"
EOF_SCRIPT_INVALID_ABS

if (cd "$SCRIPT_INVALID_ABS_DIR" && "$MOG" test >/tmp/mog_script_abs_failure.txt 2>&1); then
    echo "[FAIL] absolute script paths should be rejected"
    cat /tmp/mog_script_abs_failure.txt
    exit 1
fi

if ! grep -Fq "must be a relative path" /tmp/mog_script_abs_failure.txt; then
    echo "[FAIL] absolute script failures should explain the relative-path requirement"
    cat /tmp/mog_script_abs_failure.txt
    exit 1
fi

SCRIPT_INVALID_EXT_DIR="$(mktemp -d)"
cat > "$SCRIPT_INVALID_EXT_DIR/mog.toml" <<'EOF_SCRIPT_INVALID_EXT'
kind = "project"
name = "script-invalid-ext"
version = "0.1.0"
description = "invalid extension script"

[scripts]
test = "tests/main.txt"
EOF_SCRIPT_INVALID_EXT

if (cd "$SCRIPT_INVALID_EXT_DIR" && "$MOG" test >/tmp/mog_script_ext_failure.txt 2>&1); then
    echo "[FAIL] script paths with non-.mog extensions should be rejected"
    cat /tmp/mog_script_ext_failure.txt
    exit 1
fi

if ! grep -Fq "must use the .mog extension" /tmp/mog_script_ext_failure.txt; then
    echo "[FAIL] invalid script-extension failures should explain the .mog requirement"
    cat /tmp/mog_script_ext_failure.txt
    exit 1
fi

SCRIPT_INVALID_ESCAPE_DIR="$(mktemp -d)"
cat > "$SCRIPT_INVALID_ESCAPE_DIR/mog.toml" <<'EOF_SCRIPT_INVALID_ESCAPE'
kind = "project"
name = "script-invalid-escape"
version = "0.1.0"
description = "invalid escaping script"

[scripts]
test = "../outside.mog"
EOF_SCRIPT_INVALID_ESCAPE

if (cd "$SCRIPT_INVALID_ESCAPE_DIR" && "$MOG" test >/tmp/mog_script_escape_failure.txt 2>&1); then
    echo "[FAIL] script paths that escape the project root should be rejected"
    cat /tmp/mog_script_escape_failure.txt
    exit 1
fi

if ! grep -Fq "must stay within the project root" /tmp/mog_script_escape_failure.txt; then
    echo "[FAIL] escaping script failures should explain the project-root restriction"
    cat /tmp/mog_script_escape_failure.txt
    exit 1
fi

CACHE_STATUS_DIR="$(mktemp -d)"
EXPECTED_CACHE_ROOT="$TEMP_DIR/cache-root"
EXPECTED_USER_CACHE="$EXPECTED_CACHE_ROOT/packages"
EXPECTED_PROJECT_CACHE="$CACHE_STATUS_DIR/.mog/cache/packages/local"
EXPECTED_REGISTRY_CACHE="$EXPECTED_CACHE_ROOT/registry"
EXPECTED_GIT_CACHE="$EXPECTED_CACHE_ROOT/git"

CACHE_PATH_USER="$(cd "$CACHE_STATUS_DIR" && MOG_CACHE_DIR="$EXPECTED_CACHE_ROOT" "$MOG" cache path user)"
CACHE_PATH_PROJECT="$(cd "$CACHE_STATUS_DIR" && MOG_CACHE_DIR="$EXPECTED_CACHE_ROOT" "$MOG" cache path project)"
CACHE_PATH_REGISTRY="$(cd "$CACHE_STATUS_DIR" && MOG_CACHE_DIR="$EXPECTED_CACHE_ROOT" "$MOG" cache path registry)"
CACHE_PATH_GIT="$(cd "$CACHE_STATUS_DIR" && MOG_CACHE_DIR="$EXPECTED_CACHE_ROOT" "$MOG" cache path git)"

if [[ "$CACHE_PATH_USER" != "$EXPECTED_USER_CACHE" || \
      "$CACHE_PATH_PROJECT" != "$EXPECTED_PROJECT_CACHE" || \
      "$CACHE_PATH_REGISTRY" != "$EXPECTED_REGISTRY_CACHE" || \
      "$CACHE_PATH_GIT" != "$EXPECTED_GIT_CACHE" ]]; then
    echo "[FAIL] cache path should report the expected cache roots"
    printf 'user=%s\nproject=%s\nregistry=%s\ngit=%s\n' \
        "$CACHE_PATH_USER" "$CACHE_PATH_PROJECT" "$CACHE_PATH_REGISTRY" "$CACHE_PATH_GIT"
    exit 1
fi

CACHE_STATUS_OUTPUT="$(cd "$CACHE_STATUS_DIR" && MOG_CACHE_DIR="$EXPECTED_CACHE_ROOT" "$MOG" cache status)"
if [[ "$CACHE_STATUS_OUTPUT" != *"user_packages = $EXPECTED_USER_CACHE"* || \
      "$CACHE_STATUS_OUTPUT" != *"project_fallback_packages = $EXPECTED_PROJECT_CACHE"* || \
      "$CACHE_STATUS_OUTPUT" != *"registry = $EXPECTED_REGISTRY_CACHE"* || \
      "$CACHE_STATUS_OUTPUT" != *"git = $EXPECTED_GIT_CACHE"* ]]; then
    echo "[FAIL] cache status should report all cache roots"
    echo "$CACHE_STATUS_OUTPUT"
    exit 1
fi

CACHE_PRUNE_DIR="$(mktemp -d)"
cat > "$CACHE_PRUNE_DIR/mog.toml" <<EOF_CACHE_PRUNE
kind = "project"
name = "cache-prune"
version = "0.1.0"
description = "cache prune test"

[dependencies]
hello = { path = "$PROJECT_ROOT/packages/examples/hello", package = "examples:hello", version = "0.1.0" }
EOF_CACHE_PRUNE

cat > "$CACHE_PRUNE_DIR/app.mog" <<'EOF_CACHE_PRUNE_APP'
const hello = @import("hello")
print(hello.Greet())
EOF_CACHE_PRUNE_APP

CACHE_PRUNE_ROOT="$TEMP_DIR/cache-prune-root"
if ! (cd "$CACHE_PRUNE_DIR" && MOG_CACHE_DIR="$CACHE_PRUNE_ROOT" "$MOG" install >/dev/null); then
    echo "[FAIL] cache prune setup install should succeed"
    exit 1
fi

CACHE_LOCAL_ENTRY="$(find "$CACHE_PRUNE_ROOT/packages/local" -mindepth 3 -maxdepth 3 -type d | head -n1)"
if [[ -z "$CACHE_LOCAL_ENTRY" ]]; then
    echo "[FAIL] cache prune setup should create a reusable local cache entry"
    exit 1
fi

CACHE_PRUNE_DRY_RUN_OUTPUT="$(cd "$CACHE_PRUNE_DIR" && MOG_CACHE_DIR="$CACHE_PRUNE_ROOT" "$MOG" cache prune --dry-run)"
if [[ "$CACHE_PRUNE_DRY_RUN_OUTPUT" != *"Would remove"* || \
      "$CACHE_PRUNE_DRY_RUN_OUTPUT" != *"$CACHE_LOCAL_ENTRY"* ]]; then
    echo "[FAIL] cache prune --dry-run should report removable cache entries"
    echo "$CACHE_PRUNE_DRY_RUN_OUTPUT"
    exit 1
fi
if [[ ! -d "$CACHE_LOCAL_ENTRY" ]]; then
    echo "[FAIL] cache prune --dry-run should not remove cache entries"
    exit 1
fi

CACHE_PRUNE_OUTPUT="$(cd "$CACHE_PRUNE_DIR" && MOG_CACHE_DIR="$CACHE_PRUNE_ROOT" "$MOG" cache prune)"
if [[ "$CACHE_PRUNE_OUTPUT" != *"Removed"* ]]; then
    echo "[FAIL] cache prune should report removed cache entries"
    echo "$CACHE_PRUNE_OUTPUT"
    exit 1
fi
if [[ -d "$CACHE_LOCAL_ENTRY" ]]; then
    echo "[FAIL] cache prune should remove stale local cache entries"
    exit 1
fi
if [[ ! -f "$CACHE_PRUNE_DIR/.mog/install/registry.toml" ]]; then
    echo "[FAIL] cache prune should not touch active install metadata"
    exit 1
fi
if [[ "$(cd "$CACHE_PRUNE_DIR" && MOG_CACHE_DIR="$CACHE_PRUNE_ROOT" "$MOG" run app.mog)" != *"hello from source package"* ]]; then
    echo "[FAIL] cache prune should leave the active install runnable"
    exit 1
fi

WORKSPACE_DIR="$(mktemp -d)"
mkdir -p "$WORKSPACE_DIR/apps/demo" "$WORKSPACE_DIR/members/hello-local/src"

cat > "$WORKSPACE_DIR/mog.toml" <<'EOF_WORKSPACE'
kind = "project"
name = "workspace-root"
version = "0.1.0"
description = "workspace root"

[workspace]
members = ["members/hello-local"]

[dependencies]
hello = { workspace = true, package = "examples:hello-local", version = "0.1.0" }
EOF_WORKSPACE

cat > "$WORKSPACE_DIR/members/hello-local/mog.toml" <<'EOF_MEMBER'
kind = "source"
import_name = "hello"
namespace = "examples"
name = "hello-local"
version = "0.1.0"
author = "Mog runtime"
description = "Workspace hello package."
entry = "src/main.mog"
dependencies = []
EOF_MEMBER

cat > "$WORKSPACE_DIR/members/hello-local/src/main.mog" <<'EOF_MEMBER_SRC'
const MESSAGE str = "hello from workspace package"

fn Greet() str {
    return MESSAGE
}
EOF_MEMBER_SRC

cat > "$WORKSPACE_DIR/apps/demo/app.mog" <<'EOF_WORKSPACE_APP'
const hello = @import("hello")
print(hello.Greet())
EOF_WORKSPACE_APP

pushd "$WORKSPACE_DIR/apps/demo" >/dev/null
"$MOG" install >/dev/null
WORKSPACE_RUN_OUTPUT="$("$MOG" run app.mog)"
popd >/dev/null

if [[ "$WORKSPACE_RUN_OUTPUT" != *"hello from workspace package"* ]]; then
    echo "[FAIL] workspace-root install/run did not resolve workspace dependency"
    echo "$WORKSPACE_RUN_OUTPUT"
    exit 1
fi

if [[ ! -f "$WORKSPACE_DIR/.mog/install/registry.toml" || ! -f "$WORKSPACE_DIR/mog.lock" ]]; then
    echo "[FAIL] workspace-root commands should write install metadata at the workspace root"
    find "$WORKSPACE_DIR" -maxdepth 4 -print
    exit 1
fi

if ! grep -Fq 'source_type = "workspace"' "$WORKSPACE_DIR/mog.lock"; then
    echo "[FAIL] workspace dependencies should be recorded as workspace sources"
    cat "$WORKSPACE_DIR/mog.lock"
    exit 1
fi

REMOVE_DIR="$(mktemp -d)"
cat > "$REMOVE_DIR/mog.toml" <<EOF_REMOVE
kind = "project"
name = "remove-test"
version = "0.1.0"
description = "remove dependency test"

[dependencies]
hello = { path = "$PROJECT_ROOT/packages/examples/hello", package = "examples:hello", version = "0.1.0" }
EOF_REMOVE

cat > "$REMOVE_DIR/app.mog" <<'EOF_REMOVE_APP'
const hello = @import("hello")
print(hello.Greet())
EOF_REMOVE_APP

if [[ "$(cd "$REMOVE_DIR" && "$MOG" run app.mog)" != *"hello from source package"* ]]; then
    echo "[FAIL] remove test setup should run before the dependency is removed"
    exit 1
fi

if ! (cd "$REMOVE_DIR" && "$MOG" remove hello >/dev/null); then
    echo "[FAIL] remove should delete a direct dependency and refresh install metadata"
    exit 1
fi

if grep -Fq 'hello = {' "$REMOVE_DIR/mog.toml"; then
    echo "[FAIL] remove should delete the dependency entry from mog.toml"
    cat "$REMOVE_DIR/mog.toml"
    exit 1
fi

if grep -Fq 'examples:hello' "$REMOVE_DIR/mog.lock" || \
   grep -Fq 'examples:hello' "$REMOVE_DIR/.mog/install/registry.toml"; then
    echo "[FAIL] remove should refresh mog.lock and install metadata after deletion"
    cat "$REMOVE_DIR/mog.lock"
    cat "$REMOVE_DIR/.mog/install/registry.toml"
    exit 1
fi

if (cd "$REMOVE_DIR" && "$MOG" run app.mog >/tmp/mog_remove_run_failure.txt 2>&1); then
    echo "[FAIL] removed dependencies should no longer resolve during run"
    cat /tmp/mog_remove_run_failure.txt
    exit 1
fi

if ! grep -Fq "hello" /tmp/mog_remove_run_failure.txt; then
    echo "[FAIL] run failures after remove should still reference the missing import"
    cat /tmp/mog_remove_run_failure.txt
    exit 1
fi

REMOVE_DEV_DIR="$(mktemp -d)"
cat > "$REMOVE_DEV_DIR/mog.toml" <<EOF_REMOVE_DEV
kind = "project"
name = "remove-dev-test"
version = "0.1.0"
description = "remove dev dependency test"

[dev-dependencies]
hello = { path = "$PROJECT_ROOT/packages/examples/hello", package = "examples:hello", version = "0.1.0" }
EOF_REMOVE_DEV

if ! (cd "$REMOVE_DEV_DIR" && "$MOG" remove hello >/dev/null); then
    echo "[FAIL] remove should delete dev-dependencies when no normal dependency matches"
    exit 1
fi

if grep -Fq 'hello = {' "$REMOVE_DEV_DIR/mog.toml"; then
    echo "[FAIL] remove should delete the alias from [dev-dependencies]"
    cat "$REMOVE_DEV_DIR/mog.toml"
    exit 1
fi

if grep -Fq 'examples:hello' "$REMOVE_DEV_DIR/mog.lock" || \
   grep -Fq 'examples:hello' "$REMOVE_DEV_DIR/.mog/install/registry.toml"; then
    echo "[FAIL] remove should refresh metadata after deleting a dev-dependency"
    cat "$REMOVE_DEV_DIR/mog.lock"
    cat "$REMOVE_DEV_DIR/.mog/install/registry.toml"
    exit 1
fi

if (cd "$REMOVE_DEV_DIR" && "$MOG" remove hello >/tmp/mog_remove_missing_failure.txt 2>&1); then
    echo "[FAIL] remove should reject aliases that are no longer present"
    cat /tmp/mog_remove_missing_failure.txt
    exit 1
fi

if ! grep -Fq "No dependency named 'hello'" /tmp/mog_remove_missing_failure.txt; then
    echo "[FAIL] remove missing-alias failures should name the requested alias"
    cat /tmp/mog_remove_missing_failure.txt
    exit 1
fi

echo "[PASS] package manager workflow"

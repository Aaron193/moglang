#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
BUILD_DIR="${1:-$PROJECT_ROOT/build}"
MOG="$BUILD_DIR/interpreter"

if [[ ! -x "$MOG" ]]; then
    echo "Interpreter not found at $MOG" >&2
    exit 1
fi

OUTPUT="$($MOG "$SCRIPT_DIR/sample_host_api_v2.mog" 2>&1)"
EXPECTED=$'11\n13\n22\nfalse\n12\n11\n[0, 127, 255]\ntrue\ntrue\ntrue\ntrue\ntrue\ntrue'
if [[ "$OUTPUT" != "$EXPECTED" ]]; then
    echo "Host API v2 regression output mismatch" >&2
    diff -u <(printf '%s\n' "$EXPECTED") <(printf '%s\n' "$OUTPUT") || true
    exit 1
fi

python3 - "$PROJECT_ROOT/src/NativePackageAPI.hpp" \
           "$BUILD_DIR/generated/NativePackageAPIEmbedded.hpp" <<'PY'
from pathlib import Path
import sys

canonical = Path(sys.argv[1]).read_text(encoding="utf-8")
embedded = Path(sys.argv[2]).read_text(encoding="utf-8")
prefix = 'R"MOG_NATIVE_API('
suffix = ')MOG_NATIVE_API";'
published = embedded.split(prefix, 1)[1].rsplit(suffix, 1)[0]
if published != canonical:
    raise SystemExit("generated published NativePackageAPI.hpp is not exact")
PY

"$BUILD_DIR/host_api_v2_cross_vm_regression" "$BUILD_DIR/packages"

# Existing ABI-3 packages must continue to execute with the extended host table.
LEGACY_OUTPUT="$($MOG "$SCRIPT_DIR/sample_import_native_package.mog" 2>&1)"
if [[ "$LEGACY_OUTPUT" != *"42"* || "$LEGACY_OUTPUT" != *"Hello, Ada"* ]]; then
    echo "Existing ABI-3 native package compatibility failed" >&2
    echo "$LEGACY_OUTPUT" >&2
    exit 1
fi

echo "[PASS] Host API v2 persistent values and recoverable callbacks"

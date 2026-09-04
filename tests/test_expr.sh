#!/bin/bash
set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
INTERPRETER="$PROJECT_ROOT/build/interpreter"

if [[ ! -x "$INTERPRETER" ]]; then
    echo "Interpreter not found at $INTERPRETER"
    echo "Build first with: $PROJECT_ROOT/build.sh"
    exit 1
fi

FILTER="${1:-$SCRIPT_DIR/*.kel}"

shopt -s nullglob
FILES=( $FILTER )
shopt -u nullglob

if [[ ${#FILES[@]} -eq 0 ]]; then
    echo "No .kel files matched: $FILTER"
    exit 1
fi

passed=0
failed=0

for file in "${FILES[@]}"; do
    if [[ ! -f "$file" || "${file##*.}" != "kelvra" ]]; then
        continue
    fi

    base_name="$(basename "$file")"
    if [[ "$base_name" == fail_* ]]; then
        continue
    fi
    if [[ "$base_name" == sample_native_error_* ]]; then
        continue
    fi
    if [[ "$base_name" == "sample_compile_multi_error.kel" || "$base_name" == "sample_runtime_stacktrace.kel" || "$base_name" == "sample_invalid_logical_word_sequence.kel" ]]; then
        continue
    fi
    if [[ "$base_name" == "sample_import_cycle.kel" || "$base_name" == "sample_export_scoped_error.kel" || "$base_name" == "sample_import_native_missing.kel" || "$base_name" == "sample_import_native_type_mismatch.kel" || "$base_name" == "sample_import_native_invalid_id.kel" || "$base_name" == "sample_import_native_bare_invalid.kel" || "$base_name" == "sample_import_native_metadata_mismatch.kel" ]]; then
        continue
    fi

    echo "========================================"
    echo "Running: $file"
    echo "----------------------------------------"

    if "$INTERPRETER" "$file"; then
        echo "[PASS] $file"
        passed=$((passed + 1))
    else
        echo "[FAIL] $file"
        failed=$((failed + 1))
    fi

    echo
 done

echo "========================================"
echo "Summary: PASS=$passed FAIL=$failed TOTAL=$((passed + failed))"

if [[ $failed -ne 0 ]]; then
    exit 1
fi

exit 0

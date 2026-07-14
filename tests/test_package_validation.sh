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

run_expect_success() {
    local label="$1"
    shift

    if "$@"; then
        echo "[PASS] $label"
        return 0
    fi

    echo "[FAIL] $label"
    return 1
}

run_expect_failure() {
    local label="$1"
    local expected="$2"
    shift 2

    set +e
    local output
    output="$("$@" 2>&1)"
    local status=$?
    set -e

    if [[ $status -eq 0 ]]; then
        echo "[FAIL] $label"
        echo "$output"
        return 1
    fi

    if ! grep -Fq "$expected" <<< "$output"; then
        echo "[FAIL] $label"
        echo "Expected: $expected"
        echo "Actual output:"
        echo "$output"
        return 1
    fi

    echo "[PASS] $label"
    return 0
}

failed=0

run_expect_success \
    "validate examples:math" \
    "$INTERPRETER" --validate-package "$PROJECT_ROOT/packages/examples/math" ||
    failed=1

run_expect_success \
    "validate examples:counter" \
    "$INTERPRETER" --validate-package="$PROJECT_ROOT/packages/examples/counter" ||
    failed=1

run_expect_success \
    "validate examples:hello source package" \
    "$INTERPRETER" --validate-package "$PROJECT_ROOT/packages/examples/hello" ||
    failed=1

run_expect_failure \
    "reject registration mismatch" \
    "Manifest declares 'examples:mismatch' but library registers 'examples:declared_math'." \
    "$INTERPRETER" --validate-package "$PROJECT_ROOT/packages/examples/mismatch" ||
    failed=1

TEMP_DIR="$(mktemp -d)"
LOOKALIKE_DIR="$PROJECT_ROOT/packages-namespace-lookalike-$$"
trap 'rm -rf "$TEMP_DIR" "$LOOKALIKE_DIR"' EXIT
mkdir -p "$TEMP_DIR/mog/fake"
cat <<'EOF_MANIFEST' > "$TEMP_DIR/mog/fake/package.toml"
namespace = "mog"
name = "fake"
version = "0.1.0"
license = "MIT"
abi_version = 3
mog_runtime = "^0.1.0"
description = "fake"
dependencies = []

[native]
build = "cmake"
targets = ["linux-x86_64-gnu"]
EOF_MANIFEST

run_expect_failure \
    "reject reserved mog namespace outside repo package roots" \
    "Namespace 'mog' is reserved for runtime-maintained packages." \
    "$INTERPRETER" --validate-package "$TEMP_DIR/mog/fake" ||
    failed=1

mkdir -p "$TEMP_DIR/examples/invalid-system-dep"
cat <<'EOF_BAD_SYSDEP' > "$TEMP_DIR/examples/invalid-system-dep/package.toml"
kind = "native"
namespace = "examples"
name = "invalid-system-dep"
version = "0.1.0"
license = "MIT"
abi_version = 3
mog_runtime = "^0.1.0"
description = "invalid system dependency"
dependencies = []

[native]
build = "cmake"
targets = ["linux-x86_64-gnu"]

[system-dependencies]
sdl2 = ">=2.0.0"
EOF_BAD_SYSDEP

run_expect_failure \
    "reject malformed system dependency entries" \
    "Invalid system dependency 'sdl2': System dependency entries must be inline tables." \
    "$INTERPRETER" --validate-package "$TEMP_DIR/examples/invalid-system-dep" ||
    failed=1

mkdir -p "$TEMP_DIR/examples/unsupported-native-build"
cat <<'EOF_UNSUPPORTED_NATIVE_BUILD' > "$TEMP_DIR/examples/unsupported-native-build/package.toml"
kind = "native"
namespace = "examples"
name = "unsupported-native-build"
version = "0.1.0"
license = "MIT"
abi_version = 3
mog_runtime = "^0.1.0"
description = "unsupported native build"
dependencies = []

[native]
build = "make"
targets = ["linux-x86_64-gnu"]
EOF_UNSUPPORTED_NATIVE_BUILD

run_expect_failure \
    "reject unsupported native build backend" \
    "Native package manifest [native].build must currently be \"cmake\"." \
    "$INTERPRETER" --validate-package "$TEMP_DIR/examples/unsupported-native-build" ||
    failed=1

mkdir -p "$TEMP_DIR/examples/source-system-dep/src"
cat <<'EOF_SOURCE_SYSDEP' > "$TEMP_DIR/examples/source-system-dep/package.toml"
kind = "source"
import_name = "source-system-dep"
namespace = "examples"
name = "source-system-dep"
version = "0.1.0"
license = "MIT"
description = "source package with native-only metadata"
entry = "src/main.mog"
dependencies = []

[system-dependencies]
sdl2 = { version = ">=2.0.0", required = true }
EOF_SOURCE_SYSDEP

cat <<'EOF_SOURCE_SYSDEP_SRC' > "$TEMP_DIR/examples/source-system-dep/src/main.mog"
fn Name() str {
    return "source-system-dep"
}
EOF_SOURCE_SYSDEP_SRC

run_expect_failure \
    "reject system dependencies on source packages" \
    "Only native package manifests may declare [system-dependencies]." \
    "$INTERPRETER" --validate-package "$TEMP_DIR/examples/source-system-dep" ||
    failed=1

mkdir -p "$TEMP_DIR/examples/legacysource/src"
cat <<'EOF_LEGACY_SOURCE' > "$TEMP_DIR/examples/legacysource/package.toml"
kind = "source"
import_name = "legacysource"
namespace = "examples"
name = "legacysource"
version = "0.1.0"
license = "MIT"
description = "legacy source package"
entry = "src/main.mog"
dependencies = []
EOF_LEGACY_SOURCE

cat <<'EOF_LEGACY_SOURCE_API' > "$TEMP_DIR/examples/legacysource/package.api.mog"
package legacysource

fn Name() str
EOF_LEGACY_SOURCE_API

cat <<'EOF_LEGACY_SOURCE_SRC' > "$TEMP_DIR/examples/legacysource/src/main.mog"
fn Name() str {
    return "legacysource"
}
EOF_LEGACY_SOURCE_SRC

run_expect_success \
    "validate legacy source package manifest" \
    "$INTERPRETER" --validate-package "$TEMP_DIR/examples/legacysource" ||
    failed=1

mkdir -p "$TEMP_DIR/examples/missingentry/src"
cat <<'EOF_MISSING_ENTRY' > "$TEMP_DIR/examples/missingentry/mog.toml"
kind = "source"
import_name = "missingentry"
namespace = "examples"
name = "missingentry"
version = "0.1.0"
license = "MIT"
description = "missing source entry"
entry = "src/absent.mog"
dependencies = []
EOF_MISSING_ENTRY

cat <<'EOF_MISSING_ENTRY_API' > "$TEMP_DIR/examples/missingentry/package.api.mog"
package missingentry

fn Name() str
EOF_MISSING_ENTRY_API

cat <<'EOF_MISSING_ENTRY_SRC' > "$TEMP_DIR/examples/missingentry/src/main.mog"
fn Name() str {
    return "missing-entry"
}
EOF_MISSING_ENTRY_SRC

run_expect_failure \
    "reject missing source package entry" \
    "is missing entry module" \
    "$INTERPRETER" --validate-package "$TEMP_DIR/examples/missingentry" ||
    failed=1

mkdir -p "$TEMP_DIR/mog/fake-source/src"
cat <<'EOF_FAKE_SOURCE' > "$TEMP_DIR/mog/fake-source/mog.toml"
kind = "source"
import_name = "fake-source"
namespace = "mog"
name = "fake-source"
version = "0.1.0"
license = "MIT"
description = "reserved source package"
entry = "src/main.mog"
dependencies = []
EOF_FAKE_SOURCE

cat <<'EOF_FAKE_SOURCE_API' > "$TEMP_DIR/mog/fake-source/package.api.mog"
package fake-source

fn Name() str
EOF_FAKE_SOURCE_API

cat <<'EOF_FAKE_SOURCE_SRC' > "$TEMP_DIR/mog/fake-source/src/main.mog"
fn Name() str {
    return "fake-source"
}
EOF_FAKE_SOURCE_SRC

run_expect_failure \
    "reject reserved mog namespace for source packages" \
    "Namespace 'mog' is reserved for runtime-maintained packages." \
    "$INTERPRETER" --validate-package "$TEMP_DIR/mog/fake-source" ||
    failed=1

mkdir -p "$TEMP_DIR/std/fake/src"
printf '%s\n' 'kind = "source"' 'module = "std/fake"' 'import_name = "fake"' 'namespace = "thirdparty"' 'name = "fake"' 'version = "0.1.0"' 'license = "MIT"' 'description = "invalid standard module"' 'entry = "src/main.mog"' 'dependencies = []' > "$TEMP_DIR/std/fake/mog.toml"
printf '%s\n' 'package fake' 'fn Name() str' > "$TEMP_DIR/std/fake/package.api.mog"
printf '%s\n' 'fn Name() str { return "fake" }' > "$TEMP_DIR/std/fake/src/main.mog"
run_expect_failure \
    "reject external std module" \
    "Module namespace 'std/...' is reserved for language-owned modules." \
    "$INTERPRETER" --validate-package "$TEMP_DIR/std/fake" ||
    failed=1
mkdir -p "$LOOKALIKE_DIR/packages/std/fake/src"
printf '%s\n' 'kind = "source"' 'module = "std/fake"' 'import_name = "fake"' 'namespace = "thirdparty"' 'name = "fake"' 'version = "0.1.0"' 'license = "MIT"' 'description = "lookalike standard module"' 'entry = "src/main.mog"' 'dependencies = []' > "$LOOKALIKE_DIR/packages/std/fake/mog.toml"
printf '%s\n' 'package fake' 'fn Name() str' > "$LOOKALIKE_DIR/packages/std/fake/package.api.mog"
printf '%s\n' 'fn Name() str { return "fake" }' > "$LOOKALIKE_DIR/packages/std/fake/src/main.mog"
run_expect_failure \
    "reject std module under lookalike package root" \
    "Module namespace 'std/...' is reserved for language-owned modules." \
    "$INTERPRETER" --validate-package "$LOOKALIKE_DIR/packages/std/fake" ||
    failed=1


if [[ $failed -ne 0 ]]; then
    exit 1
fi

echo "[PASS] package validation tests"
exit 0

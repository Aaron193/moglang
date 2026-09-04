#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 2 ]]; then
    echo "usage: $0 /path/to/kelvra /path/to/foundation-packages" >&2
    exit 2
fi

KELVRA="$(cd "$(dirname "$1")" && pwd)/$(basename "$1")"
PACKAGE_ROOT="$(cd "$2" && pwd)"
if [[ ! -x "$KELVRA" ]]; then
    echo "Kelvra interpreter is not executable: $KELVRA" >&2
    exit 2
fi

WORK_DIR="$(mktemp -d)"
trap 'rm -rf "$WORK_DIR"' EXIT
export KELVRA_CACHE_DIR="$WORK_DIR/cache"

run_package_test() {
    local package_dir="$1"
    local package_name="$2"
    local package_version="$3"
    local project_dir="$WORK_DIR/test-$package_name"

    mkdir -p "$project_dir"
    sed -e "s|__PACKAGE_NAME__|$package_name|g" \
        -e "s|__PACKAGE_VERSION__|$package_version|g" \
        -e "s|__PACKAGE_PATH__|$package_dir|g" \
        "$package_dir/.github/package-test.toml.in" > "$project_dir/kelvra.toml"
    cp "$package_dir/tests/main.kel" "$project_dir/main.kel"
    (
        cd "$project_dir"
        "$KELVRA" install
        "$KELVRA" run main.kel
    )

    local fixture
    local fixture_name
    for fixture in "$package_dir"/tests/errors/*.kel; do
        [[ -e "$fixture" ]] || continue
        fixture_name="error-$(basename "$fixture")"
        cp "$fixture" "$project_dir/$fixture_name"
        if (cd "$project_dir" && "$KELVRA" run "$fixture_name"); then
            echo "Expected failure fixture succeeded: $fixture" >&2
            exit 1
        fi
    done
}

for package_name in encoding json log math path test; do
    package_dir="$PACKAGE_ROOT/$package_name"
    version="$(sed -n 's/^version = "\([^"]*\)"/\1/p' "$package_dir/kelvra.toml" | head -n 1)"
    "$KELVRA" validate-package "$package_dir"
    run_package_test "$package_dir" "$package_name" "$version"
done

for package_name in fs random time window; do
    source_dir="$PACKAGE_ROOT/$package_name"
    package_dir="$WORK_DIR/github.com/kelvralang/$package_name"
    version="$(sed -n 's/^version = "\([^"]*\)"/\1/p' "$source_dir/kelvra.toml" | head -n 1)"
    mkdir -p "$(dirname "$package_dir")"
    rsync -a --exclude .git --exclude build "$source_dir/" "$package_dir/"
    cmake -S "$package_dir" -B "$package_dir/build" \
        -DCMAKE_BUILD_TYPE=Release \
        -DCMAKE_CXX_FLAGS="-Wall -Wextra -Wpedantic"
    cmake --build "$package_dir/build" --parallel
    cp "$package_dir/build/package.so" "$package_dir/package.so"
    "$KELVRA" validate-package "$package_dir"
    run_package_test "$package_dir" "$package_name" "$version"
done

echo "[PASS] foundation package compatibility"

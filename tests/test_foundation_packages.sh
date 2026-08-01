#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 2 ]]; then
    echo "usage: $0 /path/to/mog /path/to/foundation-packages" >&2
    exit 2
fi

MOG="$(cd "$(dirname "$1")" && pwd)/$(basename "$1")"
PACKAGE_ROOT="$(cd "$2" && pwd)"
if [[ ! -x "$MOG" ]]; then
    echo "Mog interpreter is not executable: $MOG" >&2
    exit 2
fi

WORK_DIR="$(mktemp -d)"
trap 'rm -rf "$WORK_DIR"' EXIT
export MOG_CACHE_DIR="$WORK_DIR/cache"

run_package_test() {
    local package_dir="$1"
    local package_name="$2"
    local package_version="$3"
    local project_dir="$WORK_DIR/test-$package_name"

    mkdir -p "$project_dir"
    sed -e "s|__PACKAGE_NAME__|$package_name|g" \
        -e "s|__PACKAGE_VERSION__|$package_version|g" \
        -e "s|__PACKAGE_PATH__|$package_dir|g" \
        "$package_dir/.github/package-test.toml.in" > "$project_dir/mog.toml"
    (
        cd "$project_dir"
        "$MOG" run "$package_dir/tests/main.mog"
    )

    for fixture in "$package_dir"/tests/errors/*.mog; do
        [[ -e "$fixture" ]] || continue
        if (cd "$project_dir" && "$MOG" run "$fixture"); then
            echo "Expected failure fixture succeeded: $fixture" >&2
            exit 1
        fi
    done
}

for package_name in encoding json log math path test; do
    package_dir="$PACKAGE_ROOT/$package_name"
    version="$(sed -n 's/^version = "\([^"]*\)"/\1/p' "$package_dir/mog.toml" | head -n 1)"
    "$MOG" validate-package "$package_dir"
    run_package_test "$package_dir" "$package_name" "$version"
done

for package_name in fs random time window; do
    source_dir="$PACKAGE_ROOT/$package_name"
    package_dir="$WORK_DIR/github.com/moglang/$package_name"
    version="$(sed -n 's/^version = "\([^"]*\)"/\1/p' "$source_dir/mog.toml" | head -n 1)"
    mkdir -p "$(dirname "$package_dir")"
    rsync -a --exclude .git --exclude build "$source_dir/" "$package_dir/"
    cmake -S "$package_dir" -B "$package_dir/build" \
        -DCMAKE_BUILD_TYPE=Release \
        -DCMAKE_CXX_FLAGS="-Wall -Wextra -Wpedantic"
    cmake --build "$package_dir/build" --parallel
    cp "$package_dir/build/package.so" "$package_dir/package.so"
    "$MOG" validate-package "$package_dir"
    run_package_test "$package_dir" "$package_name" "$version"
done

echo "[PASS] foundation package compatibility"

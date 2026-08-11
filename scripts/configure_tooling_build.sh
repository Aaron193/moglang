#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
build_dir="${1:-$repo_root/build/tooling-debug}"
cache="$build_dir/CMakeCache.txt"

if [[ -f "$cache" ]]; then
    cached_source="$(sed -n 's/^CMAKE_HOME_DIRECTORY:INTERNAL=//p' "$cache" | head -n 1)"
    if [[ -n "$cached_source" && "$cached_source" != "$repo_root" ]]; then
        cat >&2 <<EOF
The tooling build cache belongs to a different source checkout:
  cached source: $cached_source
  current source: $repo_root

Remove or rename "$build_dir", then run this command again. CMake caches cannot
be safely reused after a checkout is moved.
EOF
        exit 2
    fi
fi

cmake -S "$repo_root" -B "$build_dir" -DCMAKE_BUILD_TYPE=Debug

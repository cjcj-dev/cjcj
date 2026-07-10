#!/usr/bin/env bash
set -euo pipefail

repo=$(cd "$(dirname "$0")/../.." && pwd)
compiler=${1:-"$repo/target/release/bin/cangjie_compiler::cjc"}
probe_root="$repo/test/g10_probe"
matrix_root=$(mktemp -d /tmp/g10_probe_matrix.XXXXXX)
trap 'rm -rf "$matrix_root"' EXIT

for variant in arena_first literal_first literals_first; do
    for run in 1 2; do
        build_dir="$matrix_root/${variant}_${run}"
        mkdir -p "$build_dir"
        cp "$probe_root/src/RawString.cj" "$build_dir/RawString.cj"
        cp "$probe_root/src/Literals.cj" "$build_dir/Literals.cj"
        cp "$probe_root/variants/$variant.cj" "$build_dir/Probe.cj"
        set +e
        (cd "$build_dir" && "$compiler" -p . --output-type=staticlib -o probe.a) >"$build_dir/build.log" 2>&1
        rc=$?
        set -e
        bytes=$(stat -c %s "$build_dir/probe.a" 2>/dev/null || echo 0)
        echo "G10-PROBE variant=$variant run=$run exit=$rc bytes=$bytes"
        if [[ $rc -ne 0 ]]; then
            sed -n '1,80p' "$build_dir/build.log"
            exit "$rc"
        fi
    done
done

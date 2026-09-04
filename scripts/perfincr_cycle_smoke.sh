#!/usr/bin/env bash
set -euo pipefail

if (( $# < 1 || $# > 3 )); then
    echo "usage: $0 <cjc> [workdir] [jobs]" >&2
    exit 2
fi

compiler="$(realpath "$1")"
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
compiler_root="$(dirname "$(dirname "$compiler")")"
node "$script_dir/verifier_artifact_gate.mjs" --root "$compiler_root"
workdir="${2:-$(mktemp -d /tmp/perfincr-cycle.XXXXXX)}"
jobs="${3:-12}"
if [[ -e "$workdir" ]] && [[ -n "$(find "$workdir" -mindepth 1 -maxdepth 1 -print -quit)" ]]; then
    echo "workdir must be absent or empty: $workdir" >&2
    exit 2
fi
mkdir -p "$workdir"/{a,b,main,build}

cat > "$workdir/a/a.cj" <<'EOF'
package cycle::a

import cycle::b.*

public func Seed(): Int64 { 40 }
public func Answer(): Int64 { Bump() + 1 }
EOF

cat > "$workdir/b/b.cj" <<'EOF'
package cycle::b

import cycle::a.*

public func Bump(): Int64 { Seed() + 1 }
EOF

cat > "$workdir/main/main.cj" <<'EOF'
package cycle

import cycle::a.*

main(): Unit { println(Answer()) }
EOF

compile_group() {
    local phase="$1"
    (
        cd "$workdir"
        "$compiler" -j "$jobs" --incremental-compile --experimental \
            --package a --package b --module-name cycle --output-type=staticlib \
            -o build/libcycle.a
    ) 2>&1 | tee "$workdir/$phase.group.log"
}

compile_main() {
    local phase="$1"
    (
        cd "$workdir"
        "$compiler" -j "$jobs" --incremental-compile --experimental \
            main/main.cj --module-name cycle --import-path build -L build -l cycle \
            --set-runtime-rpath -o build/app
    ) 2>&1 | tee "$workdir/$phase.main.log"
    "$workdir/build/app" | tee "$workdir/$phase.run.log"
}

snapshot() {
    local phase="$1"
    (
        cd "$workdir"
        find . -type f \( -path './.cached/*' -o -path './build/*' \) \
            -printf '%p\t%T@\t%s\n' | sort
    ) > "$workdir/$phase.files.tsv"
    sha256sum "$workdir/build/libcycle.a" "$workdir/build/app" > "$workdir/$phase.sha256"
}

echo '=== PHASE clean ==='
compile_group clean
compile_main clean
snapshot clean

echo '=== PHASE no-change ==='
compile_group no-change
compile_main no-change
snapshot no-change

echo '=== PHASE changed-cycle-member ==='
sed -i 's/{ 40 }/{ 50 }/' "$workdir/a/a.cj"
compile_group changed
compile_main changed
snapshot changed

clean_output="$(tr -d '\r\n' < "$workdir/clean.run.log")"
no_change_output="$(tr -d '\r\n' < "$workdir/no-change.run.log")"
changed_output="$(tr -d '\r\n' < "$workdir/changed.run.log")"
[[ "$clean_output" == 42 ]]
[[ "$no_change_output" == 42 ]]
[[ "$changed_output" == 52 ]]

echo "CYCLE_CLEAN_OUTPUT=$clean_output"
echo "CYCLE_NO_CHANGE_OUTPUT=$no_change_output"
echo "CYCLE_CHANGED_OUTPUT=$changed_output"
echo "CYCLE_SMOKE=pass"
echo "EVIDENCE_DIR=$workdir"

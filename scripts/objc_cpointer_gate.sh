#!/usr/bin/env bash
# Real compiler front-end fixtures; the stub packages do not validate Darwin execution.
set -eu
ulimit -c 0
compiler=$(realpath "${1:?compiler ELF}")
work=$(realpath -m "${2:?evidence directory}")
script_dir=$(cd "$(dirname "$0")" && pwd)
fixtures="$script_dir/objc_cpointer_fixtures"
test_filter=${3:-.*}
: "${CANGJIE_HOME:?private SDK required}"
mkdir -p "$work/import/objc" "$work/source"
cp "$fixtures/"*.cj "$work/source/"
sha256sum "$compiler" "$work/source/"*.cj > "$work/inputs.sha256"
uptime > "$work/load-before"
taskset -pc $$ > "$work/cpus"
compile_stub() {
    local name=$1
    set +e
    "$compiler" "$work/source/$name.cj" --import-path "$work/import" \
        --output-type=staticlib --output-dir "$work/import/objc" -o "$name.a" \
        --diagnostic-format=noColor > "$work/$name.log" 2>&1
    local rc=$?
    echo "$rc" > "$work/$name.rc"
    set -e
    return "$rc"
}
compile_stub internal
compile_stub lang
compile_fixture() {
    local name=$1
    mkdir -p "$work/$name"
    set +e
    "$compiler" "$work/source/$name.cj" --import-path "$work/import" \
        --output-type=staticlib --emit-chir=raw --dump-ast --diagnostic-format=noColor \
        -o "$work/$name/result" > "$work/$name/compiler.log" 2>&1
    echo "$?" > "$work/$name/compiler.rc"
}
for name in cpointer mirror impl strings negative control; do compile_fixture "$name" & done
wait
uptime > "$work/load-after"

python3 "$script_dir/objc_cpointer_assert.py" "$work" --filter "$test_filter"

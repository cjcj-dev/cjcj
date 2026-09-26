#!/usr/bin/env bash
# Real compiler front-end fixture. The stub packages do not validate Darwin execution.
set -eu
ulimit -c 0
compiler=$(realpath "${1:?compiler ELF}")
work=$(realpath -m "${2:?evidence directory}")
script_dir=$(cd "$(dirname "$0")" && pwd)
fixtures="$script_dir/objc_init_nil_fixtures"
test_filter=${3:-.*}
: "${CANGJIE_HOME:?private SDK required}"
mkdir -p "$work/import/objc" "$work/source"
cp "$fixtures/"*.cj "$work/source/"
sha256sum "$compiler" "$work/source/"*.cj > "$work/inputs.sha256"
uptime > "$work/load-before"
taskset -pc $$ > "$work/cpus" || true
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
sha256sum "$work/import/objc/"*.cjo >> "$work/inputs.sha256"
mkdir -p "$work/mirror"
set +e
(cd "$work/mirror" && "$compiler" "$work/source/mirror.cj" --import-path "$work/import" \
    --output-type=staticlib --emit-chir=raw --dump-ast --diagnostic-format=noColor \
    -o "$work/mirror/result") > "$work/mirror/compiler.log" 2>&1
echo "$?" > "$work/mirror/compiler.rc"
set -e
uptime > "$work/load-after"
python3 "$script_dir/objc_init_nil_assert.py" "$work" --filter "$test_filter"

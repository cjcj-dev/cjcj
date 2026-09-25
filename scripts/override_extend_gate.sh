#!/usr/bin/env bash
set -eu
ulimit -c 0
compiler=$(realpath "${1:?compiler ELF}")
work=$(realpath -m "${2:?evidence directory}")
fixtures=$(cd "$(dirname "$0")/override_extend_fixtures" && pwd)
mkdir -p "$work"
sha256sum "$compiler" "$fixtures/"*.cj > "$work/inputs.sha256"
uptime > "$work/load-before"
taskset -pc $$ > "$work/cpus"
run_case() {
    local n=$1
    mkdir -p "$work/$n/import" "$work/$n/main"
    set +e
    "$compiler" "$fixtures/dep$n.cj" --output-type=staticlib -O2 \
        --output-dir "$work/$n/import" -o "dep$n.a" --diagnostic-format=noColor \
        > "$work/$n/dependency.log" 2>&1
    local dep_rc=$?
    echo "$dep_rc" > "$work/$n/dependency.rc"
    if [ "$dep_rc" = 0 ]; then
        (cd "$work/$n/main" && "$compiler" "$fixtures/main$n.cj" -O2 \
            --import-path "$work/$n/import" -L "$work/$n/import" -l"dep$n" \
            --emit-chir=raw --dump-chir --diagnostic-format=noColor -o "$work/$n/main/result") \
            > "$work/$n/compiler.log" 2>&1
        echo "$?" > "$work/$n/compiler.rc"
    fi
}
run_case 02 &
run_case 03 &
wait
mkdir -p "$work/control"
set +e
(cd "$work/control" && "$compiler" "$fixtures/control.cj" --emit-chir=raw --dump-chir -O2 -o result) \
    > "$work/control/compiler.log" 2>&1
echo "$?" > "$work/control/compiler.rc"
uptime > "$work/load-after"

#!/usr/bin/env bash
set -euo pipefail

readonly REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
readonly CJC="${REPO_ROOT}/target/release/bin/cangjie_compiler::cjc"
readonly REAL_MARKER="[real-pipeline] lowered package 'app' via real AST2CHIR"

export CANGJIE_HOME=/root/.cjv/toolchains/nightly-1.1.0-alpha.20260331010029
export LD_LIBRARY_PATH="${CANGJIE_HOME}/third_party/llvm/lib:${CANGJIE_HOME}/runtime/lib/linux_x86_64_cjnative:${CANGJIE_HOME}/tools/lib:${LD_LIBRARY_PATH:-}"

fail() {
    printf 'XPKG-FAIL %s\n' "$1"
    exit 1
}

[[ -x "$CJC" ]] || fail "missing self-host cjc at ${CJC}"
[[ -d "$CANGJIE_HOME" ]] || fail "missing CANGJIE_HOME at ${CANGJIE_HOME}"

tmpdir="$(mktemp -d)"
trap 'rm -rf "$tmpdir"' EXIT

mkdir -p "$tmpdir/lib" "$tmpdir/app" "$tmpdir/facade" "$tmpdir/out"

cat >"$tmpdir/lib/lib.cj" <<'EOF'
package lib

public func add(a:Int64,b:Int64):Int64 {
    return a + b
}
EOF

cat >"$tmpdir/app/app.cj" <<'EOF'
package app

import lib.add

main(): Int64 {
    return add(2,3)
}
EOF

cat >"$tmpdir/facade/app.cj" <<'EOF'
package app

public func add(a:Int64,b:Int64):Int64 {
    return a + b
}

main(): Int64 {
    return add(2,3)
}
EOF

readonly REAL_EXE="$tmpdir/out/xpkg_real"
readonly FACADE_EXE="$tmpdir/out/xpkg_facade"
readonly REAL_STDOUT="$tmpdir/real.compile.stdout"
readonly REAL_STDERR="$tmpdir/real.compile.stderr"
readonly FACADE_STDOUT="$tmpdir/facade.compile.stdout"
readonly FACADE_STDERR="$tmpdir/facade.compile.stderr"
readonly REAL_RUN_STDOUT="$tmpdir/real.run.stdout"
readonly REAL_RUN_STDERR="$tmpdir/real.run.stderr"
readonly FACADE_RUN_STDOUT="$tmpdir/facade.run.stdout"
readonly FACADE_RUN_STDERR="$tmpdir/facade.run.stderr"

real_cmd=("$CJC" -p "$tmpdir/lib" "$tmpdir/app" -o "$REAL_EXE" --set-runtime-rpath)
facade_cmd=("$CJC" "$tmpdir/facade/app.cj" -o "$FACADE_EXE" --set-runtime-rpath)
real_invocation="CJ_REAL_PIPELINE=1 CJ_REAL_PIPELINE_VERBOSE=1"
for arg in "${real_cmd[@]}"; do
    real_invocation+=" $(printf '%q' "$arg")"
done

set +e
CJ_REAL_PIPELINE=1 CJ_REAL_PIPELINE_VERBOSE=1 "${real_cmd[@]}" >"$REAL_STDOUT" 2>"$REAL_STDERR"
real_compile_status=$?
set -e
[[ "$real_compile_status" -eq 0 ]] || fail "real compile exited ${real_compile_status}; stderr=$(tr '\n' ' ' <"$REAL_STDERR")"

grep -Fq "$REAL_MARKER" "$REAL_STDERR" || fail "missing real-path marker for app"
if grep -F "package 'app'" "$REAL_STDERR" | grep -Fq "falling back"; then
    fail "real pipeline fell back for app"
fi

set +e
"$REAL_EXE" >"$REAL_RUN_STDOUT" 2>"$REAL_RUN_STDERR"
real_run_status=$?
set -e
[[ "$real_run_status" -eq 5 ]] || fail "real executable exited ${real_run_status}, expected 5"

set +e
env -u CJ_REAL_PIPELINE -u CJ_REAL_PIPELINE_VERBOSE "${facade_cmd[@]}" >"$FACADE_STDOUT" 2>"$FACADE_STDERR"
facade_compile_status=$?
set -e
[[ "$facade_compile_status" -eq 0 ]] || fail "facade compile exited ${facade_compile_status}; stderr=$(tr '\n' ' ' <"$FACADE_STDERR")"

set +e
"$FACADE_EXE" >"$FACADE_RUN_STDOUT" 2>"$FACADE_RUN_STDERR"
facade_run_status=$?
set -e
[[ "$facade_run_status" -eq 5 ]] || fail "facade executable exited ${facade_run_status}, expected 5"

printf 'INVOCATION=%s\n' "$real_invocation"
printf 'REAL_EXIT=%s\n' "$real_run_status"
printf 'FACADE_EXIT=%s\n' "$facade_run_status"
printf 'XPKG-REAL-PASS\n'

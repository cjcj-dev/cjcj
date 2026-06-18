#!/usr/bin/env bash
set -euo pipefail

readonly REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
readonly CJC="${REPO_ROOT}/target/release/bin/cangjie_compiler::cjc"

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

mkdir -p "$tmpdir/lib" "$tmpdir/app" "$tmpdir/out"

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

readonly REAL_EXE="$tmpdir/out/xpkg_real"
readonly REAL_STDOUT="$tmpdir/real.compile.stdout"
readonly REAL_STDERR="$tmpdir/real.compile.stderr"
readonly REAL_RUN_STDOUT="$tmpdir/real.run.stdout"
readonly REAL_RUN_STDERR="$tmpdir/real.run.stderr"

real_cmd=("$CJC" -p "$tmpdir/lib" "$tmpdir/app" -o "$REAL_EXE" --set-runtime-rpath)
real_invocation=""
for arg in "${real_cmd[@]}"; do
    if [[ -z "$real_invocation" ]]; then
        real_invocation="$(printf '%q' "$arg")"
    else
        real_invocation+=" $(printf '%q' "$arg")"
    fi
done

set +e
"${real_cmd[@]}" >"$REAL_STDOUT" 2>"$REAL_STDERR"
real_compile_status=$?
set -e
[[ "$real_compile_status" -eq 0 ]] || fail "real compile exited ${real_compile_status}; stderr=$(tr '\n' ' ' <"$REAL_STDERR")"

set +e
"$REAL_EXE" >"$REAL_RUN_STDOUT" 2>"$REAL_RUN_STDERR"
real_run_status=$?
set -e
[[ "$real_run_status" -eq 5 ]] || fail "real executable exited ${real_run_status}, expected 5"

printf 'INVOCATION=%s\n' "$real_invocation"
printf 'REAL_EXIT=%s\n' "$real_run_status"
printf 'XPKG-REAL-PASS\n'

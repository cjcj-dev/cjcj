#!/usr/bin/env bash
# Selected-shell contract for build/lib/srcbuild_git.sh.
# Invoke with the shell under test: "$BASH_UNDER_TEST" build/test/srcbuild_git_shell_contract.sh
# Bash 3.2 compatible: no associative arrays, no empty @ expansion.
set -u

script_dir=$(cd "$(dirname "$0")" && pwd)
repo_root=$(cd "$script_dir/../.." && pwd)
helper=${SRCBUILD_GIT_SH:-$repo_root/build/lib/srcbuild_git.sh}
fetch_sources=${FETCH_SOURCES_SH:-$repo_root/ci/platform_tuples/fetch_sources.sh}
skip_fetch_sources=${SKIP_FETCH_SOURCES:-0}
fails=0
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

echo "BASH_VERSION=$BASH_VERSION"
echo "BASH_PATH=$BASH"
echo "HELPER=$helper"

fail_assert() {
    echo "ASSERT_FAIL name=$1 detail=$2"
    fails=$((fails + 1))
}

pass_assert() {
    echo "ASSERT_PASS name=$1"
}

git_identity() {
    git -c user.name=fixture -c user.email=fixture@example.invalid "$@"
}

make_repo() {
    local name=$1 file=$2 body=$3
    local src=$work/src-$name bare=$work/bare-$name
    mkdir -p "$(dirname "$src/$file")"
    printf '%s\n' "$body" > "$src/$file"
    git init "$src" >/dev/null
    git -C "$src" add "$file"
    git_identity -C "$src" commit -m fixture >/dev/null
    git -C "$src" rev-parse HEAD
    git clone --bare "$src" "$bare" >/dev/null
}

init_checkout() {
    local dest=$1 url=$2
    git init "$dest" >/dev/null
    git -C "$dest" remote add origin "$url"
}

run_fetch() {
    local dest=$1 url=$2 sha=$3 mirrors=${4-} require=${5-}
    local out=$work/fetch.out err=$work/fetch.err trace=$work/fetch.trace
    : >"$out"
    : >"$err"
    : >"$trace"
    (
        set -euo pipefail
        # shellcheck disable=SC1090
        source "$helper"
        if [ -n "$mirrors" ]; then
            CJCJ_SRCBUILD_SOURCE_MIRRORS=$mirrors
            export CJCJ_SRCBUILD_SOURCE_MIRRORS
        else
            unset CJCJ_SRCBUILD_SOURCE_MIRRORS
        fi
        if [ -n "$require" ]; then
            CJCJ_SRCBUILD_REQUIRE_MIRRORS=$require
            export CJCJ_SRCBUILD_REQUIRE_MIRRORS
        else
            unset CJCJ_SRCBUILD_REQUIRE_MIRRORS
        fi
        export GIT_TRACE=$trace
        srcbuild_git_fetch "$dest" "$url" "$sha"
    ) >"$out" 2>"$err"
    fetch_rc=$?
}

llvm_sha=$(make_repo llvm llvm/include/llvm/Transforms/Scalar/ReflectionInfo.h 'enum EnumReflectionType {
  ERT_NONE,
};')
compiler_sha=$(make_repo compiler schema/ModuleFormat.fbs 'table Fixture {}')
flatbuffers_sha=$(make_repo flatbuffers CMakeLists.txt 'cmake_minimum_required(VERSION 3.16)')
llvm_bare=$work/bare-llvm
compiler_bare=$work/bare-compiler
flatbuffers_bare=$work/bare-flatbuffers
canonical='https://example.invalid/a?[b]*.git'

checkout=$work/checkout-empty
init_checkout "$checkout" "file://$llvm_bare"
run_fetch "$checkout" "file://$llvm_bare" "$llvm_sha"
echo "ASSERT_REACHED name=fetch_head"
got=$(git -C "$checkout" rev-parse FETCH_HEAD 2>/dev/null || true)
if [ "$fetch_rc" = 0 ] && [ "$got" = "$llvm_sha" ] \
    && grep -F "SOURCE-MIRROR none, falling back to file://$llvm_bare" "$work/fetch.err" >/dev/null \
    && grep -F 'fetch' "$work/fetch.trace" >/dev/null \
    && ! grep -F 'local: -A' "$work/fetch.err" >/dev/null \
    && ! grep -F 'entries[@]' "$work/fetch.err" >/dev/null; then
    pass_assert fetch_head
else
    fail_assert fetch_head "rc=$fetch_rc got=$got"
    echo "---- fetch.err ----"
    cat "$work/fetch.err"
fi

if [ "$skip_fetch_sources" = 0 ]; then
    tuple=$work/tuple
    mkdir -p "$tuple"
    (
        set -euo pipefail
        unset CJCJ_SRCBUILD_SOURCE_MIRRORS CJCJ_SRCBUILD_REQUIRE_MIRRORS
        export TUPLE_ROOT=$tuple
        export LLVM_URL="file://$llvm_bare" LLVM_SHA=$llvm_sha
        export CANGJIE_COMPILER_URL="file://$compiler_bare" CANGJIE_COMPILER_SHA=$compiler_sha
        export FLATBUFFERS_URL="file://$flatbuffers_bare" FLATBUFFERS_SHA=$flatbuffers_sha
        GIT_TRACE=$work/sources.trace "$BASH" "$fetch_sources"
    ) >"$work/sources.out" 2>"$work/sources.err"
    sources_rc=$?
    echo "ASSERT_REACHED name=fetch_sources_head"
    got_llvm=$(git -C "$tuple/llvm-project" rev-parse HEAD 2>/dev/null || true)
    got_compiler=$(git -C "$tuple/cangjie-compiler" rev-parse HEAD 2>/dev/null || true)
    got_flat=$(git -C "$tuple/flatbuffers" rev-parse HEAD 2>/dev/null || true)
    if [ "$sources_rc" = 0 ] && [ "$got_llvm" = "$llvm_sha" ] \
        && [ "$got_compiler" = "$compiler_sha" ] && [ "$got_flat" = "$flatbuffers_sha" ] \
        && grep -F 'SOURCE-MIRROR none, falling back to' "$work/sources.out" >/dev/null \
        && ! grep -F 'local: -A' "$work/sources.out" "$work/sources.err" >/dev/null \
        && ! grep -F 'entries[@]' "$work/sources.out" "$work/sources.err" >/dev/null \
        && test -f "$tuple/cangjie-compiler/schema/ModuleFormat.fbs" \
        && test -f "$tuple/flatbuffers/CMakeLists.txt"; then
        pass_assert fetch_sources_head
    else
        fail_assert fetch_sources_head "rc=$sources_rc llvm=$got_llvm compiler=$got_compiler flat=$got_flat"
        echo "---- sources.out ----"
        cat "$work/sources.out"
        echo "---- sources.err ----"
        cat "$work/sources.err"
    fi
fi

hit=$work/checkout-hit
init_checkout "$hit" "$canonical"
run_fetch "$hit" "$canonical" "$llvm_sha" "$canonical=file://$llvm_bare"
echo "ASSERT_REACHED name=mirror_hit"
got=$(git -C "$hit" rev-parse FETCH_HEAD 2>/dev/null || true)
origin=$(git -C "$hit" remote get-url origin 2>/dev/null || true)
if [ "$fetch_rc" = 0 ] && [ "$got" = "$llvm_sha" ] && [ "$origin" = "$canonical" ] \
    && grep -F "file://$llvm_bare" "$work/fetch.trace" >/dev/null \
    && ! grep -F "fetch $canonical" "$work/fetch.trace" >/dev/null; then
    pass_assert mirror_hit
else
    fail_assert mirror_hit "rc=$fetch_rc got=$got origin=$origin"
    echo "---- fetch.trace ----"
    cat "$work/fetch.trace"
    echo "---- fetch.err ----"
    cat "$work/fetch.err"
fi

bad=$work/checkout-bad
init_checkout "$bad" "file://$llvm_bare"
run_fetch "$bad" "file://$llvm_bare" "$llvm_sha" 'not-a-mapping'
echo "ASSERT_REACHED name=invalid_message"
if [ "$fetch_rc" != 0 ] \
    && grep -F 'invalid CJCJ_SRCBUILD_SOURCE_MIRRORS entry: not-a-mapping' "$work/fetch.err" >/dev/null \
    && ! grep -F 'local: -A' "$work/fetch.err" >/dev/null; then
    pass_assert invalid_message
else
    fail_assert invalid_message "rc=$fetch_rc"
    echo "---- fetch.err ----"
    cat "$work/fetch.err"
fi

dup_url='https://example.invalid/a?.git'
run_fetch "$bad" "$dup_url" "$llvm_sha" "$dup_url=file://$llvm_bare;$dup_url=file://$compiler_bare"
echo "ASSERT_REACHED name=duplicate_message"
if [ "$fetch_rc" != 0 ] \
    && grep -F "duplicate CJCJ_SRCBUILD_SOURCE_MIRRORS source: $dup_url" "$work/fetch.err" >/dev/null \
    && ! grep -F 'local: -A' "$work/fetch.err" >/dev/null; then
    pass_assert duplicate_message
else
    fail_assert duplicate_message "rc=$fetch_rc"
    echo "---- fetch.err ----"
    cat "$work/fetch.err"
fi

run_fetch "$bad" 'https://example.invalid/missing.git' deadbeef '' 1
echo "ASSERT_REACHED name=require_mirrors"
if [ "$fetch_rc" != 0 ] \
    && grep -F 'source mirror required by CJCJ_SRCBUILD_REQUIRE_MIRRORS=1' "$work/fetch.err" >/dev/null; then
    pass_assert require_mirrors
else
    fail_assert require_mirrors "rc=$fetch_rc"
    echo "---- fetch.err ----"
    cat "$work/fetch.err"
fi

q='https://example.invalid/a?.git'
star='https://example.invalid/a*.git'
bracket='https://example.invalid/a[b].git'
eq='https://example.invalid/eq.git'
mappings="$q=file:///mirror-q;$star=file:///mirror-star;$bracket=file:///mirror-bracket;$eq=file:///mirror?x=1"
(
    set -euo pipefail
    # shellcheck disable=SC1090
    source "$helper"
    CJCJ_SRCBUILD_SOURCE_MIRRORS=$mappings
    export CJCJ_SRCBUILD_SOURCE_MIRRORS
    unset CJCJ_SRCBUILD_REQUIRE_MIRRORS
    srcbuild_git_resolve_source_mirror "$q"
    srcbuild_git_resolve_source_mirror "$star"
    srcbuild_git_resolve_source_mirror "$bracket"
    srcbuild_git_resolve_source_mirror "$eq"
) >"$work/glob.out" 2>"$work/glob.err"
glob_rc=$?
echo "ASSERT_REACHED name=glob_exact"
got_q=$(sed -n '1p' "$work/glob.out")
got_star=$(sed -n '2p' "$work/glob.out")
got_bracket=$(sed -n '3p' "$work/glob.out")
got_eq=$(sed -n '4p' "$work/glob.out")
if [ "$glob_rc" = 0 ] && [ "$got_q" = 'file:///mirror-q' ] && [ "$got_star" = 'file:///mirror-star' ] \
    && [ "$got_bracket" = 'file:///mirror-bracket' ] && [ "$got_eq" = 'file:///mirror?x=1' ] \
    && ! grep -F 'duplicate CJCJ_SRCBUILD_SOURCE_MIRRORS source' "$work/glob.err" >/dev/null; then
    pass_assert glob_exact
else
    fail_assert glob_exact "rc=$glob_rc q=$got_q star=$got_star bracket=$got_bracket eq=$got_eq"
    echo "---- glob.err ----"
    cat "$work/glob.err"
fi

echo "CONTRACT_FAILS=$fails"
exit "$fails"

#!/usr/bin/env bash
# Real frontend -> bitcode -> independent LLVM DataLayout/IR assertions.
# Compiler is copied to a private frontend entry; no SDK executable is replaced.
set -euo pipefail
ulimit -c 0
repo=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
compiler=${1:?candidate compiler}
sdk=${2:?host SDK}
llvm_library=${3:?paired libLLVM}
llvm_repo=${4:?paired LLVM source}
runtime_repo=${5:?paired runtime source}
work=${6:?evidence directory}
source "$repo/ci/llvm_pin.env"
source "$repo/ci/runtime_pin.env"
mkdir -p "$work"
work=$(cd "$work" && pwd)
mkdir -p "$work/frontend"
cp "$compiler" "$work/frontend/cjcj-stage1"
cmp "$compiler" "$work/frontend/cjcj-stage1"
ln -sfn cjcj-stage1 "$work/frontend/cjc-frontend"
compiler="$work/frontend/cjc-frontend"
# The source check includes the generated Cangjie file, not just the LLVM copy.
bash "$repo/ci/check-llvm-runtime-abi.sh" --llvm-repo "$llvm_repo" --llvm-ref "$LLVM_SHA" \
    --runtime-repo "$runtime_repo" --runtime-ref "$RUNTIME_REF" > "$work/pairing.log" 2>&1
header="$work/CangjieRuntimeLayout.h"
git -C "$llvm_repo" show "$LLVM_SHA:llvm/include/llvm/CodeGen/CangjieRuntimeLayout.h" > "$header"
mkdir -p "$work/core"
git -C "$runtime_repo" archive "$RUNTIME_REF" stdlib/libs/std/core | tar -x -C "$work/core"
core="$work/core/stdlib/libs/std/core"
cp "$repo/tests/runtime_layout/raw.cj" "$core/layout_contract.cj"
# The compiler uses the same paired LLVM dylib as the independent reader. Host
# runtime and std stay together; the generated target code is not executed here.
export CANGJIE_HOME="$sdk"
LD_LIBRARY_PATH="$(dirname "$llvm_library"):$sdk/runtime/lib/linux_x86_64_cjnative:$sdk/lib/linux_x86_64_cjnative:$sdk/third_party/llvm/lib:$sdk/tools/lib"
export LD_LIBRARY_PATH
export cjHeapSize=32GB
jobs=$(nproc)
uptime > "$work/uptime-before.txt"
sha256sum "$compiler" "$llvm_library" "$header" \
    "$sdk/runtime/lib/linux_x86_64_cjnative/libcangjie-runtime.so" \
    "$sdk/runtime/lib/linux_x86_64_cjnative/libboundscheck.so" > "$work/inputs.sha256"
start=$SECONDS
# One compiler process per lane arm; core and object fixtures use independent
# modules but run sequentially to keep the four-arm memory envelope bounded.
rc=0
for surface in objects arrays; do
    mkdir -p "$work/$surface"
    opt=-O0
    args=("$repo/tests/runtime_layout/layout.cj" -g)
    if [[ $surface == arrays ]]; then opt=-O2; args=(-p "$core" --no-sub-pkg --no-prelude); fi
    compile_rc=0
    timeout 900 "$compiler" "${args[@]}" --output-type=staticlib "$opt" --apc=1 --jobs "$jobs" \
        -o "$work/$surface/layout.bc" > "$work/$surface/compile.log" 2>&1 || compile_rc=$?
    printf '%s\n' "$compile_rc" > "$work/$surface/compile.rc"
    verify_rc=NOT_RUN
    if [[ $compile_rc == 0 ]]; then
        sha256sum "$work/$surface/layout.bc" > "$work/$surface/bitcode.sha256"
        verify_rc=0
        python3 "$repo/ci/verify-codegen-runtime-layout.py" --surface "$surface" \
            --llvm-library "$llvm_library" --header "$header" --bitcode "$work/$surface/layout.bc" \
            --result "$work/$surface/result.json" > "$work/$surface/verify.log" 2>&1 || verify_rc=$?
    fi
    printf '%s\n' "$verify_rc" > "$work/$surface/verify.rc"
    printf 'LAYOUT_IR surface=%s compile_rc=%s verify_rc=%s\n' "$surface" "$compile_rc" "$verify_rc"
    [[ $compile_rc == 0 && $verify_rc == 0 ]] || rc=1
done
uptime > "$work/uptime-after.txt"
printf 'rc=%s wall=%s jobs=%s\n' "$rc" "$((SECONDS-start))" "$jobs" > "$work/result.txt"
exit "$rc"

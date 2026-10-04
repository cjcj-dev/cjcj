#!/usr/bin/env bash
# Shared ten-payload publisher for GHA and the kkk2 depot.
# Caller supplies REPO_ROOT, LLVM_SHA, CANGJIE_COMPILER_SHA and CJCJ_FIXED_LLVM_DIR.
publish_fixed_tuple_to_depot() {
    local depot_root=${1:-${CJCJ_LLVM_DEPOT_ROOT:-/root/llvmdepot}}
    local depot="$depot_root/$LLVM_SHA/$CANGJIE_COMPILER_SHA"
    local tuple="$depot/fixed-llc"
    local payload recipe_sha
    local platform=${TUPLE_PLATFORM:-linux_x86_64} linker=ld.lld
    case "$platform" in
        linux_x86_64) ;;
        darwin_aarch64|darwin_x86_64) linker=ld64.lld;;
        *) echo "unsupported static tuple platform: $platform" >&2; return 1;;
    esac
    source "$REPO_ROOT/ci/bootstrap/host_tools.sh"
    local -a payloads=(llc.gz opt.gz "$linker.gz" cjselfhost_llvmshim.o llvm-tools.manifest)
    [[ -n ${LLVM_SHA:-} && -n ${CANGJIE_COMPILER_SHA:-} ]] || return 1
    recipe_sha=$(git -C "$REPO_ROOT" rev-parse HEAD) || return 1
    mkdir -p "$tuple" "$depot/bin" "$depot/lib" || return 1
    for payload in "${payloads[@]}"; do
        cp -- "$CJCJ_FIXED_LLVM_DIR/$payload" "$tuple/$payload" || return 1
    done
    for payload in llc opt "$linker"; do
        gzip -dc "$tuple/$payload.gz" > "$depot/bin/$payload" || return 1
        chmod +x "$depot/bin/$payload" || return 1
    done
    {
        printf 'PLATFORM=%s\n' "$platform"
        printf 'LLVM_SHA=%s\n' "$LLVM_SHA"
        printf 'CANGJIE_COMPILER_SHA=%s\n' "$CANGJIE_COMPILER_SHA"
        printf 'RECIPE_CJCJ_SHA=%s\n' "$recipe_sha"
        printf 'DEPOT_ROLE=byte-identical mirror\n'
    } > "$depot/MANIFEST" || return 1
    cp -- "$depot/MANIFEST" "$depot/lib/STATIC_LLVM.txt" || return 1
    (
        cd "$depot" || exit 1
        host_sha256sum -- "./MANIFEST" "./bin/llc" "./bin/opt" "./bin/$linker" "./lib/STATIC_LLVM.txt" \
            "./fixed-llc/llc.gz" "./fixed-llc/opt.gz" "./fixed-llc/$linker.gz" \
            "./fixed-llc/cjselfhost_llvmshim.o" "./fixed-llc/llvm-tools.manifest" > SHA256SUMS
    ) || return 1
    echo "published fixed LLVM tuple to depot $depot"
}


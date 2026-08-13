#!/usr/bin/env bash
# Check the three source-level constants shared by the LLVM backend and runtime.
# Missing source, an unresolvable ref, or an unreadable constant is a failure.

set -uo pipefail

usage() {
    cat <<'EOF'
usage: check-llvm-runtime-abi.sh \
  --llvm-repo PATH --llvm-ref REF \
  --runtime-repo PATH --runtime-ref REF
EOF
}

llvm_repo=
llvm_ref=
runtime_repo=
runtime_ref=

while (($# > 0)); do
    case "$1" in
        --llvm-repo)
            if (($# < 2)) || [[ -z $2 ]]; then
                printf 'ABI_PAIR=INVALID_ARGUMENT missing_value=%s\n' "$1" >&2
                exit 2
            fi
            llvm_repo=$2
            shift 2
            ;;
        --llvm-ref)
            if (($# < 2)) || [[ -z $2 ]]; then
                printf 'ABI_PAIR=INVALID_ARGUMENT missing_value=%s\n' "$1" >&2
                exit 2
            fi
            llvm_ref=$2
            shift 2
            ;;
        --runtime-repo)
            if (($# < 2)) || [[ -z $2 ]]; then
                printf 'ABI_PAIR=INVALID_ARGUMENT missing_value=%s\n' "$1" >&2
                exit 2
            fi
            runtime_repo=$2
            shift 2
            ;;
        --runtime-ref)
            if (($# < 2)) || [[ -z $2 ]]; then
                printf 'ABI_PAIR=INVALID_ARGUMENT missing_value=%s\n' "$1" >&2
                exit 2
            fi
            runtime_ref=$2
            shift 2
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            printf 'ABI_PAIR=INVALID_ARGUMENT argument=%q\n' "$1" >&2
            usage >&2
            exit 2
            ;;
    esac
done

for required in llvm_repo llvm_ref runtime_repo runtime_ref; do
    if [[ -z ${!required} ]]; then
        printf 'ABI_PAIR=INVALID_ARGUMENT missing=%s\n' "$required" >&2
        exit 2
    fi
done

resolve_ref() {
    local repo=$1
    local ref=$2

    git -C "$repo" rev-parse --verify "${ref}^{commit}" 2>/dev/null
}

if ! llvm_commit=$(resolve_ref "$llvm_repo" "$llvm_ref"); then
    printf 'ABI_PAIR=UNRESOLVABLE side=llvm ref=%s\n' "$llvm_ref"
    exit 2
fi
if ! runtime_commit=$(resolve_ref "$runtime_repo" "$runtime_ref"); then
    printf 'ABI_PAIR=UNRESOLVABLE side=runtime ref=%s\n' "$runtime_ref"
    exit 2
fi

show_source() {
    local repo=$1
    local commit=$2
    local path=$3

    git -C "$repo" show "${commit}:${path}" 2>/dev/null
}

llvm_barriers=$(show_source "$llvm_repo" "$llvm_commit" \
    llvm/lib/CodeGen/CJBarrierLowering.cpp)
llvm_asm_printer=$(show_source "$llvm_repo" "$llvm_commit" \
    llvm/lib/CodeGen/AsmPrinter/AsmPrinter.cpp)
runtime_collector=$(show_source "$runtime_repo" "$runtime_commit" \
    runtime/src/Heap/Collector/Collector.h)
runtime_thread_local=$(show_source "$runtime_repo" "$runtime_commit" \
    runtime/src/Mutator/ThreadLocal.h)
runtime_base_object=$(show_source "$runtime_repo" "$runtime_commit" \
    runtime/src/Common/BaseObject.cpp)

llvm_phase=$(sed -nE 's/.*APInt\(32, ([0-9]+)\).*/\1/p' <<<"$llvm_barriers" |
    sort -u | paste -sd, -)
runtime_phase=$(sed -nE 's/.*GC_PHASE_INIT = ([0-9]+).*/\1/p' \
    <<<"$runtime_collector" | sort -u | paste -sd, -)

llvm_mutator_offset=$(sed -nE \
    's/.*MutatorOffsetInCJTLS = AllocBufferOffsetInCJTLS \+ ([0-9]+).*/\1/p' \
    <<<"$llvm_asm_printer" | sort -u | paste -sd, -)
runtime_mutator_offset=$(awk '
    /struct ThreadLocalData[[:space:]]*\{/ { in_struct = 1; next }
    in_struct && /^[[:space:]]*Mutator\*[[:space:]]+mutator;/ {
        print fields * 8
        exit
    }
    in_struct && /^[[:space:]]*[A-Za-z_][^;]*;/ { fields++ }
' <<<"$runtime_thread_local")

llvm_mask_symbol_count=$(awk '
    /getOrInsertGlobal\("g_cjLoadBadMask", I64\)/ { count++ }
    END { print count + 0 }
' <<<"$llvm_barriers")
llvm_mask_load_count=$(awk '
    /CreateLoad\(I64, MaskGV,/ { count++ }
    END { print count + 0 }
' <<<"$llvm_barriers")
runtime_mask_definition_count=$(awk '
    /extern "C" unsigned long g_cjLoadBadMask[[:space:]]*=/ { count++ }
    END { print count + 0 }
' <<<"$runtime_base_object")

failed=0
check_equal() {
    local site=$1
    local compiler_value=$2
    local runtime_value=$3

    if [[ -n $compiler_value && -n $runtime_value && \
          $compiler_value == "$runtime_value" ]]; then
        printf 'ABI_SITE=%s compiler=%s runtime=%s status=OK\n' \
            "$site" "$compiler_value" "$runtime_value"
    else
        printf 'ABI_SITE=%s compiler=%s runtime=%s status=MISMATCH\n' \
            "$site" "${compiler_value:-UNREADABLE}" "${runtime_value:-UNREADABLE}"
        failed=1
    fi
}

check_equal gc_phase_threshold "$llvm_phase" "$runtime_phase"
check_equal cjtls_mutator_offset "$llvm_mutator_offset" "$runtime_mutator_offset"

if [[ $llvm_mask_symbol_count == 1 && $llvm_mask_load_count == 1 && \
      $runtime_mask_definition_count == 1 ]]; then
    printf 'ABI_SITE=load_bad_mask compiler_emit=%s compiler_i64_load=%s runtime_define=%s status=OK\n' \
        "$llvm_mask_symbol_count" "$llvm_mask_load_count" "$runtime_mask_definition_count"
else
    printf 'ABI_SITE=load_bad_mask compiler_emit=%s compiler_i64_load=%s runtime_define=%s status=MISMATCH\n' \
        "$llvm_mask_symbol_count" "$llvm_mask_load_count" "$runtime_mask_definition_count"
    failed=1
fi

if ((failed == 0)); then
    printf 'ABI_PAIR=OK llvm=%s runtime=%s\n' "$llvm_commit" "$runtime_commit"
else
    printf 'ABI_PAIR=MISMATCH llvm=%s runtime=%s\n' "$llvm_commit" "$runtime_commit"
fi
exit "$failed"

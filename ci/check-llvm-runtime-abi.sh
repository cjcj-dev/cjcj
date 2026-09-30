#!/usr/bin/env bash
# Check the generated layout contract shared by the LLVM backend and runtime.
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

# Read both sides at the resolved commits, never from a possibly dirty checkout.
# The runtime generator owns the assertion list and the comparison; do not
# duplicate its layout constants or infer offsets by counting C++ declarations.
work=$(mktemp -d "${TMPDIR:-/tmp}/cjcj-runtime-layout.XXXXXX") || exit 2
trap 'rm -rf "$work"' EXIT
if ! git -C "$runtime_repo" archive "$runtime_commit" runtime | tar -x -C "$work"; then
    printf 'ABI_PAIR=SOURCE_ERROR side=runtime\n'
    exit 2
fi
header="$work/CangjieRuntimeLayout.h"
if ! git -C "$llvm_repo" show \
    "$llvm_commit:llvm/include/llvm/CodeGen/CangjieRuntimeLayout.h" > "$header"; then
    printf 'ABI_PAIR=SOURCE_ERROR side=llvm\n'
    exit 2
fi
if python3 "$work/runtime/tools/generate-runtime-layout.py" --header "$header"; then
    repo=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
    if ! python3 "$repo/ci/generate-codegen-runtime-layout.py" \
        --runtime-root "$work" --header "$header" --check; then
        printf 'ABI_PAIR=CODEGEN_MISMATCH llvm=%s runtime=%s\n' "$llvm_commit" "$runtime_commit"
        exit 1
    fi
    printf 'ABI_PAIR=OK llvm=%s runtime=%s\n' "$llvm_commit" "$runtime_commit"
else
    printf 'ABI_PAIR=MISMATCH llvm=%s runtime=%s\n' "$llvm_commit" "$runtime_commit"
    exit 1
fi

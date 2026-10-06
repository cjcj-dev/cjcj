#!/usr/bin/env bash
# LLVM's configure/build checks consume assertions from the paired runtime pin.
set -euo pipefail
repo=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)

reject() {
    echo "LLVM_RUNTIME_INPUT_ERROR: $*" >&2
    exit 1
}

# Private tuple producers must carry both inputs explicitly. Never interpret an
# inherited RUNTIME_REF as a private request: the default still comes from pin.
private=0
case ${CJCJ_LLVM_RUNTIME_MODE-} in
    '')
        [[ ! ${CJCJ_LLVM_RUNTIME_URL+x} && ! ${CJCJ_LLVM_RUNTIME_SHA+x} ]] \
            || reject 'private URL/SHA require CJCJ_LLVM_RUNTIME_MODE=private'
        # shellcheck disable=SC1091
        source "$repo/ci/runtime_pin.env"
        runtime_url=$RUNTIME_SRC_URL
        runtime_sha=$RUNTIME_REF
        ;;
    private)
        private=1
        [[ ! ${RUNTIME_REF+x} && ! ${RUNTIME_SRC_URL+x} ]] \
            || reject 'do not mix private inputs with RUNTIME_REF/RUNTIME_SRC_URL'
        [[ ${CJCJ_LLVM_RUNTIME_URL-} == https://github.com/cjcj-dev/cangjie-runtime.git ]] \
            || reject 'private runtime requires the approved cjcj-dev HTTPS URL'
        [[ ${CJCJ_LLVM_RUNTIME_SHA-} =~ ^[0-9a-f]{40}$ ]] \
            || reject 'private runtime requires a complete lowercase 40-digit SHA'
        runtime_url=$CJCJ_LLVM_RUNTIME_URL
        runtime_sha=$CJCJ_LLVM_RUNTIME_SHA
        ;;
    *) reject 'CJCJ_LLVM_RUNTIME_MODE must be unset or private' ;;
esac

operation=fetch
case ${1-} in
    --check-input) operation=check; shift ;;
    --verify-checkout) operation=verify; shift ;;
esac
[[ $# == 1 && -n $1 ]] || reject 'expected one paired runtime destination'
dest=$1

verify_clean() {
    local top
    top=$(git -C "$dest" rev-parse --show-toplevel) \
        || reject 'private runtime destination is not a Git worktree'
    [[ $(cd "$dest" && pwd -P) == "$(cd "$top" && pwd -P)" ]] \
        || reject 'private runtime destination must be the Git worktree root'
    [[ -z $(git -C "$dest" status --porcelain --untracked-files=all) ]] \
        || reject 'private runtime checkout is dirty'
}

# Reject a dirty private destination before fetching any tuple source, instead
# of letting checkout silently carry tracked modifications into layout checks.
if [[ $private == 1 && -e $dest ]]; then
    verify_clean
fi
[[ $operation != check ]] || exit 0
if [[ $operation == verify ]]; then
    if [[ $private == 1 ]]; then
        verify_clean
        [[ $(git -C "$dest" rev-parse HEAD) == "$runtime_sha" ]] \
            || reject 'private runtime checkout HEAD differs from requested SHA'
        printf 'LLVM_RUNTIME_IDENTITY mode=private sha=%s source=%s\n' "$runtime_sha" "$(cd "$dest" && pwd -P)"
    fi
    exit 0
fi

# shellcheck disable=SC1091
source "$repo/build/lib/srcbuild_git.sh"
git init "$dest"
srcbuild_git_fetch "$dest" "$runtime_url" "$runtime_sha"
git -C "$dest" checkout --detach FETCH_HEAD
test "$(git -C "$dest" rev-parse HEAD)" = "$runtime_sha"
if [[ $private == 1 ]]; then
    verify_clean
    printf 'LLVM_RUNTIME_IDENTITY mode=private sha=%s source=%s\n' "$runtime_sha" "$(cd "$dest" && pwd -P)"
fi

#!/usr/bin/env bash
# LLVM's configure/build checks consume assertions from the paired runtime pin.
set -euo pipefail
repo=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
# shellcheck disable=SC1091
source "$repo/ci/runtime_pin.env"
# shellcheck disable=SC1091
source "$repo/build/lib/srcbuild_git.sh"
dest=${1:?paired runtime destination}
git init "$dest"
srcbuild_git_fetch "$dest" "$RUNTIME_SRC_URL" "$RUNTIME_REF"
git -C "$dest" checkout --detach FETCH_HEAD
test "$(git -C "$dest" rev-parse HEAD)" = "$RUNTIME_REF"

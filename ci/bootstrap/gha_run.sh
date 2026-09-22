#!/usr/bin/env bash
set -euo pipefail
stage=${1:?stage0|stage1}
root=${GITHUB_WORKSPACE:?}
: "${CJCJ_BOOTSTRAP_BASE:?}"
: "${CJCJ_BOOTSTRAP_HOST_LLVM_SO:?}"
: "${CJCJ_BOOTSTRAP_HOST_LLVM_SHA256:?}"
: "${CJCJ_BOOTSTRAP_AST_SUPPORT:?}"
: "${CJCJ_BOOTSTRAP_AST_SUPPORT_SHA256:?}"
: "${CJCJ_BOOTSTRAP_COLOUR_TUPLE:?}"
: "${CJCJ_BOOTSTRAP_COLOUR_LLVM_SHA:?}"
: "${CJCJ_BOOTSTRAP_COLOUR_RT:?}"
: "${CJCJ_BOOTSTRAP_HOST_RT:?}"
: "${CJCJ_BOOTSTRAP_CPP_SRC:?}"
: "${CJCJ_BOOTSTRAP_CJCJ_SHA:?}"
export SDK_BUILD="$root/ci/bootstrap/sdk_build.sh"
# bootstrap.sh publishes stage0 to STAGE0_CACHE_ROOT (default /root/stage0depot,
# the kkk2 depot). A hosted runner cannot write /root, and the publish failing
# is fatal, so give it a workspace directory. Nothing restores it between runs.
export STAGE0_CACHE_ROOT="${STAGE0_CACHE_ROOT:-${CANGJIE_WORKSPACE:?}/stage0depot}"
exec bash "$root/ci/bootstrap/bootstrap.sh" \
  --work "${CANGJIE_WORKSPACE:?}/bootstrap-work" \
  --src "$root" \
  --cjcj-sha "$CJCJ_BOOTSTRAP_CJCJ_SHA" \
  --stdsrc "$CANGJIE_WORKSPACE/cangjie_runtime/stdlib" \
  --cpp-src "$CJCJ_BOOTSTRAP_CPP_SRC" \
  --base "$CJCJ_BOOTSTRAP_BASE" \
  --host-llvm-so "$CJCJ_BOOTSTRAP_HOST_LLVM_SO" \
  --host-llvm-sha256 "$CJCJ_BOOTSTRAP_HOST_LLVM_SHA256" \
  --ast-support "$CJCJ_BOOTSTRAP_AST_SUPPORT" \
  --ast-support-sha256 "$CJCJ_BOOTSTRAP_AST_SUPPORT_SHA256" \
  --colour-tuple "$CJCJ_BOOTSTRAP_COLOUR_TUPLE" \
  --colour-llvm-sha "$CJCJ_BOOTSTRAP_COLOUR_LLVM_SHA" \
  --colour-rt "$CJCJ_BOOTSTRAP_COLOUR_RT" \
  --host-rt "$CJCJ_BOOTSTRAP_HOST_RT" \
  --stage "$stage"

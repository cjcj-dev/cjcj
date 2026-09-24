#!/usr/bin/env bash
# Rebuild std with the activated coloured compiler and separate host runtime.
set -euo pipefail
ulimit -c 0
source_root=$(realpath "${1:?runtime checkout}")
active=$(realpath "${2:?activated language SDK}")
artifact=$(realpath "${3:?AST SDK inputs}")
installed=$(realpath "${4:?runtime install root}")
repo=$(cd "$(dirname "$0")/../.." && pwd)
source "$active.env"
python3 "$repo/ci/install_std_sdk_inputs.py" "$artifact" "$CANGJIE_HOME" linux_x86_64_cjnative
export PATH="$CANGJIE_HOME/bin:$CANGJIE_HOME/third_party/llvm/bin:$PATH"
export LD_LIBRARY_PATH="$GC_UNIT_CJC_RUNTIME_LIB_DIR:$CANGJIE_HOME/tools/lib:$CANGJIE_HOME/third_party/llvm/lib"
source "$repo/ci/build_resources.sh"
configure_build_resources "${CJ_HEAP:-96GB}"
export cjHeapSize="$STD_BUILD_HEAP"
sha256sum "$CANGJIE_HOME/bin/cjc" "$GC_UNIT_CJC_RUNTIME_LIB_DIR"/*.so
cd "$source_root/stdlib"
python3 build.py clean
/usr/bin/time -v python3 build.py build -t release -j "$STD_BUILD_JOBS" --target-lib="$CANGJIE_HOME/runtime/lib/linux_x86_64_cjnative"
python3 build.py install --prefix "$installed"

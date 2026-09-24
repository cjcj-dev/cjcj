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
export cjHeapSize=96GB
sha256sum "$CANGJIE_HOME/bin/cjc" "$GC_UNIT_CJC_RUNTIME_LIB_DIR"/*.so
cd "$source_root/stdlib"
python3 build.py clean
python3 build.py build -t release -j "$(getconf _NPROCESSORS_ONLN)" --target-lib="$CANGJIE_HOME/runtime/lib/linux_x86_64_cjnative"
python3 build.py install --prefix "$installed"

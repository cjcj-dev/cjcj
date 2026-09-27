#!/usr/bin/env bash
# Native bootstrap conventions: host_llvm.mjs:12-15 and build_tuple.sh:23-25.
# GNU file utilities keep cache/manifest bytes identical on the two host OSes.
# macOS runners install coreutils, findutils and gnu-tar before bootstrap.
BOOTSTRAP_TOOLS_DIR=$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
HOST_OS=$(uname -s)
HOST_DYNSYM_RULER=readelf--dyn-syms
HOST_LIB_EXT=so
HOST_LLVM_LIBRARY=libLLVM-15.so
HOST_LINKER=ld.lld
HOST_LOADER_VAR=LD_LIBRARY_PATH
HOST_LAYOUT_OS=linux
HOST_SHA256_COMMAND=sha256sum
if [ "$HOST_OS" = Darwin ]; then
  HOST_DYNSYM_RULER=native-nm-defined
  HOST_LIB_EXT=dylib
  HOST_LLVM_LIBRARY=libLLVM.dylib
  HOST_LINKER=ld64.lld
  HOST_LOADER_VAR=DYLD_LIBRARY_PATH
  HOST_LAYOUT_OS=darwin
  HOST_SHA256_COMMAND=gsha256sum
fi
host_file_tool() {
  local tool=$1
  shift
  if [ "$HOST_OS" = Darwin ]; then
    command "g$tool" "$@"
  else
    command "$tool" "$@"
  fi
}
host_sha256sum() { host_file_tool sha256sum "$@"; }
host_readlink() { host_file_tool readlink "$@"; }
host_install() { host_file_tool install "$@"; }
host_sort() { host_file_tool sort "$@"; }
host_tar() { host_file_tool tar "$@"; }
host_find() { host_file_tool find "$@"; }
host_nm() { python3 "$BOOTSTRAP_TOOLS_DIR/host_nm.py" "$@"; }

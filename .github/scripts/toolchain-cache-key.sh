#!/usr/bin/env bash
# Single source of truth for the GHA cache key of a built toolchain.
# Bump the version suffix when toolchain pinning changes (LLVM_MINGW_TAG,
# OPENSSL_VERSION, NCURSES_VERSION, LIBEDIT_TARBALL in src/cangjie_build/
# toolchain/{mingw.py,static_libs.py}).
#
# Usage: toolchain-cache-key.sh <linux-x64|windows-x64>
set -euo pipefail

case "${1:?target required (linux-x64|windows-x64)}" in
  linux-x64)   echo "staticlibs-Linux-ncurses6.5-libedit3.1-v1" ;;
  windows-x64) echo "mingw-Linux-llvm20220906-prebuilt-msvcrt-openssl3.0.9-v2" ;;
  *) echo "unknown target: $1" >&2; exit 1 ;;
esac

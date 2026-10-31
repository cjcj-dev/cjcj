# cangjie_build@d4be4ed3 docs/linux_cross_windows.md:100-116 installs the
# llvm-mingw@20220906 wrappers; clang-target-wrapper.c:98-101 selects
# compiler-rt, libc++ and lld. build.py already supplies the first two.
# MINGW64 clang otherwise selects GNU ld, which fails libc++ delete REL32s.
cmake_minimum_required(VERSION 3.29)
set(CMAKE_LINKER_TYPE LLD)
if("$ENV{RUNTIME_NATIVE_PAIR}" STREQUAL "1")
  include("${CMAKE_CURRENT_LIST_DIR}/native_runtime_toolchain.cmake")
endif()

# Capture each real linker process before an unchanged POST_BUILD check can
# fail and make deletes its output. These launchers never replace the linker.
if(DEFINED ENV{WINDOWS_RUNTIME_CAPTURE_SCRIPT})
  set(CMAKE_C_LINKER_LAUNCHER "$ENV{WINDOWS_RUNTIME_NODE};$ENV{WINDOWS_RUNTIME_CAPTURE_SCRIPT};run;link;--")
  set(CMAKE_CXX_LINKER_LAUNCHER "$ENV{WINDOWS_RUNTIME_NODE};$ENV{WINDOWS_RUNTIME_CAPTURE_SCRIPT};run;link;--")
endif()

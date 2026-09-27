# cangjie_build@d4be4ed3 docs/linux_cross_windows.md:100-116 installs the
# llvm-mingw@20220906 wrappers; clang-target-wrapper.c:88-91 selects
# compiler-rt, libc++ and lld. build.py already supplies the first two.
# MINGW64 clang otherwise selects GNU ld, which fails libc++ delete REL32s.
cmake_minimum_required(VERSION 3.29)
set(CMAKE_LINKER_TYPE LLD)

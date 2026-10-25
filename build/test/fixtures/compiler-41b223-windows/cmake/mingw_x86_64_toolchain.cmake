# Copyright (c) Huawei Technologies Co., Ltd. 2025. All rights reserved.
# This source file is part of the Cangjie project, licensed under Apache-2.0
# with Runtime Library Exception.
#
# See https://cangjie-lang.cn/pages/LICENSE for license information.

set(CMAKE_SYSTEM_NAME Windows)
set(CMAKE_SYSTEM_PROCESSOR x86_64)

# On Windows, x86_64 arch is named "AMD64".
# Unify it to "x86_64" for convenience in later scripts.
if("${CMAKE_HOST_SYSTEM_PROCESSOR}" STREQUAL "AMD64")
    set(CMAKE_HOST_SYSTEM_PROCESSOR x86_64)
endif()

if("${CMAKE_SYSTEM_NAME}" STREQUAL "${CMAKE_HOST_SYSTEM_NAME}")
    set(CMAKE_CROSSCOMPILING OFF)
endif()

if(CANGJIE_TARGET_SYSROOT)
    set(CMAKE_SYSROOT ${CANGJIE_TARGET_SYSROOT})
endif()

set(TRIPLE "x86_64-w64-mingw32")

set(CMAKE_POSITION_INDEPENDENT_CODE ON)
set(WARNINGS_SETTINGS "-Wall ${EXTRA_WARNING_SETTINGS} -Werror -Wdate-time ${CUSTOM_WARNING_SETTINGS}")
set(C_OTHER_FLAGS "-fsigned-char")
set(CXX_OTHER_FLAGS "-Weffc++")
set(OTHER_FLAGS
    "-fno-omit-frame-pointer -pipe -fno-common -fno-strict-aliasing -m64 -fstack-protector-all"
)

# The ld in MinGW toolchain is very slow, especially when linking the debug version. lld is preferred for linking cjc.exe.
# However, the gcc cross compiler doesn't search for the name "lld", but "read-ld", "ld.lld" or "<target>-ld.lld", etc.
# According to collect2's manual, cross-compilers search for linker in the following order:
# - real-ld in the compiler’s search directories (which is specified by -B).
# - target-real-ld in PATH.
# - The file specified in the REAL_LD_FILE_NAME configuration macro, if specified.
# - ld in the compiler’s search directories.
# - target-ld in PATH.
# Hence, we have to make a symlink to lld with the required name, and pass its directory to cross-gcc using "-B".
find_program(lld_path lld${CMAKE_EXECUTABLE_SUFFIX})
if(NOT lld_path)
    message(WARNING "`lld` cannot be found. `ld` will be used to link cjc.exe instead, but it may take much longer.")
else()
    file(MAKE_DIRECTORY ${CMAKE_BINARY_DIR}/toolchain/)
    file(
        CREATE_LINK ${lld_path} ${CMAKE_BINARY_DIR}/toolchain/ld.lld${CMAKE_EXECUTABLE_SUFFIX}
        RESULT result
        SYMBOLIC)
    set(OTHER_FLAGS "${OTHER_FLAGS} -B${CMAKE_BINARY_DIR}/toolchain/ -fuse-ld=lld")
endif()

set(LINK_FLAGS "-Wl,--stack,16777216")
set(STRIP_FLAG "-s")

set(C_FLAGS "${WARNINGS_SETTINGS} ${C_OTHER_FLAGS} ${OTHER_FLAGS}")
set(CPP_FLAGS "${WARNINGS_SETTINGS} ${CXX_OTHER_FLAGS} ${OTHER_FLAGS}")

set(CMAKE_C_FLAGS "${C_FLAGS}")
set(CMAKE_C_FLAGS_RELWITHDEBINFO "-O2 -g")
set(CMAKE_C_FLAGS_RELEASE "-D_FORTIFY_SOURCE=2 -O2")
set(CMAKE_C_FLAGS_DEBUG "-O0 -g")
set(CMAKE_CXX_FLAGS "${CPP_FLAGS}")
set(CMAKE_CXX_FLAGS_RELWITHDEBINFO "-O2 -g")
set(CMAKE_CXX_FLAGS_RELEASE "-D_FORTIFY_SOURCE=2 -O2")
set(CMAKE_CXX_FLAGS_DEBUG "-O0 -g")
set(CMAKE_ASM_FLAGS "${CPP_FLAGS} -x assembler-with-cpp")
set(CMAKE_SHARED_LINKER_FLAGS "-Wl,--no-insert-timestamp")
set(CMAKE_EXE_LINKER_FLAGS "-Wl,--no-insert-timestamp")
if(CMAKE_BUILD_TYPE MATCHES Release)
    set(CMAKE_EXE_LINKER_FLAGS "${CMAKE_EXE_LINKER_FLAGS} ${LINK_FLAGS} ${STRIP_FLAG}")
else()
    set(CMAKE_EXE_LINKER_FLAGS "${CMAKE_EXE_LINKER_FLAGS} ${LINK_FLAGS}")
endif()

# Besides gcc and g++, there are also copies of them with the triple prefix
# in a native MinGW toolchain, like x86_64-w64-mingw32-gcc.
# Use those with the prefix here in order to be compatible with cross-compilation.
set(CMAKE_C_COMPILER x86_64-w64-mingw32-gcc)
set(CMAKE_CXX_COMPILER x86_64-w64-mingw32-g++)
find_program(CMAKE_AR llvm-ar)
find_program(CMAKE_RANLIB llvm-ranlib)
set(LLVM_BUILD_C_COMPILER x86_64-w64-mingw32-gcc)
set(LLVM_BUILD_CXX_COMPILER x86_64-w64-mingw32-g++)

set(LINKER_OPTION_PREFIX "-Wl,")
set(MAKE_SO_STACK_PROTECTOR_OPTION -fstack-protector)

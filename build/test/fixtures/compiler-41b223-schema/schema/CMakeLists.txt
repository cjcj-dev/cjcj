# Copyright (c) Huawei Technologies Co., Ltd. 2025. All rights reserved.
# This source file is part of the Cangjie project, licensed under Apache-2.0
# with Runtime Library Exception.
#
# See https://cangjie-lang.cn/pages/LICENSE for license information.

# Copyright (c) Huawei Technologies Co., Ltd. 2025. All rights reserved.
# This source file is part of the Cangjie project, licensed under Apache-2.0
# with Runtime Library Exception.
#
# See https://cangjie-lang.cn/pages/LICENSE for license information.

# Generate headers with a host-runnable flatc; install the target-platform flatc.
if(NOT FLATC_HOST_EXECUTABLE)
    set(FLATC_HOST_EXECUTABLE "${CMAKE_BINARY_DIR}/bin/flatc${CMAKE_EXECUTABLE_SUFFIX}")
endif()
if(NOT FLATC_TARGET_EXECUTABLE)
    set(FLATC_TARGET_EXECUTABLE "${CMAKE_BINARY_DIR}/bin/flatc${CMAKE_EXECUTABLE_SUFFIX}")
endif()

file(GLOB FLATBUFFERS_SOURCE CONFIGURE_DEPENDS "${CMAKE_CURRENT_SOURCE_DIR}/*.fbs")

set(FLATC_GENERATION_DEPS flatbuffers)
if(CMAKE_CROSSCOMPILING)
    list(APPEND FLATC_GENERATION_DEPS flatbuffers-host)
endif()

set(FLATC_OUTPUTS)
foreach(FILE ${FLATBUFFERS_SOURCE})
    get_filename_component(FILENAME ${FILE} NAME_WE)
    set(FLATC_OUTPUT "${CMAKE_CURRENT_BINARY_DIR}/flatbuffers/${FILENAME}_generated.h")

    add_custom_command(
        OUTPUT ${FLATC_OUTPUT}
        COMMAND ${FLATC_HOST_EXECUTABLE} ARGS --no-warnings -c -o "${CMAKE_CURRENT_BINARY_DIR}/flatbuffers" ${FILE}
        DEPENDS ${FILE} ${FLATC_GENERATION_DEPS} # flatc defined in flatbuffers project: add_executable(flatc..)
        WORKING_DIRECTORY ${CMAKE_CURRENT_SOURCE_DIR})
    list(APPEND FLATC_OUTPUTS ${FLATC_OUTPUT})
endforeach()

set(FLATBUFFERS_INCLUDE_DIR
    ${CMAKE_CURRENT_BINARY_DIR} ${CMAKE_BINARY_DIR}/include
    PARENT_SCOPE)
add_custom_target(CangjieFlatbuffersHeaders DEPENDS ${FLATC_OUTPUTS} ${FLATC_LIBAST_OUTPUTS})

# Install flatbuffers toolchain and runtime support for std.ast / libast consumers.
# flatc ships with cjc; libs-only / cross-libs builds must not overwrite the host SDK flatc.
if(CANGJIE_BUILD_CJC)
    install(PROGRAMS ${FLATC_TARGET_EXECUTABLE} DESTINATION third_party/flatbuffers/bin)
endif()
install(DIRECTORY ${FLATBUFFERS_SOURCE_DIR}/include/flatbuffers
    DESTINATION third_party/flatbuffers/include)
install(
    FILES
        ${CMAKE_CURRENT_SOURCE_DIR}/StdxChirFormat.fbs
        ${CMAKE_CURRENT_SOURCE_DIR}/StdAstFormat.fbs
    DESTINATION schema)

# Rewrite package std.ast -> package flatbuffers and expose API as public for std.ast consumers.
# Glob *.cj at install time (ExternalProject sources are guaranteed present then).
set(FLATBUFFERS_CANGJIE_SRC_DIR "${FLATBUFFERS_SOURCE_DIR}/cangjie")
install(CODE "
    execute_process(
        COMMAND \"${CMAKE_COMMAND}\"
            \"-DSRC_DIR=${FLATBUFFERS_CANGJIE_SRC_DIR}\"
            \"-DDST_DIR=\${CMAKE_INSTALL_PREFIX}/third_party/flatbuffers/cangjie\"
            -P \"${CMAKE_CURRENT_SOURCE_DIR}/install_flatbuffers_cangjie.cmake\"
        RESULT_VARIABLE _fb_cj_install_result)
    if(NOT _fb_cj_install_result EQUAL 0)
        message(FATAL_ERROR \"Failed to install flatbuffers cangjie runtime\")
    endif()
")

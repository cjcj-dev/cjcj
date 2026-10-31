cmake_minimum_required(VERSION 3.16)
project(CangjieNativeRuntimeDependencies LANGUAGES NONE)
# Inputs come from the producing CMake graphs and CJThread install manifest.
# This fills the top-level runtime install's independent-subgraph gap.
foreach(input CJ_THREAD_ARCHIVE CJ_AIO_ARCHIVE CJ_BOUNDS_LIBRARY)
  if(NOT IS_ABSOLUTE "${${input}}" OR NOT EXISTS "${${input}}")
    message(FATAL_ERROR "Missing native runtime install input: ${input}")
  endif()
endforeach()
install(FILES "${CJ_THREAD_ARCHIVE}" "${CJ_AIO_ARCHIVE}"
  DESTINATION "lib/${CJ_RUNTIME_TUPLE}" COMPONENT native-runtime-dependencies)
install(FILES "${CJ_BOUNDS_LIBRARY}"
  DESTINATION "runtime/lib/${CJ_RUNTIME_TUPLE}" COMPONENT native-runtime-dependencies)

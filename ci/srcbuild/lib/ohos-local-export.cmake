# runtime/build.py owns native configuration and clears its build directory.
# Supply its local export selection on the first CMake configure.
if(NOT "$ENV{CJCJ_PARENT_RUNTIME_TOOLCHAIN}" STREQUAL "")
  include("$ENV{CJCJ_PARENT_RUNTIME_TOOLCHAIN}")
endif()
set(GLOBAL_EXPORT_FLAG 0 CACHE STRING "OHOS AArch64 local export map")

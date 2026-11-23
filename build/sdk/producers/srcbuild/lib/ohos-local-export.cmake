# runtime/build.py owns native configuration and clears its build directory.
# Supply its local export selection on the first CMake configure.
if(NOT "$ENV{CJCJ_PARENT_RUNTIME_TOOLCHAIN}" STREQUAL "")
  include("$ENV{CJCJ_PARENT_RUNTIME_TOOLCHAIN}")
endif()
# A normal variable can shadow a cache entry. Reject either kind of conflict
# before setting the cache type; "10" would also select the local map upstream.
if(DEFINED GLOBAL_EXPORT_FLAG AND NOT "${GLOBAL_EXPORT_FLAG}" STREQUAL "0")
  message(FATAL_ERROR "OHOS local export requires GLOBAL_EXPORT_FLAG=0; got '${GLOBAL_EXPORT_FLAG}'")
endif()
if(DEFINED CACHE{GLOBAL_EXPORT_FLAG} AND NOT "$CACHE{GLOBAL_EXPORT_FLAG}" STREQUAL "0")
  message(FATAL_ERROR "OHOS local export requires GLOBAL_EXPORT_FLAG=0; cached '$CACHE{GLOBAL_EXPORT_FLAG}'")
endif()
set(GLOBAL_EXPORT_FLAG "0" CACHE STRING "OHOS AArch64 local export map" FORCE)

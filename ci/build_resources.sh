#!/usr/bin/env bash
# Keep the official host runtime's heap request within its physical-memory limit.
configure_build_resources() {
  local requested=${1:-96GB} memory_kb requested_mb budget_mb
  if [[ -r /proc/meminfo ]]; then
    memory_kb=$(awk '/^MemTotal:/ {print $2}' /proc/meminfo)
  else
    memory_kb=$(( $(sysctl -n hw.memsize) / 1024 ))
  fi
  case "$requested" in
    *GB) requested_mb=$(( ${requested%GB} * 1024 ));;
    *MB) requested_mb=${requested%MB};;
    *KB) requested_mb=$(( (${requested%KB} + 1023) / 1024 ));;
    *) echo "Unsupported build heap: $requested" >&2; return 1;;
  esac
  budget_mb=$(( memory_kb * 3 / 4 / 1024 ))
  (( budget_mb >= 4 && requested_mb >= 4 )) || return 1
  (( requested_mb <= budget_mb )) || requested_mb=$budget_mb
  STD_BUILD_HEAP="${requested_mb}MB"
  # Large hosts retain all build cores. Hosted runners compile one std package
  # at a time so independent compiler heaps cannot exhaust the machine.
  if (( budget_mb >= 96 * 1024 )); then
    STD_BUILD_JOBS=$(getconf _NPROCESSORS_ONLN)
  else
    STD_BUILD_JOBS=1
  fi
  export STD_BUILD_HEAP STD_BUILD_JOBS
  echo "BUILD_RESOURCES MemTotal_kB=$memory_kb requested=$requested heap=$STD_BUILD_HEAP jobs=$STD_BUILD_JOBS" >&2
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  configure_build_resources "${1:-96GB}" || exit $?
  printf 'STD_BUILD_HEAP=%s\nSTD_BUILD_JOBS=%s\n' "$STD_BUILD_HEAP" "$STD_BUILD_JOBS"
fi

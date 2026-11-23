#!/usr/bin/env bash
# Source in the build shell: descendants must inherit the core limit.
# Diagnostics are best effort and must never replace the build/gate exit code.
core_root="$PWD/.platform-ci/runtime-gate-diagnostics"
mkdir -p "$core_root/cores"
{
  printf 'core setup UTC=%s\n' "$(date -u +%FT%TZ)"
  printf 'original core_pattern='; cat /proc/sys/kernel/core_pattern
  ulimit -c unlimited
  printf 'ulimit_rc=%s core_limit=' "$?"; ulimit -c
  # %E encodes the executable path; %p/%t distinguish concurrent children.
  printf '%s/cores/core.%%E.%%p.%%t\n' "$core_root" | sudo -n tee /proc/sys/kernel/core_pattern
  printf 'core_pattern_write_rc=%s\n' "$?"
  printf 'effective core_pattern='; cat /proc/sys/kernel/core_pattern
  printf 'core_uses_pid='; cat /proc/sys/kernel/core_uses_pid
  df -h "$core_root"
} > "$core_root/setup.log" 2>&1
cat "$core_root/setup.log"
unset core_root

#!/usr/bin/env bash
set -eu

log=${1:?usage: qualify_teardown_tools.sh LOG}
mkdir -p "$(dirname "$log")"
: > "$log"
for tool in gdb timeout; do
  if command -v "$tool" >> "$log" 2>&1; then
    if "$tool" --version >> "$log" 2>&1; then
      printf 'GC_UNIT_TEARDOWN_TOOL_OK tool=%s rc=0\n' "$tool" >> "$log"
    else
      rc=$?
      printf 'GC_UNIT_TEARDOWN_TOOL_FAIL tool=%s rc=%s\n' "$tool" "$rc" >> "$log"
      cat "$log"
      exit "$rc"
    fi
  else
    printf 'GC_UNIT_TEARDOWN_TOOL_FAIL tool=%s rc=127 reason=not-found\n' "$tool" >> "$log"
    cat "$log"
    exit 127
  fi
done
cat "$log"

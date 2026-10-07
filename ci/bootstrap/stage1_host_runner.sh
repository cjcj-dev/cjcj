#!/usr/bin/env bash
# Compatibility entry; implementation migrated to zx ESM (cjcj#883).
exec node "$(dirname "$0")/stage1_host_runner.mjs" "$@"

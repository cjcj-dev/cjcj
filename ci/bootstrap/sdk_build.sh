#!/usr/bin/env bash
# Compatibility entry; private SDK implementation migrated to zx ESM (cjcj#883).
exec node "$(dirname "$0")/sdk_build.mjs" "$@"

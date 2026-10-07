#!/usr/bin/env bash
# Compatibility CLI; two-stage implementation migrated to zx ESM (cjcj#883).
exec node "$(dirname "$0")/bootstrap.mjs" "$@"

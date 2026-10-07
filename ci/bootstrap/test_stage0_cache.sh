#!/usr/bin/env bash
# Compatibility test entry; implementation migrated to ESM (cjcj#883).
exec node "$(dirname "$0")/test_stage0_cache.mjs" "$@"

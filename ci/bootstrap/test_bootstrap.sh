#!/usr/bin/env bash
# Compatibility entry; the complete contract dispatcher lives in zx ESM.
exec node "$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)/test-bootstrap.mjs" "$@"

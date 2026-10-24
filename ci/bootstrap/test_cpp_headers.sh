#!/usr/bin/env bash
# Compatibility entry; implementation is the registered zx/ESM driver.
exec node "$(dirname "${BASH_SOURCE[0]}")/cpp-headers.integration.mjs" "$@"

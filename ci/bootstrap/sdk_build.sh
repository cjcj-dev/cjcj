#!/usr/bin/env bash
# Compatibility entry. All production assembly consumes one complete frozen plan.
exec node "$(dirname "${BASH_SOURCE[0]}")/sdk-build.mjs" "$@"

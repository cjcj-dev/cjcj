#!/usr/bin/env bash
# Compatibility entry. Native target configuration builds, installs, tests and archives.
exec node "$(dirname "${BASH_SOURCE[0]}")/sdk-build.mjs" "$@"

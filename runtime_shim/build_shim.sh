#!/usr/bin/env bash
exec npx --yes zx@8 "$(dirname "$0")/build_shim.mjs" "$@"

#!/usr/bin/env bash
# Colour LLVM tools must not DT_NEEDED libxml2. The fat tuple recipe turns the
# dependency off at cmake (ci/platform_tuples/build_tuple.sh); this is the check
# the publisher runs on the linked binary.
set -euo pipefail

tool=${1:?usage: assert_no_libxml2_needed.sh TOOL}
if [[ ! -f $tool || -L $tool ]]; then
    echo "not a regular file: $tool" >&2
    exit 2
fi
case "$(uname -s)" in
    Darwin) deps=$(otool -L "$tool") ;;
    *) deps=$(readelf -d "$tool") ;;
esac
if printf '%s\n' "$deps" | grep -F libxml2 >/dev/null; then
    echo "DT_NEEDED libxml2 in $tool" >&2
    printf '%s\n' "$deps" >&2
    exit 1
fi
echo "NO_LIBXML2 $(basename "$tool")"

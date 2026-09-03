#!/usr/bin/env bash
set -euo pipefail
basedir=${CCACHE_BASEDIR:-${CANGJIE_WORKSPACE:-}}
compiler=$1
shift
if [[ -z $basedir ]]; then
    exec "$compiler" "$@"
fi
cwd=$PWD
out=()
for arg in "$@"; do
    if [[ $arg == -I${basedir}/* ]]; then
        rel=$(realpath --relative-to="$cwd" "${arg#-I}" 2>/dev/null || true)
        if [[ -n $rel ]]; then out+=("-I$rel"); continue; fi
    elif [[ $arg == ${basedir}/* ]]; then
        rel=$(realpath --relative-to="$cwd" "$arg" 2>/dev/null || true)
        if [[ -n $rel ]]; then out+=("$rel"); continue; fi
    fi
    out+=("$arg")
done
exec "$compiler" "${out[@]}"

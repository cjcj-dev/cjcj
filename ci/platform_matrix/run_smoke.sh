#!/usr/bin/env bash
# Cross-platform two-sample compile/run smoke. If the pinned runtime stage
# produced a host library, repeat one sample with that library first in the
# loader search path to exercise the runtime+cjcj combination.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=ci/platform_matrix/common.sh
source "$HERE/common.sh"
stage_begin test

print_common_versions
case "$(uname -s)" in
    MINGW*|MSYS*) exe_suffix=.exe ;;
    *) exe_suffix= ;;
esac

product=""
for candidate in \
    "target/release/bin/cjcj::cjc${exe_suffix}" \
    "target/release/bin/cjcj${exe_suffix}" \
    "target/release/bin/cjc${exe_suffix}"; do
    if [ -f "$candidate" ]; then product="$candidate"; break; fi
done
if [ -z "$product" ]; then
    product="$(find target -type f \( -name 'cjcj*.exe' -o -name 'cjcj::cjc' -o -name 'cjcj' \) -print -quit 2>/dev/null || true)"
fi
if [ -z "$product" ]; then
    echo "FATAL: cjcj build product not found; cjcj stage did not reach link success" >&2
    exit 2
fi

deploy="$PLATFORM_CI_ROOT/bin/cjcj${exe_suffix}"
mkdir -p "$PLATFORM_CI_ROOT/bin"
cp "$product" "$deploy"
chmod +x "$deploy" || true
if [ -n "${CANGJIE_HOME:-}" ] && [ -d "$CANGJIE_HOME/runtime" ]; then
    if [ ! -e "$PLATFORM_CI_ROOT/runtime" ]; then
        cp -R "$CANGJIE_HOME/runtime" "$PLATFORM_CI_ROOT/runtime"
    fi
fi
"$deploy" --version || true

run_one() {
    local name expected out got
    name="$1"
    expected="$2"
    out="$PLATFORM_CI_ROOT/${name}${exe_suffix:-}"
    "$deploy" "ci/smoke/${name}.cj" -o "$out"
    got="$("$out")"
    printf '%s => [%s]\n' "$name" "$got"
    [ "$got" = "$expected" ] || {
        printf 'ERROR: %s expected [%s], got [%s]\n' "$name" "$expected" "$got" >&2
        return 1
    }
}
run_one 01_hello 'hello from cjcj'
run_one 02_generics '42 hi 7'

runtime_lib="$(find "$PLATFORM_CI_ROOT/runtime-install" -type f \( -name 'libcangjie-runtime.so' -o -name 'libcangjie-runtime.dylib' -o -iname 'libcangjie-runtime.dll' -o -iname 'cangjie-runtime.dll' \) -print -quit 2>/dev/null || true)"
if [ -n "$runtime_lib" ]; then
    runtime_dir="$(dirname "$runtime_lib")"
    echo "combined runtime smoke: $runtime_lib"
    case "$(uname -s)" in
        Darwin) DYLD_LIBRARY_PATH="$runtime_dir:${DYLD_LIBRARY_PATH:-}" run_one 01_hello 'hello from cjcj' ;;
        MINGW*|MSYS*) PATH="$runtime_dir:$PATH" run_one 01_hello 'hello from cjcj' ;;
        *) LD_LIBRARY_PATH="$runtime_dir:${LD_LIBRARY_PATH:-}" run_one 01_hello 'hello from cjcj' ;;
    esac
else
    echo "ERROR: combined runtime smoke unavailable: runtime stage produced no host library" >&2
    exit 3
fi

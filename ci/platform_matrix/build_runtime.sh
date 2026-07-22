#!/usr/bin/env bash
# Build the exact pinned runtime on the current host. Linux/macOS use the
# build.py native path. Windows runs build.py's windows-x86_64 target inside
# MSYS2/MinGW64 because build.py has no Windows-host/MSVC native branch and
# hard-codes make.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=ci/platform_matrix/common.sh
source "$HERE/common.sh"
stage_begin runtime

RUNTIME_SOURCE="${RUNTIME_SOURCE:-$PWD/runtime-source}"
RUNTIME_VERSION="${RUNTIME_VERSION:-1.2.0-alpha.20260721165458}"
INSTALL_ROOT="${PLATFORM_CI_ROOT}/runtime-install"

print_common_versions
printf 'runtime_source=%s\nruntime_ref=%s\n' "$RUNTIME_SOURCE" "${RUNTIME_REF:-unknown}"
if [ ! -f "$RUNTIME_SOURCE/runtime/build.py" ]; then
    echo "FATAL: pinned runtime checkout missing: $RUNTIME_SOURCE/runtime/build.py" >&2
    exit 2
fi
if [ -n "${RUNTIME_REF:-}" ]; then
    actual_ref="$(git -C "$RUNTIME_SOURCE" rev-parse HEAD)"
    if [ "$actual_ref" != "$RUNTIME_REF" ]; then
        echo "FATAL: runtime checkout is $actual_ref, expected $RUNTIME_REF" >&2
        exit 3
    fi
fi

mkdir -p "$INSTALL_ROOT"
cd "$RUNTIME_SOURCE/runtime" || exit 4
case "$(uname -s)" in
    Linux)
        sudo apt-get update -qq
        sudo apt-get install -y -qq clang cmake make
        python3 build.py build --target native --build-type release \
            --prefix "$RUNNER_TEMP/runtime-preinstall" -v "$RUNTIME_VERSION"
        ;;
    Darwin)
        xcodebuild -version || true
        xcrun --sdk macosx --show-sdk-version || true
        python3 build.py build --target native --build-type release \
            --prefix "$RUNNER_TEMP/runtime-preinstall" -v "$RUNTIME_VERSION"
        ;;
    MINGW*|MSYS*)
        # This is the upstream Windows target recipe, hosted by MSYS2 so its
        # POSIX PATH concatenation and hard-coded `make` are truthful.
        python3 build.py build --target windows-x86_64 --build-type release \
            --target-toolchain /mingw64 --prefix "$RUNNER_TEMP/runtime-preinstall" \
            -v "$RUNTIME_VERSION"
        ;;
    *)
        echo "FATAL: unsupported runtime build host: $(uname -s)/$(uname -m)" >&2
        exit 5
        ;;
esac
python3 build.py install --prefix "$INSTALL_ROOT"
find "$INSTALL_ROOT" -type f -maxdepth 8 -print | sort
runtime_lib="$(find "$INSTALL_ROOT" -type f \( -name 'libcangjie-runtime.so' -o -name 'libcangjie-runtime.dylib' -o -iname 'libcangjie-runtime.dll' -o -iname 'cangjie-runtime.dll' \) -print -quit)"
if [ -z "$runtime_lib" ]; then
    echo "FATAL: libcangjie-runtime was not installed under $INSTALL_ROOT" >&2
    exit 6
fi
file "$runtime_lib" || true

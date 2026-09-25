#!/usr/bin/env bash
# Use the upstream std-support branch; never patch the compiler's CMake files.
set -euo pipefail
src=${1:?compiler source}
build=${2:?build directory}
out=${3:?artifact directory}
nightly=${4:?nightly-1.3.0-alpha.20260924001050 SDK}
mkdir -p "$out"
start=$SECONDS
# Host builds keep clang. A Windows target sets CMAKE_TOOLCHAIN_FILE to the
# compiler's mingw_x86_64_toolchain.cmake, which names the cross compilers.
cmake_cmd=(
  cmake -S "$src" -B "$build" -G Ninja
  -DCMAKE_BUILD_TYPE=Release
  -DCMAKE_POSITION_INDEPENDENT_CODE=ON
)
if [[ -n ${CMAKE_TOOLCHAIN_FILE:-} ]]; then
  cmake_cmd+=(-DCMAKE_TOOLCHAIN_FILE="$CMAKE_TOOLCHAIN_FILE")
  if [[ -n ${AST_CMAKE_PREFIX_PATH:-} ]]; then
    cmake_cmd+=(-DCMAKE_PREFIX_PATH="$AST_CMAKE_PREFIX_PATH")
  fi
else
  cmake_cmd+=(-DCMAKE_C_COMPILER=clang -DCMAKE_CXX_COMPILER=clang++)
fi
cmake_cmd+=(
  -DCANGJIE_BUILD_CJC=OFF -DCANGJIE_BUILD_TESTS=OFF
  -DCANGJIE_BUILD_STD_SUPPORT=ON -DCANGJIE_SKIP_BUILD_CLANG_RT=ON
)
"${cmake_cmd[@]}" 2>&1 | tee "$out/configure.log"
# The dependency listing is evidence of the actual build surface, not a second
# hand-maintained list of upstream objects.
ninja -C "$build" -t commands cangjie-ast-support > "$out/target-commands.txt"
jobs=$(getconf _NPROCESSORS_ONLN)
cmake --build "$build" --target cangjie-ast-support -j "$jobs" \
  2>&1 | tee "$out/build.log"
cp "$build/lib/libcangjie-ast-support.a" "$out/"
# Keep archive, public headers and generated schema from one compiler build.
mkdir -p "$out/include/flatbuffers" "$out/schema" "$out/third_party"
cp -RL "$src/include/cangjie" "$out/include/"
cp "$build/schema/flatbuffers/StdAstFormat_generated.h" "$out/include/flatbuffers/"
cp "$src/schema/StdAstFormat.fbs" "$out/schema/"
# The official nightly supplies the Cangjie flatbuffers module as well as flatc.
cp -RL "$nightly/third_party/flatbuffers" "$out/third_party/"
python3 - "$out" <<'PYHASH'
import hashlib
from pathlib import Path
import sys
root = Path(sys.argv[1])
files = [root / 'libcangjie-ast-support.a']
for name in ('include', 'schema', 'third_party'):
    files.extend(p for p in (root / name).rglob('*') if p.is_file())
with (root / 'SHA256SUMS').open('w') as out:
    for p in sorted(files):
        out.write(f'{hashlib.sha256(p.read_bytes()).hexdigest()}  {p.relative_to(root)}\n')
PYHASH
nm_tool=${NM:-nm}
"$nm_tool" --defined-only "$out/libcangjie-ast-support.a" > "$out/nm-defined.txt"
printf 'target=cangjie-ast-support jobs=%s wall=%ss\n' "$jobs" "$((SECONDS-start))" | tee "$out/build-summary.txt"

#!/usr/bin/env bash
# Use the upstream std-support branch; never patch the compiler's CMake files.
set -euo pipefail
src=${1:?compiler source}
build=${2:?build directory}
out=${3:?artifact directory}
nightly=${4:?official flatbuffers SDK directory}
mkdir -p "$out"
start=$SECONDS
cmake -S "$src" -B "$build" -G Ninja \
  -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_POSITION_INDEPENDENT_CODE=ON \
  -DCMAKE_C_COMPILER=clang -DCMAKE_CXX_COMPILER=clang++ \
  -DCANGJIE_BUILD_CJC=OFF -DCANGJIE_BUILD_TESTS=OFF \
  -DCANGJIE_BUILD_STD_SUPPORT=ON -DCANGJIE_SKIP_BUILD_CLANG_RT=ON \
  2>&1 | tee "$out/configure.log"
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
nm --defined-only "$out/libcangjie-ast-support.a" > "$out/nm-defined.txt"
printf 'target=cangjie-ast-support jobs=%s wall=%ss\n' "$jobs" "$((SECONDS-start))" | tee "$out/build-summary.txt"

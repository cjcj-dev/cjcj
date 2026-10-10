#!/usr/bin/env bash
# One actual fetch_sources -> build_tuple chain. Other source trees use an
# existing local transport fixture; runtime remains the real fixed Git commit.
# First CMake argv is observed, then stopped; no LLVM configure/build is run.
set -euo pipefail
repo=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)
work=${1:?new work directory}
runtime_mirror=${2:?actual runtime Git transport mirror}
other_mirror=${3:?other-source Git transport fixture}
mkdir "$work"
work=$(cd "$work" && pwd -P)
runtime_mirror=$(cd "$runtime_mirror" && pwd -P)
other_mirror=$(cd "$other_mirror" && pwd -P)
other_sha=$(git -C "$other_mirror" rev-parse HEAD)
unset RUNTIME_REF RUNTIME_SRC_URL
export CJCJ_LLVM_RUNTIME_MODE=private
export CJCJ_LLVM_RUNTIME_URL=https://github.com/cjcj-dev/cangjie-runtime.git
export CJCJ_LLVM_RUNTIME_SHA=4909b2dec1af7f522133c6401e2ce960b0ef511d
export CJCJ_SRCBUILD_SOURCE_MIRRORS="$CJCJ_LLVM_RUNTIME_URL=file://$runtime_mirror;file://$other_mirror=file://$other_mirror"
export CJCJ_SRCBUILD_REQUIRE_MIRRORS=1
export TUPLE_ROOT="$work/tuple" TUPLE_PLATFORM=linux_x86_64 LLVM_TARGETS=X86
export LLVM_URL="file://$other_mirror" LLVM_SHA=$other_sha
export CANGJIE_COMPILER_URL="file://$other_mirror" CANGJIE_COMPILER_SHA=$other_sha
export FLATBUFFERS_URL="file://$other_mirror" FLATBUFFERS_SHA=$other_sha
export GIT_TRACE="$work/fetch.trace"
printf 'CHAIN_INPUT runtime=%s other=%s runtime_mirror=%s\n' "$CJCJ_LLVM_RUNTIME_SHA" "$other_sha" "$runtime_mirror"
bash "$repo/ci/platform_tuples/fetch_sources.sh" > "$work/fetch.log" 2>&1
head=$(git -C "$TUPLE_ROOT/paired-runtime" rev-parse HEAD)
printf 'CHAIN_ASSERT_REACHED runtime_head actual=%s expected=%s\n' "$head" "$CJCJ_LLVM_RUNTIME_SHA"
test "$head" = "$CJCJ_LLVM_RUNTIME_SHA"
echo 'CHAIN_ASSERT_PASS runtime_head'
mkdir "$work/bin"
export LLVM_RUNTIME_CMAKE_CAPTURE="$work/cmake.json"
cat > "$work/bin/cmake" <<'PY'
#!/usr/bin/env python3
import json,os,sys
with open(os.environ['LLVM_RUNTIME_CMAKE_CAPTURE'], 'w') as out:
    json.dump(sys.argv[1:], out)
sys.exit(86)
PY
chmod 0755 "$work/bin/cmake"
export PATH="$work/bin:$PATH"
# The same tuple root and private environment enter the real build script.
set +e
bash "$repo/ci/platform_tuples/build_tuple.sh" > "$work/build.log" 2>&1
rc=$?
set -e
printf '%s\n' "$rc" > "$work/build.rc"
printf 'CHAIN_ASSERT_REACHED first_cmake_boundary actual=%s expected=86\n' "$rc"
test "$rc" = 86
echo 'CHAIN_ASSERT_PASS first_cmake_boundary'
python3 - "$work/cmake.json" "$TUPLE_ROOT/paired-runtime" "$CJCJ_LLVM_RUNTIME_SHA" <<'PY'
import json,subprocess,sys
from pathlib import Path
command=json.loads(Path(sys.argv[1]).read_text())
actual=[x for x in command if x.startswith('-DCANGJIE_RUNTIME_SOURCE_DIR=')]
expected=['-DCANGJIE_RUNTIME_SOURCE_DIR='+str(Path(sys.argv[2]).resolve())]
print(f'CHAIN_ASSERT_REACHED cmake_runtime_source actual={actual!r} expected={expected!r}', flush=True)
assert actual==expected, 'cmake_runtime_source'
selected=actual[0].split('=',1)[1]
head=subprocess.check_output(['git','-C',selected,'rev-parse','HEAD'],text=True).strip()
print(f'CHAIN_ASSERT_REACHED consumed_head actual={head} expected={sys.argv[3]}',flush=True)
assert head==sys.argv[3], 'consumed_head'
assert not subprocess.check_output(['git','-C',selected,'status','--porcelain']).strip()
print('CHAIN_ASSERT_PASS cmake_runtime_source consumed_head clean')
PY

#!/usr/bin/env bash
# Run the BCHIR linker regression with the real compiler shim, in a private
# build copy. The package's normal link contract is restored on every exit.
# Usage: CANGJIE_HOME=<sdk> BCHIR_TEST_CORES=<cores> bash scripts/bchir_linker_test.sh \
#          <private-source> <target-dir> <evidence-dir> [test-filter]
set -euo pipefail

source_dir=$(realpath "${1:?private source directory required}")
target_dir=$(realpath -m "${2:?target directory required}")
evidence_dir=$(realpath -m "${3:?evidence directory required}")
test_filter=${4:-BCHIRLinkerTest.*}
sdk=${CANGJIE_HOME:?CANGJIE_HOME must name the SDK used to build the compiler}
cores=${BCHIR_TEST_CORES:?BCHIR_TEST_CORES must name the reserved core domain}
mkdir -p "$evidence_dir" "$evidence_dir/tmp"
manifest=$source_dir/packages/chir/cjpm.toml
backup=$(mktemp "$evidence_dir/chir-manifest.XXXXXX")
cp -p "$manifest" "$backup"
restore_manifest() {
    local rc=$?
    cp -p "$backup" "$manifest"
    sha256sum "$manifest" > "$evidence_dir/manifest.after.sha256"
    cmp "$backup" "$manifest" > "$evidence_dir/manifest.restore.log" 2>&1 || rc=1
    printf '%s\n' "$rc" > "$evidence_dir/harness.rc"
    exit "$rc"
}
trap restore_manifest EXIT
sha256sum "$manifest" > "$evidence_dir/manifest.before.sha256"

# This is the existing CHIRRelease test recipe and the product cjc package's
# actual shim, not a replacement implementation of a missing symbol.
python3 - "$manifest" <<'PY'
from pathlib import Path
import sys
p = Path(sys.argv[1])
text = p.read_text()
old = '  link-option = ""'
if text.count(old) != 1:
    raise SystemExit("expected one empty CHIR link-option in the private copy")
p.write_text(text.replace(old,
    '  link-option = "runtime_shim/cjselfhost_llvmshim.o '
    '${CANGJIE_HOME}/third_party/llvm/lib/libLLVM-15.so -lstdc++"', 1))
PY

export PATH="$sdk/bin:$sdk/tools/bin:$sdk/third_party/llvm/bin:/usr/bin:/bin"
export LD_LIBRARY_PATH="$sdk/runtime/lib/linux_x86_64_cjnative:$sdk/lib/linux_x86_64_cjnative:$sdk/third_party/llvm/lib:$sdk/tools/lib:/usr/lib/x86_64-linux-gnu"
export TMPDIR="$evidence_dir/tmp"
export cjHeapSize=24GB
sha256sum "$sdk/bin/cjc" "$sdk/tools/bin/cjpm" \
    "$sdk/runtime/lib/linux_x86_64_cjnative/libcangjie-runtime.so" \
    "$sdk/runtime/lib/linux_x86_64_cjnative/libboundscheck.so" \
    "$sdk/third_party/llvm/lib/libLLVM-15.so" \
    "$source_dir/runtime_shim/cjselfhost_llvmshim.o" > "$evidence_dir/inputs.sha256"
sha256sum "$source_dir/packages/chir/src/BCHIRLinker.cj" \
    "$source_dir/packages/chir/src/BCHIR.cj" \
    "$source_dir/packages/chir/src/BCHIRLinker_test.cj" > "$evidence_dir/source.sha256"
printf 'cores=%s filter=%s flags=-g -i --member=packages/chir\n' "$cores" "$test_filter" > "$evidence_dir/recipe.txt"
date -Ins > "$evidence_dir/build.before"
uptime > "$evidence_dir/uptime.before"
cd "$source_dir"
set +e
taskset -c "$cores" timeout -k 10 1800 cjpm test -g -i -j 8 \
    --member=packages/chir --filter "$test_filter" --target-dir "$target_dir" \
    --no-color > "$evidence_dir/test.log" 2>&1
rc=$?
set -e
printf '%s\n' "$rc" > "$evidence_dir/test.rc"
date -Ins > "$evidence_dir/build.after"
uptime > "$evidence_dir/uptime.after"
test_elf=$target_dir/debug/unittest_bin/chir@cjcj
if [[ -f "$test_elf" ]]; then
    cp -p "$test_elf" "$evidence_dir/chir-test"
    sha256sum "$evidence_dir/chir-test" > "$evidence_dir/test.sha256"
fi
exit "$rc"

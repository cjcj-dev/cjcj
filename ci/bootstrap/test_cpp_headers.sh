#!/usr/bin/env bash
# Real cold-start integration test. Run on a build host with the bootstrap SDK,
# host LLVM, AST archive and colour tuple inputs used by prepare_bootstrap_inputs.
# Usage: bash ci/bootstrap/test_cpp_headers.sh <new, empty work directory>
# Source mirrors may be supplied through CJCJ_SRCBUILD_SOURCE_MIRRORS.
set -euo pipefail
ulimit -c 0
repo=$(cd "$(dirname "$0")/../.." && pwd)
work=${1:?new work directory required}
mkdir "$work"
work=$(cd "$work" && pwd)
export CANGJIE_WORKSPACE="$work/workspace"
export GITHUB_ENV="$work/bootstrap.env"
export CJCJ_BOOTSTRAP_CJCJ_SHA=$(git -C "$repo" rev-parse HEAD)
unset CJCJ_BOOTSTRAP_CPP_SRC CANGJIE_CPP_SRC CJCJ_LLVM_SHIM_O
set -a
source "$repo/ci/llvm_pin.env"
source "$repo/ci/source_pin.env"
set +a
cpp="$CANGJIE_WORKSPACE/cangjie_compiler"
node --input-type=module - "$repo" "$cpp" <<'JS'
import {pathToFileURL} from 'node:url';
const {checkoutExactSource} = await import(pathToFileURL(`${process.argv[2]}/build/lib/git.mjs`));
await checkoutExactSource(process.env.COMPILER_SRC_URL, process.argv[3], process.env.COMPILER_REF);
JS
[[ ! -e "$cpp/build" ]]
printf 'COLD_COMPILER_BUILD_ABSENT path=%s\n' "$cpp/build"
mkdir -p "$work/consumer/runtime_shim"
cp -a "$repo/runtime_shim/." "$work/consumer/runtime_shim/"
rm -f "$work/consumer/runtime_shim/"*.o
export CJCJ_COMMIT="$CJCJ_BOOTSTRAP_CJCJ_SHA"
# Positive control for the missing-input detector, on the real shim consumer.
set +e
CANGJIE_CPP_SRC="$cpp" bash "$work/consumer/runtime_shim/build_shim.sh" > "$work/before.log" 2>&1
before_rc=$?
set -e
[[ $before_rc -ne 0 ]]
grep -F 'ERR: cannot obtain cjselfhost_llvmshim.o' "$work/before.log"
printf 'COLD_SHIM_BEFORE_RC=%s\n' "$before_rc"
node "$repo/ci/release/prepare_bootstrap_inputs.mjs"
node --input-type=module - "$cpp" "$GITHUB_ENV" <<'JS'
import assert from 'node:assert/strict';
import crypto from 'node:crypto';
import fs from 'node:fs';
import path from 'node:path';
const cpp = process.argv[2];
assert.ok(fs.readFileSync(process.argv[3], 'utf8').split('\n').includes(`CJCJ_BOOTSTRAP_CPP_SRC=${cpp}`));
const manifest = JSON.parse(fs.readFileSync(`${cpp}/build/build/shim-headers.json`));
assert.equal(manifest.compiler.sha, process.env.COMPILER_REF);
assert.equal(manifest.llvm.sha, process.env.LLVM_SHA);
assert.equal(manifest.flatbuffers.sha, process.env.FLATBUFFERS_SHA);
for (const [root, files] of Object.entries(manifest.headers)) {
  assert.ok(files.length > 0, root);
  for (const file of files) {
    const hash = crypto.createHash('sha256').update(fs.readFileSync(path.join(cpp, root, file.path))).digest('hex');
    assert.equal(hash, file.sha256, file.path);
  }
  console.log(`HEADER_MANIFEST_VERIFIED root=${root} files=${files.length}`);
}
JS
CANGJIE_CPP_SRC="$cpp" bash "$work/consumer/runtime_shim/build_shim.sh" > "$work/after.log" 2>&1
printf 'COLD_SHIM_AFTER_RC=0\n'
nm --defined-only "$work/consumer/runtime_shim/cjselfhost_llvmshim.o" > "$work/shim.nm"
grep -E ' T LLVMGlobalObjectAddStringAttribute$' "$work/shim.nm"
sha256sum "$work/consumer/runtime_shim/"*.o
printf 'COLD_SHIM_TEST_PASS work=%s\n' "$work"

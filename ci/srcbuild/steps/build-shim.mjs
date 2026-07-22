#!/usr/bin/env zx

import fs from 'node:fs/promises';

$.stdio = 'inherit';

await $`rm -f runtime_shim/cjselfhost_llvmshim.o runtime_shim/cjc_runtime_config.o`;
await $`set -o pipefail; npx --yes zx@8 runtime_shim/build_shim.mjs | tee .srcbuild/shim-build.log`;
const log = await fs.readFile('.srcbuild/shim-build.log', 'utf8');
if (log.includes('used vendored prebuilt shim')) {
  throw new Error('shim source build unexpectedly fell back to a vendored object');
}
const stat = await fs.stat('runtime_shim/cjselfhost_llvmshim.o');
if (stat.size === 0) throw new Error('runtime_shim/cjselfhost_llvmshim.o is empty');

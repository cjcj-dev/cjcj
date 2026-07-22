#!/usr/bin/env zx

$.stdio = 'inherit';

// cjcj has no upstream -O2 CHIR bug. Self-build the final compiler at -O2 with
// cjcj-stage1; the fixed static llc handles the -O2 backend.
console.log('stage2 compiler:');
await $`set -o pipefail; cjc --version | head -2`;
// -j1 + 20GB heap (backed by the workflow's 16GB swapfile): the O1-seed stage1
// compiling chir OOMs at 14GB with 38% region fragmentation (rc3); the local
// 24GB control passed at ~26GB RSS. 20GB heap over 16GB RAM + 16GB swap is the
// smallest configuration with headroom over the ~9.4GB live set + fragmentation.
await $({env: {...process.env, cjHeapSize: '20GB'}})`cjpm build -j 1`;

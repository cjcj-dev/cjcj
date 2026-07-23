#!/usr/bin/env zx

$.stdio = 'inherit';

// cjcj has no upstream -O2 CHIR bug. Self-build the final compiler at -O2 with
// cjcj-stage1; the fixed static llc handles the -O2 backend.
console.log('[stage2] compiler');
await $`set -o pipefail; cjc --version | head -2`;
// -j1 + 14GB heap: the O1-seed stage1 compiling chir needs >12GB Cangjie heap
// (rc2: OOM at usedObjSize 9.46GB with 26.6% region fragmentation on the 12.8GB
// heap). Single-process keeps peak RSS within the 16GB runner while the heap
// cap gets the remaining headroom.
await $({env: {...process.env, cjHeapSize: '14GB'}})`cjpm build -j 1`;

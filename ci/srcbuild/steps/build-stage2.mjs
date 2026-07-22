#!/usr/bin/env zx

$.stdio = 'inherit';

// cjcj has no upstream -O2 CHIR bug. Self-build the final compiler at -O2 with
// cjcj-stage1; the fixed static llc handles the -O2 backend.
console.log('stage2 compiler:');
await $`set -o pipefail; cjc --version | head -2`;
await $`cjpm build`;

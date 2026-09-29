#!/usr/bin/env zx

import {checkCodegenRuntimeLayout} from '../../check-codegen-runtime-layout.mjs';

$.stdio = 'inherit';

// cjcj has no upstream -O2 CHIR bug. Self-build the final compiler at -O2 with
// cjcj-stage1; the fixed static llc handles the -O2 backend.
console.log('[stage2] compiler');
await $`set -o pipefail; cjc --version | head -2`;
// Inherit the caller’s resource-limited host heap; swap does not raise the
// official runtime’s physical-memory limit. Compiler sizing belongs to its wrapper.
await checkCodegenRuntimeLayout();
await $`cjpm build -j 1`;

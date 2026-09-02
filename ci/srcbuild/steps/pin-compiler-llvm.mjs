#!/usr/bin/env node

import fs from 'node:fs';
import path from 'node:path';
import {checkoutExactSource} from '../../../build/lib/git.mjs';

const workspace = process.env.CANGJIE_WORKSPACE;
const llvmRef = process.env.LLVM_REF;
if (!workspace || !llvmRef) throw new Error('CANGJIE_WORKSPACE and LLVM_REF are required');

// compiler main emits 7-operand enum reflection, while its hard-coded LLVM dev
// branch only accepts 6. Pin LLVM main with ERT_CTOR_ANNOTATIONS and pre-create
// the source override so the compiler build does not clone the dev branch.
const llvmSrc = path.join(workspace, 'cangjie_compiler', 'third_party', 'llvm-project');
// The URL is a variable because the release line builds our fork, which carries the
// barrier lowering and the stack-map fixes. Upstream stays the default so a caller
// that only sets LLVM_REF keeps the old behaviour instead of silently switching repo.
const llvmUrl = process.env.LLVM_URL || 'https://gitcode.com/Cangjie/llvm-project.git';
await checkoutExactSource(llvmUrl, llvmSrc, llvmRef);
const actualRef = fs.readFileSync(path.join(llvmSrc, '.git', 'HEAD'), 'utf8').trim();
if (actualRef !== llvmRef) throw new Error(`LLVM ref mismatch: expected ${llvmRef}, got ${actualRef}`);
const reflection = fs.readFileSync(
  path.join(llvmSrc, 'llvm/include/llvm/Transforms/Scalar/ReflectionInfo.h'), 'utf8');
if (!reflection.includes('ERT_CTOR_ANNOTATIONS')) {
  throw new Error('pinned LLVM is missing ERT_CTOR_ANNOTATIONS');
}

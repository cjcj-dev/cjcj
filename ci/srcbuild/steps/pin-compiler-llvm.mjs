#!/usr/bin/env zx

$.stdio = 'inherit';

const workspace = process.env.CANGJIE_WORKSPACE;
const llvmRef = process.env.LLVM_REF;
if (!workspace || !llvmRef) throw new Error('CANGJIE_WORKSPACE and LLVM_REF are required');

// compiler main emits 7-operand enum reflection, while its hard-coded LLVM dev
// branch only accepts 6. Pin LLVM main with ERT_CTOR_ANNOTATIONS and pre-create
// the source override so the compiler build does not clone the dev branch.
const llvmSrc = `${workspace}/cangjie_compiler/third_party/llvm-project`;
await $`git init ${llvmSrc}`;
await $`git -C ${llvmSrc} remote add origin https://gitcode.com/Cangjie/llvm-project.git`;
await $`git -C ${llvmSrc} fetch --depth=1 origin ${llvmRef}`;
await $`git -C ${llvmSrc} checkout --detach FETCH_HEAD`;
const actualRef = (await $({stdio: 'pipe'})`git -C ${llvmSrc} rev-parse HEAD`).stdout.trim();
if (actualRef !== llvmRef) throw new Error(`LLVM ref mismatch: expected ${llvmRef}, got ${actualRef}`);
await $`grep -q ERT_CTOR_ANNOTATIONS ${llvmSrc}/llvm/include/llvm/Transforms/Scalar/ReflectionInfo.h`;

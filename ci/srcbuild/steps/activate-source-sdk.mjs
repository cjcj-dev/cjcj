#!/usr/bin/env zx

import fs from 'node:fs/promises';

$.stdio = 'inherit';

const workspace = process.env.CANGJIE_WORKSPACE;
const githubEnv = process.env.GITHUB_ENV;
const githubPath = process.env.GITHUB_PATH;
if (!workspace || !githubEnv || !githubPath) {
  throw new Error('CANGJIE_WORKSPACE, GITHUB_ENV and GITHUB_PATH are required');
}

const sdk = `${workspace}/software/cangjie`;
const fixedLlc = `${sdk}/third_party/llvm/bin/llc.fixed`;
await $`gunzip -c .srcbuild/fixed-llc/llc.gz > ${fixedLlc}`;
await $`chmod 0755 ${fixedLlc}`;
await $`set -o pipefail; ${fixedLlc} --version | head -5`;
await $`mv ${fixedLlc} ${sdk}/third_party/llvm/bin/llc`;

// A stubbed llvm-objcopy -- 19 bytes of `#!/bin/bash\nexit 0` -- sat in a shared
// toolchain for a day. It returns rc=0 and leaves the object byte-identical, so
// the --localize-symbols pass after `ld -r` silently did nothing: 3871 symbols
// that CHIR had correctly marked INTERNAL stayed global, and stage2 linked with
// 14665 multiple-definition errors. Nothing in the build noticed, because every
// step reported success. A lane spent a full round looking for the defect in our
// codegen before finding the tool.
//
// rc=0 is not evidence a tool did its job. Make each one identify itself: a
// stub is a script, so `file` separates it from a real binary, and --version
// separates a truncated or wrong-arch binary from a working one. Size proves
// identity, never validity, so it is deliberately not a criterion here.
const requiredLlvmTools = ['llc', 'llvm-objcopy', 'llvm-ar', 'llvm-strip'];
for (const tool of requiredLlvmTools) {
  const path = `${sdk}/third_party/llvm/bin/${tool}`;
  const kind = (await $({stdio: 'pipe'})`file -b ${path}`).stdout.trim();
  if (!kind.startsWith('ELF')) {
    throw new Error(`${tool} is not a binary (${kind}); a stub would pass every rc check silently`);
  }
  await $`set -o pipefail; ${path} --version | head -3`;
}

const llvmDir = `${sdk}/third_party/llvm/lib`;

await fs.appendFile(githubEnv, [
  `CANGJIE_HOME=${sdk}`,
  `CANGJIE_STDX_PATH=${workspace}/cangjie_stdx/target/linux_x86_64_cjnative/static/stdx`,
  `LD_LIBRARY_PATH=${llvmDir}:${sdk}/runtime/lib/linux_x86_64_cjnative:${sdk}/tools/lib`,
  '',
].join('\n'));
await fs.appendFile(githubPath, `${sdk}/bin\n${sdk}/tools/bin\n`);

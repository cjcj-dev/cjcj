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

const llvmDir = `${sdk}/third_party/llvm/lib`;
const hardDir = (await $({stdio: 'pipe'})`grep -oE "/[^ '\\"]*/third_party/llvm/lib" packages/cjc/cjpm.toml | head -1`).stdout.trim();
await $`sed ${`s#${hardDir}#${llvmDir}#g`} packages/cjc/cjpm.toml > packages/cjc/cjpm.toml.tmp`;
await $`mv packages/cjc/cjpm.toml.tmp packages/cjc/cjpm.toml`;

await fs.appendFile(githubEnv, [
  `CANGJIE_HOME=${sdk}`,
  `CANGJIE_STDX_PATH=${workspace}/cangjie_stdx/target/linux_x86_64_cjnative/static/stdx`,
  `LD_LIBRARY_PATH=${llvmDir}:${sdk}/runtime/lib/linux_x86_64_cjnative:${sdk}/tools/lib`,
  '',
].join('\n'));
await fs.appendFile(githubPath, `${sdk}/bin\n${sdk}/tools/bin\n`);

#!/usr/bin/env zx

$.stdio = 'inherit';

const workspace = process.env.CANGJIE_WORKSPACE;
const githubWorkspace = process.env.GITHUB_WORKSPACE;
if (!workspace || !githubWorkspace) throw new Error('CANGJIE_WORKSPACE and GITHUB_WORKSPACE are required');

const sdk = `${workspace}/software/cangjie`;
await $`cp cjpm.toml cjpm.toml.O2bak`;
await $`sed -i 's/compile-option = "-O2"/compile-option = "-O1"/' cjpm.toml`;
// Upstream cjc miscompiles cjcj at -O2. Build the seed at -O1 to avoid the
// generic concrete-to-interface upcast loss in the upstream CHIR optimizer.
await $`cjpm build`;

// Put the seed under the SDK so <exe>/../runtime resolves. The C++ oracle stays
// in cangjie_compiler/output/bin and is never copied into the SDK tree.
// The mapped seed must not be named cjc: the Linux runtime reserves that basename
// for native C++ cjc and otherwise excludes managed frames from GC root scanning.
await $`install -m0755 target/release/bin/cjcj::cjc ${sdk}/bin/cjcj-stage1`;
await $`rm -f ${sdk}/bin/cjc`;
await $`ln -s cjcj-stage1 ${sdk}/bin/cjc`;
const scanJson = (await $({stdio: 'pipe'})`mktemp`).stdout.trim();
await $`cjc -p ${githubWorkspace}/packages/basic/src --scan-dependency > ${scanJson}`;
await $`grep -q '"package":"cjcj::basic"' ${scanJson}`;
await $`mv cjpm.toml.O2bak cjpm.toml`;
await $`cjpm clean`;

#!/usr/bin/env zx

import fs from 'node:fs/promises';

$.stdio = 'inherit';

const workspace = process.env.CANGJIE_WORKSPACE;
const version = process.env.SOURCE_SDK_VERSION;
if (!workspace || !version) throw new Error('CANGJIE_WORKSPACE and SOURCE_SDK_VERSION are required');

const sdk = `${workspace}/software/cangjie`;
await $`test -x target/release/bin/cjcj::cjc`;
// The packaged SDK contains exactly one compiler, built by the cjcj stage2 line.
// cjc-frontend is an official C++ SDK tool; frontend_tool is currently a static
// selfhost package, so shipping the C++ binary would mix product lines.
const compilerNames = [
  'cjc',
  'cjc-frontend',
  'cjc-upstream-oracle',
  'cjc-oracle',
  'cjcj-stage1',
  'cjcj',
];
for (const name of compilerNames) await fs.rm(`${sdk}/bin/${name}`, {force: true});
await $`install -m0755 target/release/bin/cjcj::cjc ${sdk}/bin/cjc`;

const archive = `${workspace}/software/cangjie-sdk-linux-x64-${version}-cjcj.tar.gz`;
await $`tar -C ${workspace}/software -czf ${archive} cangjie`;
await $`sha256sum ${archive} > ${archive}.sha256`;

#!/usr/bin/env zx

$.stdio = 'inherit';

const workspace = process.env.CANGJIE_WORKSPACE;
const version = process.env.SOURCE_SDK_VERSION;
if (!workspace || !version) throw new Error('CANGJIE_WORKSPACE and SOURCE_SDK_VERSION are required');

const sdk = `${workspace}/software/cangjie`;
await $`test -x target/release/bin/cjcj::cjc`;
// Stage1 replaced cjc with the seed symlink. Restore upstream cjc, expose its
// oracle copy, and install the final self-built stage2 compiler.
await $`rm -f ${sdk}/bin/cjc`;
await $`install -m0755 ${sdk}/bin/cjc-upstream-oracle ${sdk}/bin/cjc`;
await $`cp ${sdk}/bin/cjc ${sdk}/bin/cjc-oracle`;
await $`install -m0755 target/release/bin/cjcj::cjc ${sdk}/bin/cjcj`;

const archive = `${workspace}/software/cangjie-sdk-linux-x64-${version}-cjcj.tar.gz`;
await $`tar -C ${workspace}/software -czf ${archive} cangjie`;
await $`sha256sum ${archive} > ${archive}.sha256`;

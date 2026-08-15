#!/usr/bin/env zx

import crypto from 'node:crypto';
import fs from 'node:fs/promises';
import path from 'node:path';
import {runRequiredCheck} from '../../../build/lib/fail-closed-probes.mjs';
import {assertSdkCompilerRuntimeAbi} from '../../../build/lib/runtime-split.mjs';
import {getTarget} from '../../../build/lib/targets.mjs';
import {resolveProductBinary} from '../lib/product-binary.mjs';

$.stdio = 'inherit';

const workspace = process.env.CANGJIE_WORKSPACE;
const version = process.env.SOURCE_SDK_VERSION;
const targetKey = process.env.CJCJ_SRCBUILD_TARGET;
if (!workspace || !version || !targetKey) {
  throw new Error('CANGJIE_WORKSPACE, SOURCE_SDK_VERSION and CJCJ_SRCBUILD_TARGET are required');
}
const target = getTarget(targetKey);
if (process.platform !== target.spec.nodePlatform || process.arch !== target.spec.nodeArch) {
  throw new Error(`target ${targetKey} requires ${target.spec.nodePlatform}/${target.spec.nodeArch}`);
}

const sdk = `${workspace}/software/cangjie`;
const product = await resolveProductBinary('target/release/bin', 'compose-sdk');
await $`test -x ${product}`;
// The packaged SDK contains exactly one compiler, rebuilt at stage3 against the
// final std produced by stage2.
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
await $`install -m0755 ${product} ${sdk}/bin/cjc`;
const productVersion = await $({stdio: 'pipe'})`${sdk}/bin/cjc --version`;
const versionOutput = `${productVersion.stdout}${productVersion.stderr}`;
if (!versionOutput.includes(version)) {
  throw new Error(`selfhost version mismatch: expected ${version}, got ${versionOutput.trim()}`);
}
process.stdout.write(versionOutput);

const installed = path.join(sdk, 'bin', 'cjc');
const kind = (await $({stdio: 'pipe'})`file -b ${installed}`).stdout.trim();
if (!kind.includes(target.spec.fileFormat) || !kind.includes(target.spec.fileArch)) {
  throw new Error(`packaged compiler has wrong native format for ${targetKey}: ${kind}`);
}
await runRequiredCheck({
  label: 'packaged SDK compiler/runtime colour ABI',
  run: async () => assertSdkCompilerRuntimeAbi({sdk, target}),
});

if (target.spec.os === 'darwin') {
  const runtime = path.join(sdk, 'runtime', 'lib', target.spec.runtimeTuple, target.spec.runtimeLibrary);
  const llvm = path.join(sdk, 'third_party', 'llvm', 'lib', 'libLLVM.dylib');
  await $`install_name_tool -id ${`@rpath/${target.spec.runtimeLibrary}`} ${runtime}`;
  await $`install_name_tool -id '@rpath/libLLVM.dylib' ${llvm}`;
  const linked = await $({stdio: 'pipe'})`otool -L ${installed}`;
  for (const line of linked.stdout.split('\n').slice(1)) {
    const dependency = line.trim().split(/\s+\(/)[0];
    const basename = path.basename(dependency);
    if (basename === target.spec.runtimeLibrary && dependency !== `@rpath/${basename}`) {
      await $`install_name_tool -change ${dependency} ${`@rpath/${basename}`} ${installed}`;
    }
    if (basename === 'libLLVM.dylib' && dependency !== '@rpath/libLLVM.dylib') {
      await $`install_name_tool -change ${dependency} '@rpath/libLLVM.dylib' ${installed}`;
    }
  }
  const loadCommands = await $({stdio: 'pipe'})`otool -l ${installed}`;
  const lines = loadCommands.stdout.split('\n');
  const rpaths = [];
  for (let index = 0; index < lines.length; index += 1) {
    if (lines[index].trim() !== 'cmd LC_RPATH') continue;
    const pathLine = lines.slice(index + 1, index + 5).find(line => /^\s*path .* \(offset \d+\)$/.test(line));
    if (pathLine) rpaths.push(pathLine.trim().replace(/^path /, '').replace(/ \(offset \d+\)$/, ''));
  }
  for (const rpath of new Set(rpaths.filter(value => path.isAbsolute(value)))) {
    await $`install_name_tool -delete_rpath ${rpath} ${installed}`;
  }
  const relativeRpaths = [
    `@loader_path/../runtime/lib/${target.spec.runtimeTuple}`,
    '@loader_path/../third_party/llvm/lib',
    '@loader_path/../tools/lib',
  ];
  for (const rpath of relativeRpaths) {
    if (!rpaths.includes(rpath)) await $`install_name_tool -add_rpath ${rpath} ${installed}`;
  }
}

const archive = path.join(
  workspace, 'software', `cangjie-sdk-${target.spec.sdkName}-${version}-cjcj.tar.gz`,
);
await $`${target.spec.tarCommand} --format=gnu -C ${path.join(workspace, 'software')} -czf ${archive} cangjie`;
const archiveSha = crypto.createHash('sha256').update(await fs.readFile(archive)).digest('hex');
await fs.writeFile(`${archive}.sha256`, `${archiveSha}  ${path.basename(archive)}\n`);
console.log(`SOURCE_SDK_ARCHIVE target=${targetKey} tuple=${target.spec.runtimeTuple} sha256=${archiveSha} path=${archive}`);

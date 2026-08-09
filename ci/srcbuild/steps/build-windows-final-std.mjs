#!/usr/bin/env zx

import fs from 'node:fs/promises';
import path from 'node:path';
import {writeStdProvenance} from '../../../build/lib/provenance.mjs';
import {getTarget} from '../../../build/lib/targets.mjs';
import {installPath, isInstalled, TARGET_TRIPLE} from '../../../build/toolchain/mingw.mjs';
import {assertFinalStd} from '../lib/final-std.mjs';

$.stdio = 'inherit';

const requiredEnv = name => {
  const value = process.env[name];
  if (!value) throw new Error(`${name} is required`);
  return value;
};

const workspace = path.resolve(requiredEnv('CANGJIE_WORKSPACE'));
const buildRoot = path.resolve(requiredEnv('CANGJIE_BUILD_ROOT'));
const version = requiredEnv('CJCJ_STAGE3_CANGJIE_VERSION');
const expectedRuntimeRef = requiredEnv('RUNTIME_REF');
for (const directory of [workspace, buildRoot]) {
  if (directory === path.parse(directory).root) throw new Error('source-build paths must not be filesystem roots');
}

const target = getTarget('windows-x64');
if (process.platform !== target.spec.nodePlatform || process.arch !== target.spec.nodeArch) {
  throw new Error(`target ${target.spec.key} requires ${target.spec.nodePlatform}/${target.spec.nodeArch}`);
}
if (!target.spec.crossCompile) throw new Error('windows-x64 must remain a cross target');
if (!isInstalled(buildRoot)) throw new Error(`official MinGW toolchain is incomplete under ${installPath(buildRoot)}`);

const sdk = path.join(workspace, 'software', 'cangjie');
const compiler = path.join(sdk, 'bin', 'cjcj-stage2');
const activeCompiler = path.join(sdk, 'bin', 'cjc');
const runtimeRepository = path.join(workspace, 'cangjie_runtime');
const runtimeRoot = path.join(runtimeRepository, 'runtime');
const runtimeOutput = path.join(runtimeRoot, 'output');
const runtimeTarget = path.join(runtimeRoot, 'target');
const stdlibRoot = path.join(runtimeRepository, 'stdlib');
const finalStd = path.join(workspace, 'software', 'final-std-windows-stage2');
const mingwRoot = installPath(buildRoot);
const mingwBin = path.join(mingwRoot, 'bin');
const mingwLib = path.join(mingwRoot, TARGET_TRIPLE, 'lib');

const runtimeRef = (await $({stdio: 'pipe'})`git -C ${runtimeRepository} rev-parse HEAD`).stdout.trim();
if (runtimeRef !== expectedRuntimeRef) {
  throw new Error(`runtime source mismatch: expected ${expectedRuntimeRef}, got ${runtimeRef}`);
}
const [resolvedCompiler, resolvedActiveCompiler] = await Promise.all([
  fs.realpath(compiler),
  fs.realpath(activeCompiler),
]);
if (resolvedCompiler !== resolvedActiveCompiler) {
  throw new Error(`Windows final std must use stage2: active=${resolvedActiveCompiler}, expected=${resolvedCompiler}`);
}
const compilerKind = (await $({stdio: 'pipe'})`file -b ${compiler}`).stdout.trim();
if (!compilerKind.includes('ELF') || !compilerKind.includes('x86-64')) {
  throw new Error(`stage2 host compiler has wrong format: ${compilerKind}`);
}

const stageEnv = {
  ...process.env,
  ARCH: 'x86_64',
  CANGJIE_HOME: sdk,
  CANGJIE_VERSION: version,
  CMAKE_PREFIX_PATH: path.join(mingwRoot, TARGET_TRIPLE),
  LDFLAGS: '-fuse-ld=lld',
  MINGW_PATH: mingwRoot,
  PATH: [path.join(sdk, 'bin'), path.join(sdk, 'tools', 'bin'), mingwBin, process.env.PATH ?? '']
    .filter(Boolean).join(path.delimiter),
};
await $({env: stageEnv})`set -o pipefail; cjc --version | head -2`;
console.log(`WINDOWS_STAGE3_COMPILER_ASSERT_PASS path=${resolvedCompiler} runtime_ref=${runtimeRef}`);

console.log('[windows-stage3] cross-build source runtime with the official MinGW target');
await $({cwd: runtimeRoot, env: stageEnv})`python3 build.py clean`;
await $({cwd: runtimeRoot, env: stageEnv})`python3 build.py build -t release --target windows-x86_64 --target-toolchain ${mingwBin} -v ${version}`;
await $({cwd: runtimeRoot, env: stageEnv})`python3 build.py install`;
await fs.mkdir(runtimeTarget, {recursive: true});
for (const entry of await fs.readdir(runtimeOutput)) {
  await fs.cp(path.join(runtimeOutput, entry), path.join(runtimeTarget, entry), {
    recursive: true,
    force: true,
  });
}

console.log('[windows-stage3] cross-build final std with stage2 host cjc');
await fs.rm(finalStd, {recursive: true, force: true});
await $({cwd: stdlibRoot, env: stageEnv})`python3 build.py clean`;
await $({cwd: stdlibRoot, env: stageEnv})`python3 build.py build -t release --target windows-x86_64 --target-lib=${runtimeTarget} --target-lib=${mingwLib} --target-sysroot ${mingwRoot}/ --target-toolchain ${mingwBin}`;
await $({cwd: stdlibRoot, env: stageEnv})`python3 build.py install --prefix ${finalStd}`;
await writeStdProvenance({
  sourceDir: stdlibRoot,
  installPrefix: finalStd,
  compiler,
  note: `stage2 Linux host cjc cross-built windows-x64 std with source runtime ${runtimeRef}`,
});
await assertFinalStd(finalStd, target);

const core = path.join(finalStd, 'lib', target.spec.runtimeTuple, 'libcangjie-std-core.a');
const symbols = (await $({stdio: 'pipe'})`nm -A ${core}`).stdout;
if (!symbols.includes('g_cjLoadBadMask') || !/CJ_MCC_Read(?:StaticRef|RefField)/.test(symbols)) {
  throw new Error('Windows final std lacks coloured-runtime barrier symbols');
}
console.log(`WINDOWS_STAGE3_BUILD_PASS target=${target.spec.key} final_std=${finalStd}`);

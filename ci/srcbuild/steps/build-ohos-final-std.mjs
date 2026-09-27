#!/usr/bin/env zx
// Shape: build-windows-final-std.mjs; official cangjie_build/docs/linux_cross_ohos.md:203-228.
// #1196 supplies runtime/build.py --ohos-public-sdk for both architectures.
import fs from 'node:fs/promises';
import path from 'node:path';
import {assertBootstrapCompiler} from '../lib/bootstrap-handoff.mjs';
import {writeStdProvenance} from '../../../build/lib/provenance.mjs';
import {probeRequirement} from '../../release/platform-matrix.mjs';
import {buildOhosRuntime} from '../lib/ohos-runtime.mjs';

$.stdio = 'inherit';
const required = name => {
  if (!process.env[name]) throw new Error(`${name} is required`);
  return process.env[name];
};
if (process.platform !== 'linux' || process.arch !== 'x64') {
  throw new Error('OHOS producer requires the linux-x64 source cell');
}
const workspace = path.resolve(required('CANGJIE_WORKSPACE'));
if (workspace === path.parse(workspace).root) throw new Error('workspace must not be a filesystem root');
const version = required('CJCJ_STAGE3_CANGJIE_VERSION');
const expectedRef = required('RUNTIME_REF');
const probe = probeRequirement('ohos-sdk');
if (!probe.present) throw new Error(probe.detail);
const ohos = path.resolve(probe.detail.slice(probe.detail.indexOf('=') + 1));
const native = path.join(ohos, 'native');
const toolchain = path.join(native, 'llvm');
const sdk = path.join(workspace, 'software', 'cangjie');
const repository = path.join(workspace, 'cangjie_runtime');
const runtime = path.join(repository, 'runtime');
const stdlib = path.join(repository, 'stdlib');
const runtimeRef = (await $({stdio: 'pipe'})`git -C ${repository} rev-parse HEAD`).stdout.trim();
if (runtimeRef !== expectedRef) throw new Error(`runtime source mismatch: ${runtimeRef} != ${expectedRef}`);
const stageEnv = {...process.env, CANGJIE_HOME: sdk, CANGJIE_VERSION: version,
  PATH: [path.join(sdk, 'bin'), path.join(sdk, 'tools', 'bin'), path.join(toolchain, 'bin'), process.env.PATH].join(path.delimiter)};
const assertCompiler = async () => {
  const command = (await $({env: stageEnv, stdio: 'pipe'})`command -v cjc`).stdout.trim();
  await assertBootstrapCompiler({sdk, command});
};
// These builds share runtime/CMakebuild and stdlib/build, so architectures
// run sequentially; each build uses all runner cores. Copy before the next clean.
for (const arch of ['aarch64', 'x86_64']) {
  const tuple = `linux_ohos_${arch}_cjnative`;
  const finalStd = path.join(workspace, 'software', `final-std-ohos-${arch.replace('_', '-')}`);
  await assertCompiler();
  const runtimeInstall = await buildOhosRuntime({workspace, native, arch, version, runtimeRef, env: stageEnv});
  await assertCompiler();
  await fs.rm(finalStd, {recursive: true, force: true});
  await $({cwd: stdlib, env: stageEnv})`python3 build.py clean`;
  await $({cwd: stdlib, env: stageEnv})`python3 build.py build -t release --target ${`ohos-${arch}`} --target-lib=${path.join(runtime, 'output')} --target-lib=${path.join(runtimeInstall, 'runtime', 'lib', tuple)} --target-lib=${path.join(runtimeInstall, 'lib', tuple)} --target-toolchain ${path.join(toolchain, 'bin')} --target-sysroot ${path.join(native, 'sysroot')}`;
  await $({cwd: stdlib, env: stageEnv})`python3 build.py install --prefix ${finalStd}`;
  await assertCompiler();
  await writeStdProvenance({sourceDir: stdlib, installPrefix: finalStd,
    compiler: path.join(sdk, 'bin', 'cjcj-stage2'), note: `OHOS ${arch} final std; runtime ${runtimeRef}`});
  // Keep runtime separate from std so package consumers cannot confuse their provenance.
  const runtimeArtifact = path.join(finalStd, 'cross-runtime');
  await fs.cp(runtimeInstall, runtimeArtifact, {recursive: true});

  for (const relative of [`runtime/lib/${tuple}/libcangjie-std-core.so`, `lib/${tuple}/libcangjie-std-core.a`, `modules/${tuple}/std/std.core.cjo`]) {
    await fs.access(path.join(finalStd, relative));
  }
  await $`file ${path.join(runtimeArtifact, 'runtime', 'lib', tuple, 'libcangjie-runtime.so')} ${path.join(finalStd, 'runtime', 'lib', tuple, 'libcangjie-std-core.so')}`;
  await $`sha256sum ${path.join(runtimeArtifact, 'runtime', 'lib', tuple, 'libcangjie-runtime.so')} ${path.join(finalStd, 'lib', tuple, 'libcangjie-std-core.a')}`;
  console.log(`OHOS_FINAL_STD_BUILT tuple=${tuple} runtime_ref=${runtimeRef} artifact=${finalStd}`);
}

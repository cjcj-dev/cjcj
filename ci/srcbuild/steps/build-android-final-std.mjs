#!/usr/bin/env zx
// Runtime build.py:36,241-280 and stdlib/build.py:51,140-143 use API 23
// for the unversioned linux_android_aarch64_cjnative tuple.
import fs from 'node:fs/promises';
import path from 'node:path';
import {assertBootstrapCompiler} from '../lib/bootstrap-handoff.mjs';
import {writeStdProvenance} from '../../../build/lib/provenance.mjs';
import {probeRequirement} from '../../release/platform-matrix.mjs';
import {writeCrossRuntimeManifest} from '../../release/cross-runtime.mjs';

$.stdio = 'inherit';
const required = name => {
  if (!process.env[name]) throw new Error(`${name} is required`);
  return process.env[name];
};
if (process.platform !== 'linux' || process.arch !== 'x64') {
  throw new Error('Android producer requires the linux-x64 source cell');
}
const workspace = path.resolve(required('CANGJIE_WORKSPACE'));
if (workspace === path.parse(workspace).root) throw new Error('workspace must not be a filesystem root');
const version = required('CJCJ_STAGE3_CANGJIE_VERSION');
const expectedRef = required('RUNTIME_REF');
const probe = probeRequirement('android-ndk');
if (!probe.present) throw new Error(probe.detail);
const ndk = path.resolve(probe.detail.slice(probe.detail.indexOf('=') + 1));
const toolchain = path.join(ndk, 'toolchains', 'llvm', 'prebuilt', 'linux-x86_64');
const sdk = path.join(workspace, 'software', 'cangjie');
const repository = path.join(workspace, 'cangjie_runtime');
const runtime = path.join(repository, 'runtime');
const stdlib = path.join(repository, 'stdlib');
const tuple = 'linux_android_aarch64_cjnative';
const finalStd = path.join(workspace, 'software', 'final-std-android-aarch64');
const runtimeInstall = path.join(runtime, 'output', 'linux_android_release_aarch64');
const runtimeRef = (await $({stdio: 'pipe'})`git -C ${repository} rev-parse HEAD`).stdout.trim();
if (runtimeRef !== expectedRef) throw new Error(`runtime source mismatch: ${runtimeRef} != ${expectedRef}`);
const stageEnv = {...process.env, CANGJIE_HOME: sdk, CANGJIE_VERSION: version,
  PATH: [path.join(sdk, 'bin'), path.join(sdk, 'tools', 'bin'), path.join(toolchain, 'bin'), process.env.PATH].join(path.delimiter)};
const assertCompiler = async () => {
  const command = (await $({env: stageEnv, stdio: 'pipe'})`command -v cjc`).stdout.trim();
  await assertBootstrapCompiler({sdk, command});
};
await assertCompiler();
await $({cwd: runtime, env: stageEnv})`python3 build.py clean`;
await $({cwd: runtime, env: stageEnv})`python3 build.py build -t release --target android-aarch64 --target-toolchain ${path.join(ndk, 'toolchains')} -v ${version}`;
await $({cwd: runtime, env: stageEnv})`python3 build.py install`;
await assertCompiler();
await fs.rm(finalStd, {recursive: true, force: true});
await $({cwd: stdlib, env: stageEnv})`python3 build.py clean`;
await $({cwd: stdlib, env: stageEnv})`python3 build.py build -t release --target android-aarch64 --target-lib=${path.join(runtimeInstall, 'runtime', 'lib', tuple)} --target-lib=${path.join(runtimeInstall, 'lib', tuple)} --target-toolchain ${path.join(toolchain, 'bin')} --target-sysroot ${path.join(toolchain, 'sysroot')}`;
await $({cwd: stdlib, env: stageEnv})`python3 build.py install --prefix ${finalStd}`;
await assertCompiler();
await writeStdProvenance({sourceDir: stdlib, installPrefix: finalStd,
  compiler: path.join(sdk, 'bin', 'cjcj-stage2'), note: `Android API 23 final std; runtime ${runtimeRef}`});
// Keep runtime separate from std so package consumers cannot confuse their provenance.
const runtimeArtifact = path.join(finalStd, 'cross-runtime');
await fs.cp(runtimeInstall, runtimeArtifact, {recursive: true});
await writeCrossRuntimeManifest({root: runtimeArtifact, tuple, runtimeRef});
for (const relative of [`runtime/lib/${tuple}/libcangjie-std-core.so`, `lib/${tuple}/libcangjie-std-core.a`, `modules/${tuple}/std/core.cjo`]) {
  // Module spelling is std.core.cjo in the compiler's installed tuple layout.
  const file = relative.endsWith('/core.cjo') ? relative.replace('/core.cjo', '/std.core.cjo') : relative;
  await fs.access(path.join(finalStd, file));
}
await $`file ${path.join(runtimeArtifact, 'runtime', 'lib', tuple, 'libcangjie-runtime.so')} ${path.join(finalStd, 'runtime', 'lib', tuple, 'libcangjie-std-core.so')}`;
await $`sha256sum ${path.join(runtimeArtifact, 'runtime', 'lib', tuple, 'libcangjie-runtime.so')} ${path.join(finalStd, 'lib', tuple, 'libcangjie-std-core.a')}`;
console.log(`ANDROID_FINAL_STD_BUILT tuple=${tuple} runtime_ref=${runtimeRef} artifact=${finalStd}`);

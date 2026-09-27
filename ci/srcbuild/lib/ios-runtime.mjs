import fs from 'node:fs/promises';
import path from 'node:path';
import {writeCrossRuntimeManifest} from '../../release/cross-runtime.mjs';

// runtime/build.py:284-328 selects the three iOS build variants; install:359-370
// keeps lib/<tuple> and runtime/lib/<tuple> under the requested prefix.
export const iosTargets = Object.freeze([
  {target: 'ios-aarch64', tuple: 'ios_aarch64_cjnative', sdk: 'iphoneos', arch: 'arm64', runtimeArch: 'aarch64'},
  {target: 'ios-simulator-aarch64', tuple: 'ios_simulator_aarch64_cjnative', sdk: 'iphonesimulator', arch: 'arm64', runtimeArch: 'aarch64'},
  {target: 'ios-simulator-x86_64', tuple: 'ios_simulator_x86_64_cjnative', sdk: 'iphonesimulator', arch: 'x86_64', runtimeArch: 'x86_64'},
]);

export async function buildIosRuntime({source, target, sysroot, toolBin, version, runtimeRef, env = process.env}) {
  const runtime = path.join(source, 'runtime');
  const root = path.join(source, 'runtime-install');
  await $({cwd: runtime, env})`python3 build.py build -t release --target ${target.target} --target-toolchain ${path.dirname(toolBin)} --target-sysroot ${sysroot} -v ${version}`;
  await $({cwd: runtime, env})`python3 build.py install --prefix ${root}`;
  // CMakeLists.txt installs boundscheck only for macOS. As in the Android
  // producer, carry the dependency from this same cross build, never host SDK.
  await fs.copyFile(path.join(runtime, 'CMakebuild', 'runtime-staging', 'lib', `${target.runtimeArch}_Release`, 'libboundscheck.dylib'),
    path.join(root, 'runtime', 'lib', target.tuple, 'libboundscheck.dylib'));
  await writeCrossRuntimeManifest({root, tuple: target.tuple, runtimeRef});
  return root;
}

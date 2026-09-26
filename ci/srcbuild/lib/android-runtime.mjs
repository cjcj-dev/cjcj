import path from 'node:path';
import {writeCrossRuntimeManifest} from '../../release/cross-runtime.mjs';

// The source cell and the standalone runner build use the same runtime entry.
export async function buildAndroidRuntime({workspace, ndk, version, runtimeRef, env = process.env}) {
  const repository = path.join(workspace, 'cangjie_runtime');
  const runtime = path.join(repository, 'runtime');
  const actualRef = (await $({stdio: 'pipe'})`git -C ${repository} rev-parse HEAD`).stdout.trim();
  if (actualRef !== runtimeRef) throw new Error(`runtime source mismatch: ${actualRef} != ${runtimeRef}`);
  await $({cwd: runtime, env})`python3 build.py clean`;
  await $({cwd: runtime, env})`python3 build.py build -t release --target android-aarch64 --prefix ${path.join(runtime, 'output', 'common')} --target-toolchain ${path.join(ndk, 'toolchains')} -v ${version}`;
  await $({cwd: runtime, env})`python3 build.py install`;
  const root = path.join(runtime, 'output', 'common', 'linux_android_release_aarch64');
  await writeCrossRuntimeManifest({root, tuple: 'linux_android_aarch64_cjnative', runtimeRef});
  return root;
}

import path from 'node:path';
import fs from 'node:fs/promises';
import {writeCrossRuntimeManifest} from '../../release/cross-runtime.mjs';

// runtime/build.py --ohos-public-sdk feeds the same native root to runtime
// and cjthread; never construct a private OHOS_ROOT or rename libc++.so.
export async function buildOhosRuntime({workspace, native, arch, version, runtimeRef, env = process.env}) {
  if (!['aarch64', 'x86_64'].includes(arch)) throw new Error(`unsupported OHOS architecture: ${arch}`);
  const repository = path.join(workspace, 'cangjie_runtime');
  const runtime = path.join(repository, 'runtime');
  const actualRef = (await $({stdio: 'pipe'})`git -C ${repository} rev-parse HEAD`).stdout.trim();
  if (actualRef !== runtimeRef) throw new Error(`runtime source mismatch: ${actualRef} != ${runtimeRef}`);
  await $({cwd: runtime, env})`python3 build.py clean`;
  await $({cwd: runtime, env})`python3 build.py build -t release --target ${`ohos-${arch}`} --prefix ${path.join(runtime, 'output', 'common')} --ohos-public-sdk ${native} -v ${version}`;
  await $({cwd: runtime, env})`python3 build.py install`;
  const root = path.join(runtime, 'output', 'common', `linux_ohos_release_${arch}`);
  const tuple = `linux_ohos_${arch}_cjnative`;
  // Same dependency staging as the Android producer: the Linux-host install
  // does not install boundscheck, so use this invocation's target build output.
  await fs.copyFile(path.join(runtime, 'CMakebuild', 'runtime-staging', 'lib', `${arch}_Release`, 'libboundscheck.so'),
    path.join(root, 'runtime', 'lib', tuple, 'libboundscheck.so'));
  await writeCrossRuntimeManifest({root, tuple, runtimeRef});
  return root;
}

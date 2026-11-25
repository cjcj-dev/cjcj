import {crossBuildJobs} from './cross-build-jobs.mjs';
import {fileURLToPath} from 'node:url';
import {checkExports, targetRef} from './ohos-split-sdk.mjs';
import path from 'node:path';
import fs from 'node:fs/promises';
import {writeCrossRuntimeManifest} from '../../release/cross-runtime.mjs';

// Read the completed runtime configure, before installing or publishing its output.
export async function readLocalExportFlag(cacheFile) {
  const cache = await fs.readFile(cacheFile, 'utf8');
  const entries = cache.split(/\r?\n/).filter(line => line.startsWith('GLOBAL_EXPORT_FLAG:'));
  const match = entries.length === 1 && /^GLOBAL_EXPORT_FLAG:(?:STRING|UNINITIALIZED)=(.*)$/.exec(entries[0]);
  if (!match || match[1] !== '0') {
    throw Error(`expected GLOBAL_EXPORT_FLAG=0 in ${cacheFile}; got ${JSON.stringify(entries)}`);
  }
  return match[1];
}

// runtime/build.py --ohos-public-sdk feeds the same native root to runtime
// and cjthread; never construct a private OHOS_ROOT or rename libc++.so.
export async function buildOhosRuntime({workspace, native, arch, version, runtimeRef, localExport = false, python, env = process.env}) {
  env = {...env, CANGJIE_BUILD_JOBS: String(crossBuildJobs(env))};
  if (!['aarch64', 'x86_64'].includes(arch)) throw new Error(`unsupported OHOS architecture: ${arch}`);
  const repository = path.join(workspace, 'cangjie_runtime');
  const runtime = path.join(repository, 'runtime');
  const actualRef = (await $({stdio: 'pipe'})`git -C ${repository} rev-parse HEAD`).stdout.trim();
  if (actualRef !== runtimeRef) throw new Error(`runtime source mismatch: ${actualRef} != ${runtimeRef}`);
  if (localExport) {
    if (arch !== 'aarch64' || actualRef !== targetRef) throw Error('unsupported local-export runtime');
    env = {...env, CJCJ_PARENT_RUNTIME_TOOLCHAIN:env.CMAKE_TOOLCHAIN_FILE || '',
      CMAKE_TOOLCHAIN_FILE:fileURLToPath(new URL('./ohos-local-export.cmake', import.meta.url))};
  }
  await $({cwd: runtime, env})`${python} build.py clean`;
  await $({cwd: runtime, env})`${python} build.py build -t release --target ${`ohos-${arch}`} --prefix ${path.join(runtime, 'output', 'common')} --ohos-public-sdk ${native} -v ${version}`;
  const globalExportFlag = localExport
    ? await readLocalExportFlag(path.join(runtime, 'CMakebuild', 'CMakeCache.txt')) : undefined;
  await $({cwd: runtime, env})`${python} build.py install`;
  const root = path.join(runtime, 'output', 'common', `linux_ohos_release_${arch}`);
  const tuple = `linux_ohos_${arch}_cjnative`;
  // Same dependency staging as the Android producer: the Linux-host install
  // does not install boundscheck, so use this invocation's target build output.
  await fs.copyFile(path.join(runtime, 'CMakebuild', 'runtime-staging', 'lib', `${arch}_Release`, 'libboundscheck.so'),
    path.join(root, 'runtime', 'lib', tuple, 'libboundscheck.so'));
  if (localExport) {
    const link = await fs.readFile(path.join(runtime, 'CMakebuild/src/CMakeFiles/cangjie-runtime.dir/link.txt'), 'utf8');
    if (!/--version-script[=,][^\s]*\/ohos_local_export\.map\b/.test(link)) throw Error('wrong OHOS runtime export map');
    await checkExports(root);
  }
  const sourceRepository = localExport
    ? (await $({stdio:'pipe'})`git -C ${repository} remote get-url origin`).stdout.trim() : undefined;
  await writeCrossRuntimeManifest({root, tuple, runtimeRef, sourceRepository});
  return {root, globalExportFlag};
}

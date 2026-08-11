// Port of cangjie-build/src/cangjie_build/stages/stdlib.py.

import path from 'node:path';
import {stage} from '../../lib/logging.mjs';
import {writeStdProvenance} from '../../lib/provenance.mjs';
import {assertRuntimeCommonCache, assertRuntimeSplit} from '../../lib/runtime-split.mjs';
import {installPath, TARGET_TRIPLE} from '../../toolchain/mingw.mjs';
import {copyContents, hostCompilerEnv, opensslLibPath, runBuildPy, windowsCrossArgs} from './common.mjs';

export async function run(config) {
  const stdlibRoot = path.join(config.repoPath('runtime'), 'stdlib');
  const runtimeTarget = path.join(config.repoPath('runtime'), 'runtime', 'target');
  const stdlibOutput = path.join(stdlibRoot, 'output');
  const compilerOutput = path.join(config.repoPath('compiler'), 'output');
  const compilerSuffix = config.target.spec.crossCompile ? '' : config.target.spec.exeSuffix;
  const compiler = path.join(compilerOutput, 'bin', `cjc${compilerSuffix}`);
  const nativeTargetLibs = [runtimeTarget, opensslLibPath(config)].filter(Boolean);

  await stage('stdlib', async () => {
    let split;
    if (process.env.CANGJIE_BUILD_DRY_RUN !== '1') {
      split = assertRuntimeSplit({
        hostSdk: process.env.CJCJ_SRCBUILD_HOST_SDK,
        targetSdk: compilerOutput,
        target: config.target,
      });
    }
    const hostEnv = split ? hostCompilerEnv(config, {hostRuntime: split.hostRuntime}) : undefined;
    await runBuildPy(config, stdlibRoot, ['clean'], {stageName: 'stdlib.clean.host'});
    await runBuildPy(config, stdlibRoot, [
      'build', '-t', config.buildType, '--target', 'native',
      ...nativeTargetLibs.map(directory => `--target-lib=${directory}`),
    ], {stageName: 'stdlib.build.host', extraEnv: hostEnv});
    if (process.env.CANGJIE_BUILD_DRY_RUN !== '1') {
      assertRuntimeCommonCache({
        cache: path.join(stdlibRoot, 'build', 'build', 'CMakeCache.txt'),
        runtimeTarget,
      });
    }
    await runBuildPy(config, stdlibRoot, ['install'], {
      stageName: 'stdlib.install.host', extraEnv: hostEnv,
    });
    if (process.env.CANGJIE_BUILD_DRY_RUN !== '1') {
      await writeStdProvenance({sourceDir: stdlibRoot, installPrefix: stdlibOutput, compiler});
    }
    copyContents(stdlibOutput, compilerOutput, {stage: 'stdlib.copy.host'});
    if (!config.target.spec.crossCompile) return;

    await runBuildPy(config, stdlibRoot, ['clean'], {stageName: 'stdlib.clean.windows'});
    const mingwLib = path.join(installPath(config.buildRoot), TARGET_TRIPLE, 'lib');
    await runBuildPy(config, stdlibRoot, [
      'build', '-t', config.crossBuildType,
      `--target-lib=${runtimeTarget}`,
      `--target-lib=${mingwLib}`,
      ...windowsCrossArgs(config),
    ], {stageName: 'stdlib.build.windows'});
    await runBuildPy(config, stdlibRoot, ['install'], {stageName: 'stdlib.install.windows'});
    if (process.env.CANGJIE_BUILD_DRY_RUN !== '1') {
      await writeStdProvenance({sourceDir: stdlibRoot, installPrefix: stdlibOutput, compiler});
    }
    copyContents(stdlibOutput, compilerOutput, {stage: 'stdlib.copy.windows.host'});
    copyContents(stdlibOutput, path.join(config.repoPath('compiler'), 'output-x86_64-w64-mingw32'), {
      stage: 'stdlib.copy.windows.cross',
    });
  });
}

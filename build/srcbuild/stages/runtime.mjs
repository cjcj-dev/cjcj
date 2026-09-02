// Port of cangjie-build/src/cangjie_build/stages/runtime.py.

import path from 'node:path';
import {stage} from '../../lib/logging.mjs';
import {assertRuntimeSplit} from '../../lib/runtime-split.mjs';
import {
  beginGcUnitLanguageDeferral,
  finishGcUnitLanguageDeferral,
  gcUnitRuntimeBuildEnv,
} from '../gc-unit-gate.mjs';
import {copyContents, ensureDir, runBuildPy, windowsCrossArgs} from './common.mjs';

export async function run(config) {
  const runtimeRoot = path.join(config.repoPath('runtime'), 'runtime');
  const targetDir = path.join(runtimeRoot, 'target');
  const compilerOutput = path.join(config.repoPath('compiler'), 'output');

  await stage('runtime', async () => {
    beginGcUnitLanguageDeferral(config, runtimeRoot, compilerOutput);
    ensureDir(targetDir);
    await runBuildPy(config, runtimeRoot, ['clean'], {stageName: 'runtime.clean.host'});
    await runBuildPy(config, runtimeRoot, [
      'build', '--target', 'native', '-t', config.buildType, '-v', config.cangjieVersion,
    ], {
      stageName: 'runtime.build.host',
      extraEnv: gcUnitRuntimeBuildEnv(config),
    });
    await runBuildPy(config, runtimeRoot, ['install'], {stageName: 'runtime.install.host'});
    copyContents(path.join(runtimeRoot, 'output'), targetDir, {stage: 'runtime.snapshot.host'});

    const hostSubdir = path.join(
      runtimeRoot, 'output', 'common', config.target.hostRuntimeOutputSubdir(config.buildType),
    );
    for (const subdirectory of ['lib', 'runtime']) {
      copyContents(path.join(hostSubdir, subdirectory), path.join(compilerOutput, subdirectory), {
        stage: 'runtime.copy.host',
      });
    }
    finishGcUnitLanguageDeferral(config, runtimeRoot, compilerOutput);
    if (!config.target.spec.crossCompile) {
      if (process.env.CANGJIE_BUILD_DRY_RUN !== '1') {
        assertRuntimeSplit({
          hostSdk: process.env.CJCJ_SRCBUILD_HOST_SDK,
          targetSdk: compilerOutput,
          target: config.target,
        });
      }
      return;
    }

    await runBuildPy(config, runtimeRoot, ['clean'], {stageName: 'runtime.clean.windows'});
    await runBuildPy(config, runtimeRoot, [
      'build', '-t', config.crossBuildType,
      ...windowsCrossArgs(config, {sysroot: false}),
      '-v', config.cangjieVersion,
    ], {stageName: 'runtime.build.windows'});
    await runBuildPy(config, runtimeRoot, ['install'], {stageName: 'runtime.install.windows'});
    copyContents(path.join(runtimeRoot, 'output'), targetDir, {stage: 'runtime.snapshot.windows'});

    const windowsSubdir = path.join(
      runtimeRoot, 'output', 'common', config.target.runtimeOutputSubdir(config.crossBuildType),
    );
    const compilerMingwOutput = path.join(config.repoPath('compiler'), 'output-x86_64-w64-mingw32');
    for (const subdirectory of ['lib', 'runtime']) {
      copyContents(path.join(windowsSubdir, subdirectory), path.join(compilerOutput, subdirectory), {
        stage: 'runtime.copy.windows.host',
      });
      copyContents(path.join(windowsSubdir, subdirectory), path.join(compilerMingwOutput, subdirectory), {
        stage: 'runtime.copy.windows.cross',
      });
    }
    if (process.env.CANGJIE_BUILD_DRY_RUN !== '1') {
      assertRuntimeSplit({
        hostSdk: process.env.CJCJ_SRCBUILD_HOST_SDK,
        targetSdk: compilerOutput,
        target: config.target,
      });
    }
  });
}

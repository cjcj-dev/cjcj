// Port of cangjie-build/src/cangjie_build/stages/runtime.py.

import path from 'node:path';
import {stage} from '../../lib/logging.mjs';
import {copyContents, ensureDir, runBuildPy, windowsCrossArgs} from './common.mjs';

export async function run(config) {
  const runtimeRoot = path.join(config.repoPath('runtime'), 'runtime');
  const targetDir = path.join(runtimeRoot, 'target');
  const compilerOutput = path.join(config.repoPath('compiler'), 'output');

  await stage('runtime', async () => {
    ensureDir(targetDir);
    await runBuildPy(config, runtimeRoot, ['clean'], {stageName: 'runtime.clean.linux'});
    await runBuildPy(config, runtimeRoot, [
      'build', '-t', config.buildType, '-v', config.cangjieVersion,
    ], {stageName: 'runtime.build.linux'});
    await runBuildPy(config, runtimeRoot, ['install'], {stageName: 'runtime.install.linux'});
    copyContents(path.join(runtimeRoot, 'output'), targetDir, {stage: 'runtime.snapshot.linux'});

    const linuxSubdir = path.join(runtimeRoot, 'output', 'common', `linux_${config.buildType.toLowerCase()}_x86_64`);
    for (const subdirectory of ['lib', 'runtime']) {
      copyContents(path.join(linuxSubdir, subdirectory), path.join(compilerOutput, subdirectory), {
        stage: 'runtime.copy.linux',
      });
    }
    if (!config.target.spec.crossCompile) return;

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
  });
}

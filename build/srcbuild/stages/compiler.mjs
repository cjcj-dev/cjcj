// Port of cangjie-build/src/cangjie_build/stages/compiler.py.

import fs from 'node:fs';
import path from 'node:path';
import {stage} from '../../lib/logging.mjs';
import {run as runCommand} from '../../lib/runner.mjs';
import * as staticLibs from '../../toolchain/static-libs.mjs';
import * as targetPython from '../../toolchain/target-python.mjs';
import {
  copyContents,
  mergedEnv,
  pythonExe,
  requireDir,
  runBuildPy,
  windowsCrossArgs,
} from './common.mjs';

export async function run(config) {
  const repoDir = config.repoPath('compiler');
  await stage('compiler', async () => {
    await runBuildPy(config, repoDir, ['clean'], {stageName: 'compiler.clean'});

    if (config.target.spec.crossCompile) {
      await runBuildPy(config, repoDir, [
        'build', '-t', config.buildType, '--no-tests', '-v', config.cangjieVersion,
      ], {stageName: 'compiler.build.host'});
      const crossArgs = windowsCrossArgs(config);
      const targetPythonPath = await targetPython.install(config.buildRoot);
      const targetPythonEnv = {TARGET_PYTHON_PATH: targetPythonPath};
      await runBuildPy(config, repoDir, [
        'build', '-t', config.crossBuildType,
        '--product', 'cjc', '--no-tests', '--build-cjdb',
        '-v', config.cangjieVersion, ...crossArgs,
      ], {stageName: 'compiler.build.windows.cjc', extraEnv: targetPythonEnv});
      await runBuildPy(config, repoDir, [
        'build', '-t', config.crossBuildType,
        '--product', 'libs', '-v', config.cangjieVersion, ...crossArgs,
      ], {stageName: 'compiler.build.windows.libs', extraEnv: targetPythonEnv});
      await runBuildPy(config, repoDir, ['install', '--host', 'windows-x86_64'], {
        stageName: 'compiler.install.windows', extraEnv: targetPythonEnv,
      });
      await runBuildPy(config, repoDir, ['install'], {stageName: 'compiler.install.host'});
      await targetPython.installRuntimeDlls(
        targetPythonPath,
        path.join(repoDir, 'output-x86_64-w64-mingw32', 'tools', 'bin'),
      );
      copyContents(
        path.join(repoDir, 'output-x86_64-w64-mingw32'),
        path.join(repoDir, 'output'),
        {stage: 'compiler.merge'},
      );
      return;
    }

    const targetLib = staticLibs.targetLibPath(config.buildRoot);
    const buildArgs = [
      'build', '-t', config.buildType, '--no-tests', '--build-cjdb', '-v', config.cangjieVersion,
    ];
    if (fs.existsSync(targetLib)) buildArgs.push('--target-lib', targetLib);
    await runBuildPy(config, repoDir, buildArgs, {stageName: 'compiler.build.native'});
    await runBuildPy(config, repoDir, ['install'], {stageName: 'compiler.install'});
  });
}

export async function runTests(config) {
  if (config.target.spec.crossCompile) return;
  const repoDir = config.repoPath('compiler');
  const envsetup = path.join(repoDir, 'output', 'envsetup.sh');
  requireDir(repoDir, {stage: 'compiler.test'});
  if (!fs.statSync(envsetup, {throwIfNoEntry: false})?.isFile()) throw new Error(envsetup);
  await runCommand(['bash', '-c', `set -e; source '${envsetup}'; ${pythonExe()} build.py test`], {
    cwd: repoDir, envOverlay: mergedEnv(config), stage: 'compiler.test',
  });
}

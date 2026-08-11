// Port of cangjie-build/src/cangjie_build/stages/stdx.py.

import path from 'node:path';
import {stage} from '../../lib/logging.mjs';
import {assertHostRuntimeCommands, assertRuntimeSplit} from '../../lib/runtime-split.mjs';
import {installPath, TARGET_TRIPLE} from '../../toolchain/mingw.mjs';
import {opensslLibPath, runBuildPy, windowsCrossArgs} from './common.mjs';

export async function run(config) {
  const stdxRoot = config.repoPath('stdx');
  const compilerInclude = path.join(config.repoPath('compiler'), 'include');
  await stage('stdx', async () => {
    let split;
    if (process.env.CANGJIE_BUILD_DRY_RUN !== '1') {
      split = assertRuntimeSplit({
        hostSdk: process.env.CJCJ_SRCBUILD_HOST_SDK,
        targetSdk: path.join(config.repoPath('compiler'), 'output'),
        target: config.target,
      });
    }
    const hostClosureEnv = split
      ? {STDX_HOST_CANGJIE_HOME: process.env.CJCJ_SRCBUILD_HOST_SDK}
      : undefined;
    await runBuildPy(config, stdxRoot, ['clean'], {stageName: 'stdx.clean'});
    let args;
    if (config.target.spec.crossCompile) {
      const mingwLib = path.join(installPath(config.buildRoot), TARGET_TRIPLE, 'lib');
      args = [
        'build', '-t', config.crossBuildType,
        `--include=${compilerInclude}`,
        `--target-lib=${mingwLib}`,
        ...windowsCrossArgs(config),
      ];
    } else {
      args = ['build', '-t', config.buildType, `--include=${compilerInclude}`];
      const openssl = opensslLibPath(config);
      if (openssl) args.push(`--target-lib=${openssl}`);
    }
    await runBuildPy(config, stdxRoot, args, {stageName: 'stdx.build', extraEnv: hostClosureEnv});
    if (split) {
      assertHostRuntimeCommands({
        buildFile: path.join(stdxRoot, 'build_temp', 'build', 'build.ninja'),
        hostRuntime: split.hostRuntime,
        targetRuntime: split.targetRuntime,
        loaderEnv: config.target.spec.loaderEnv,
      });
    }
    await runBuildPy(config, stdxRoot, ['install'], {
      stageName: 'stdx.install', extraEnv: hostClosureEnv,
    });
  });
}

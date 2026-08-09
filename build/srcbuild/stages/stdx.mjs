// Port of cangjie-build/src/cangjie_build/stages/stdx.py.

import path from 'node:path';
import {stage} from '../../lib/logging.mjs';
import {installPath, TARGET_TRIPLE} from '../../toolchain/mingw.mjs';
import {opensslLibPath, runBuildPy, windowsCrossArgs} from './common.mjs';

export async function run(config) {
  const stdxRoot = config.repoPath('stdx');
  const compilerInclude = path.join(config.repoPath('compiler'), 'include');
  await stage('stdx', async () => {
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
    await runBuildPy(config, stdxRoot, args, {stageName: 'stdx.build'});
    await runBuildPy(config, stdxRoot, ['install'], {stageName: 'stdx.install'});
  });
}

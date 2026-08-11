// Port of cangjie-build/src/cangjie_build/stages/verify.py.

import fs from 'node:fs';
import path from 'node:path';
import {BuildError} from '../../lib/errors.mjs';
import {getLogger, stage} from '../../lib/logging.mjs';
import {run as runCommand} from '../../lib/runner.mjs';
import {assertRuntimeSplit, hostLoaderPath, targetLoaderPath} from '../../lib/runtime-split.mjs';
import {ensureDir, requireFile} from './common.mjs';

const logger = getLogger('cangjie_build.stages.verify');
const HELLO_SOURCE = 'main() { println("Hello, Cangjie") }\n';

export async function run(config) {
  const cangjieDir = path.join(config.softwareDir, 'cangjie');
  const suffix = config.target.spec.exeSuffix;
  if (config.target.spec.crossCompile) {
    requireFile(path.join(cangjieDir, 'bin', `cjc${suffix}`), {stage: 'verify.cjc'});
    requireFile(path.join(cangjieDir, 'tools', 'bin', `cjpm${suffix}`), {stage: 'verify.cjpm'});
    logger.info('Cross-compile target; SDK artifacts present');
    return;
  }

  const envsetup = requireFile(path.join(cangjieDir, 'envsetup.sh'), {stage: 'verify'});
  const work = ensureDir(path.join(config.workspace, 'verify'));
  fs.writeFileSync(path.join(work, 'hello.cj'), HELLO_SOURCE, 'utf8');
  if (process.env.CANGJIE_BUILD_DRY_RUN !== '1') {
    assertRuntimeSplit({
      hostSdk: process.env.CJCJ_SRCBUILD_HOST_SDK,
      targetSdk: cangjieDir,
      target: config.target,
    });
  }
  const hostLibraries = process.env.CANGJIE_BUILD_DRY_RUN === '1' ? '<HOST_LIBRARIES>' : hostLoaderPath({
    hostSdk: process.env.CJCJ_SRCBUILD_HOST_SDK,
    targetSdk: cangjieDir,
    target: config.target,
  });
  const targetLibraries = process.env.CANGJIE_BUILD_DRY_RUN === '1' ? '<TARGET_LIBRARIES>' : targetLoaderPath({
    targetSdk: cangjieDir,
    target: config.target,
  });
  const hostCompiler = process.env.CANGJIE_BUILD_DRY_RUN === '1'
    ? '<HOST_CJC>'
    : requireFile(path.join(process.env.CJCJ_SRCBUILD_HOST_SDK, 'bin', 'cjc'), {stage: 'verify.host-cjc'});
  await stage('verify', async () => {
    await runCommand([
      'bash', '-c',
      'set -e; source "$1"; export "$2=$3"; "$5" hello.cj -o hello; export "$2=$4"; ./hello',
      'srcbuild-verify', envsetup, config.target.spec.loaderEnv, hostLibraries, targetLibraries, hostCompiler,
    ], {
      cwd: work, stage: 'verify.hello',
    });
    if (!fs.existsSync(path.join(work, 'hello'))) {
      throw new BuildError('verify', 'hello binary was not produced');
    }
  });
}

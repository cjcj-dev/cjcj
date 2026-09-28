// Port of cangjie-build/src/cangjie_build/stages/verify.py.

import fs from 'node:fs';
import path from 'node:path';
import {BuildError} from '../../lib/errors.mjs';
import {getLogger, stage} from '../../lib/logging.mjs';
import {run as runCommand} from '../../lib/runner.mjs';
import {sdkEnvironment} from '../../lib/sdk-environment.mjs';
import {assertGcUnitLanguageDone} from '../gc-unit-gate.mjs';
import {ensureDir, requireFile} from './common.mjs';
import {assertPackagedLineage} from '../../lib/package-lineage.mjs';

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

  requireFile(path.join(cangjieDir, 'envsetup.sh'), {stage: 'verify'});
  const work = ensureDir(path.join(config.workspace, 'verify'));
  fs.writeFileSync(path.join(work, 'hello.cj'), HELLO_SOURCE, 'utf8');
  const compiler = requireFile(path.join(cangjieDir, 'bin', `cjc${suffix}`), {stage: 'verify.cjc'});
  await stage('verify', async () => {
    assertGcUnitLanguageDone(config, cangjieDir);
    if (process.env.CANGJIE_BUILD_DRY_RUN !== '1') {
      await assertPackagedLineage(cangjieDir, {
        allowNightlyStd: process.env.CJCJ_ALLOW_NIGHTLY_STD === '1',
      });
    }
    const activated = process.env.CANGJIE_BUILD_DRY_RUN === '1' ? {} : sdkEnvironment(cangjieDir);
    const envOverlay = Object.fromEntries(Object.keys(process.env).map(key => [key, null]));
    Object.assign(envOverlay, activated);
    await runCommand([
      'bash', '--noprofile', '--norc', '-c',
      'set -e; "$1" hello.cj -o hello; ./hello',
      'srcbuild-verify', compiler,
    ], {
      cwd: work, stage: 'verify.hello', envOverlay,
    });
    if (!fs.existsSync(path.join(work, 'hello'))) {
      throw new BuildError('verify', 'hello binary was not produced');
    }
  });
}

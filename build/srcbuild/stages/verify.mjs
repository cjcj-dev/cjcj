// Port of cangjie-build/src/cangjie_build/stages/verify.py.

import fs from 'node:fs';
import path from 'node:path';
import {BuildError} from '../../lib/errors.mjs';
import {getLogger, stage} from '../../lib/logging.mjs';
import {run as runCommand} from '../../lib/runner.mjs';
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
  await stage('verify', async () => {
    await runCommand(['bash', '-c', `set -e; source '${envsetup}'; cjc hello.cj -o hello && ./hello`], {
      cwd: work, stage: 'verify.hello',
    });
    if (!fs.existsSync(path.join(work, 'hello'))) {
      throw new BuildError('verify', 'hello binary was not produced');
    }
  });
}

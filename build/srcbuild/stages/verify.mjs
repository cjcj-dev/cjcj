// Port of cangjie-build/src/cangjie_build/stages/verify.py.

import path from 'node:path';
import {getLogger, stage} from '../../lib/logging.mjs';
import {verifyInstall} from '../../../ci/bootstrap/sdk-verify-install.mjs';
import {assertRuntimeSplit} from '../../lib/runtime-split.mjs';
import {runGcUnitLanguageTests} from '../gc-unit-gate.mjs';
import {bootstrapHostSdk, ensureDir, requireFile} from './common.mjs';
import {assertPackagedLineage} from '../../lib/package-lineage.mjs';

const logger = getLogger('cangjie_build.stages.verify');

export async function run(config) {
  const cangjieDir = path.join(config.softwareDir, 'cangjie');
  const suffix = config.target.spec.exeSuffix;
  if (config.target.spec.crossCompile) {
    requireFile(path.join(cangjieDir, 'bin', `cjc${suffix}`), {stage: 'verify.cjc'});
    requireFile(path.join(cangjieDir, 'tools', 'bin', `cjpm${suffix}`), {stage: 'verify.cjpm'});
    logger.info('Cross-compile target; SDK artifacts present');
    return;
  }

  const work = ensureDir(path.join(config.workspace, 'verify'));
  await stage('verify', async () => {
    if(process.env.CANGJIE_BUILD_DRY_RUN!=='1')await runGcUnitLanguageTests(config,cangjieDir);
    if (process.env.CANGJIE_BUILD_DRY_RUN !== '1') {
      assertRuntimeSplit({hostSdk:bootstrapHostSdk(config),targetSdk:cangjieDir,target:config.target});
      await assertPackagedLineage(cangjieDir, {
        allowNightlyStd:process.env.CJCJ_ALLOW_NIGHTLY_STD==='1',officialRoot:config.officialSdkRoot,
      });
      await verifyInstall({sdk:cangjieDir,work,platform:config.target.spec.llvmPlatform});
    }
  });
}

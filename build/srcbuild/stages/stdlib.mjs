// Port of cangjie-build/src/cangjie_build/stages/stdlib.py, with the cjcj sticky std variant.

import fs from 'node:fs';
import path from 'node:path';
import {BuildError} from '../../lib/errors.mjs';
import {getLogger, stage} from '../../lib/logging.mjs';
import {run as runCommand} from '../../lib/runner.mjs';
import {
  OPTIMIZED_STD_SUBDIR,
  STICKY_LLC_OPTION,
  compareStdCjos,
  copyCompiledStdLibraries,
  createStickySdkOverlay,
  stickyPreflight,
} from '../../lib/std-variants.mjs';
import {installPath, TARGET_TRIPLE} from '../../toolchain/mingw.mjs';
import {copyContents, runBuildPy, windowsCrossArgs} from './common.mjs';

const logger = getLogger('cangjie_build.stdlib');
const LINUX_LIB_PATH = 'linux_x86_64_cjnative';

export async function run(config) {
  const stdlibRoot = path.join(config.repoPath('runtime'), 'stdlib');
  const runtimeTarget = path.join(config.repoPath('runtime'), 'runtime', 'target');
  const stdlibOutput = path.join(stdlibRoot, 'output');
  const compilerOutput = path.join(config.repoPath('compiler'), 'output');
  const buildOutput = path.join(stdlibRoot, 'build', 'build');

  await stage('stdlib', async () => {
    await runBuildPy(config, stdlibRoot, ['clean'], {stageName: 'stdlib.clean.linux'});
    await runBuildPy(config, stdlibRoot, [
      'build', '-t', config.buildType, `--target-lib=${runtimeTarget}`,
    ], {stageName: 'stdlib.build.linux'});
    await runBuildPy(config, stdlibRoot, ['install'], {stageName: 'stdlib.install.linux'});
    copyContents(stdlibOutput, compilerOutput, {stage: 'stdlib.copy.linux'});
    copyCompiledStdLibraries(
      path.join(buildOutput, 'lib', LINUX_LIB_PATH),
      path.join(compilerOutput, 'lib', LINUX_LIB_PATH),
    );

    if (config.target.spec.key === 'linux-x64') {
      const flagOffCjos = path.join(config.buildRoot, 'stddual', 'flag-off-cjo');
      fs.rmSync(flagOffCjos, {recursive: true, force: true});
      fs.cpSync(path.join(stdlibOutput, 'modules', LINUX_LIB_PATH, 'std'), flagOffCjos, {recursive: true});

      const stickySdk = createStickySdkOverlay(
        compilerOutput, path.join(config.buildRoot, 'stddual', 'sticky-sdk'),
      );
      const llc = path.join(compilerOutput, 'third_party', 'llvm', 'bin', 'llc');
      const llcHelp = await runCommand([llc, '--help-hidden'], {
        stage: 'stdlib.sticky.llc-capability', capture: true, logOutput: false,
      });
      if (!llcHelp.stdout.includes(STICKY_LLC_OPTION)) {
        throw new BuildError('stdlib.sticky.llc-capability', `llc does not support ${STICKY_LLC_OPTION}`);
      }

      await runBuildPy(config, stdlibRoot, ['clean'], {
        stageName: 'stdlib.clean.sticky', extraEnv: {CANGJIE_HOME: stickySdk},
      });
      await runBuildPy(config, stdlibRoot, [
        'build', '-t', config.buildType, `--target-lib=${runtimeTarget}`,
      ], {stageName: 'stdlib.build.sticky', extraEnv: {CANGJIE_HOME: stickySdk}});

      const stickyCjos = path.join(buildOutput, 'modules', LINUX_LIB_PATH, 'std');
      const cjoResults = compareStdCjos(flagOffCjos, stickyCjos);
      const differingCjos = cjoResults.filter(result => !result.identical);
      if (differingCjos.length !== 0) {
        throw new BuildError('stdlib.compare-cjo',
          `sticky backend changed CJO bytes: ${differingCjos.map(result => result.name).join(', ')}`);
      }

      const stickyLibraries = path.join(
        compilerOutput, 'lib', OPTIMIZED_STD_SUBDIR, LINUX_LIB_PATH,
      );
      fs.rmSync(stickyLibraries, {recursive: true, force: true});
      const copied = copyCompiledStdLibraries(
        path.join(buildOutput, 'lib', LINUX_LIB_PATH), stickyLibraries,
      );
      const preflight = stickyPreflight(stickyLibraries);
      logger.info('sticky std: CJO %d/%d identical; %d libraries, %d bytes; symbols=%d relocations=%d',
        cjoResults.length, cjoResults.length, copied.files.length, copied.bytes,
        preflight.loggedBaseSymbols, preflight.stickyRelocations);
    }
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
    copyContents(stdlibOutput, compilerOutput, {stage: 'stdlib.copy.windows.host'});
    copyContents(stdlibOutput, path.join(config.repoPath('compiler'), 'output-x86_64-w64-mingw32'), {
      stage: 'stdlib.copy.windows.cross',
    });
  });
}

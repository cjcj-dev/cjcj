// Port of cangjie-build/src/cangjie_build/stages/runtime.py.

import path from 'node:path';
import fs from 'node:fs/promises';
import {runtimeSourceRepository,RUNTIME_INPUTS} from '../../lib/runtime-source-inputs.mjs';
import {receiveNativeRuntime} from '../../../ci/bootstrap/native-runtime-input.mjs';
import {prepareRuntimeInputs} from '../../../ci/bootstrap/sdk-native-stage.mjs';
import {sdkPlatform} from '../../../ci/bootstrap/sdk-platform.mjs';
import {hostPlatform} from '../../../ci/host-toolchain-pin.mjs';
import {stage} from '../../lib/logging.mjs';
import {assertRuntimeSplit} from '../../lib/runtime-split.mjs';
import {
  beginGcUnitLanguageDeferral,
  finishGcUnitLanguageDeferral,
  gcUnitRuntimeBuildEnv,
} from '../gc-unit-gate.mjs';
import {bootstrapHostSdk, copyContents, ensureDir, runBuildPy, windowsCrossArgs} from './common.mjs';

export async function run(config) {
  const runtimeRoot = path.join(config.repoPath('runtime'), 'runtime');
  const targetDir = path.join(runtimeRoot, 'target');
  const compilerOutput = path.join(config.repoPath('compiler'), 'output');

  await stage('runtime', async () => {
    if (config.nativeRuntime) {
      const selected=config.nativeRuntime;
      if (!selected.hostVersion || config.target.spec.crossCompile) throw new Error('RUNTIME_COMPONENT_NATIVE_PAIR_REQUIRED');
      const input = await receiveNativeRuntime({root:selected.install,
        sourceRoot:selected.sourceRoot,
        sourceRepository:config.sources.runtime.repository, platform:hostPlatform(),
        llvmCommit:selected.llvmCommit,runtimeCommit:selected.runtimeCommit,hostVersion:selected.hostVersion,
        work:path.join(config.workspace,'native-runtime-consumer')});
      for (const subdirectory of ['lib','runtime',...(config.target.spec.os==='linux'?['share/runtime-build']:[])])
        copyContents(path.join(input.install,subdirectory),path.join(compilerOutput,subdirectory),{stage:'runtime.adopt.native'});
      await fs.copyFile(path.join(input.install,RUNTIME_INPUTS),path.join(compilerOutput,RUNTIME_INPUTS));
      // The legacy stdlib stage consumes this build input snapshot. Reuse the
      // native SDK adapter without rebuilding or mutating the R installation.
      await prepareRuntimeInputs({runtime:input.install,link:targetDir,
        native:sdkPlatform(hostPlatform()),buildType:config.buildType});
      assertRuntimeSplit({hostSdk:bootstrapHostSdk(config),targetSdk:compilerOutput,target:config.target});
      return;
    }
    if (process.env.CANGJIE_BUILD_DRY_RUN !== '1') beginGcUnitLanguageDeferral(config, runtimeRoot, compilerOutput);
    ensureDir(targetDir);
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
    if (process.env.CANGJIE_BUILD_DRY_RUN !== '1') finishGcUnitLanguageDeferral(config, runtimeRoot, compilerOutput);
    if (!config.target.spec.crossCompile) {
      if (process.env.CANGJIE_BUILD_DRY_RUN !== '1') {
        assertRuntimeSplit({
          hostSdk: bootstrapHostSdk(config),
          targetSdk: compilerOutput,
          target: config.target,
        });
      }
      return;
    }

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
        hostSdk: bootstrapHostSdk(config),
        targetSdk: compilerOutput,
        target: config.target,
      });
    }
  });
}

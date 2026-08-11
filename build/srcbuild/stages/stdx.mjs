// Port of cangjie-build/src/cangjie_build/stages/stdx.py.

import path from 'node:path';
import {stage} from '../../lib/logging.mjs';
import {assertHostRuntimeCommands, assertRuntimeSplit} from '../../lib/runtime-split.mjs';
import {installPath, TARGET_TRIPLE} from '../../toolchain/mingw.mjs';
import {applyTextPatch, opensslLibPath, runBuildPy, windowsCrossArgs} from './common.mjs';

const HOST_RUNTIME_EDIT = [[
  '        set(_cj_runtime_lib_dir "$ENV{CANGJIE_HOME}/runtime/lib/${output_cj_lib_dir}${SANITIZER_SUBPATH}")',
  `        if(DEFINED ENV{STDX_HOST_RUNTIME_LIB_DIR} AND NOT "$ENV{STDX_HOST_RUNTIME_LIB_DIR}" STREQUAL "")
            set(_cj_runtime_lib_dir "$ENV{STDX_HOST_RUNTIME_LIB_DIR}")
        else()
            set(_cj_runtime_lib_dir "$ENV{CANGJIE_HOME}/runtime/lib/\${output_cj_lib_dir}\${SANITIZER_SUBPATH}")
        endif()`,
]];

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
      applyTextPatch(
        path.join(stdxRoot, 'build', 'common', 'modules', 'AddCangjieSource.cmake'),
        HOST_RUNTIME_EDIT,
        {stage: 'stdx.host-runtime.patch', marker: 'ENV{STDX_HOST_RUNTIME_LIB_DIR}'},
      );
    }
    const hostRuntimeEnv = split
      ? {STDX_HOST_RUNTIME_LIB_DIR: path.dirname(split.hostRuntime)}
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
    await runBuildPy(config, stdxRoot, args, {stageName: 'stdx.build', extraEnv: hostRuntimeEnv});
    if (split) {
      assertHostRuntimeCommands({
        buildFile: path.join(stdxRoot, 'build_temp', 'build', 'build.ninja'),
        hostRuntime: split.hostRuntime,
        targetRuntime: split.targetRuntime,
        loaderEnv: config.target.spec.loaderEnv,
      });
    }
    await runBuildPy(config, stdxRoot, ['install'], {
      stageName: 'stdx.install', extraEnv: hostRuntimeEnv,
    });
  });
}

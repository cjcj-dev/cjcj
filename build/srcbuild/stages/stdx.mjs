#!/usr/bin/env zx
// Port of cangjie-build/src/cangjie_build/stages/stdx.py.

import path from 'node:path';
import fs from 'node:fs';
import {command,publishPaths,atomicJson} from '../../../ci/bootstrap/sdk-flow.mjs';
import {cleanSdkEnvironment,sdkPlatform} from '../../../ci/bootstrap/sdk-platform.mjs';
import {STDX_BUILD_INPUTS} from '../stdx-build-inputs.mjs';
import {selectBuildJobs} from '../../../ci/build-resources.mjs';
import {BuildError} from '../../lib/errors.mjs';
import {stage} from '../../lib/logging.mjs';
import {assertSourceIdentity} from '../../lib/git.mjs';
import {assertHostRuntimeCommands, assertRuntimeSplit} from '../../lib/runtime-split.mjs';
import {installPath, TARGET_TRIPLE} from '../../toolchain/mingw.mjs';
import {bootstrapHostSdk, consumerSdk, opensslLibPath, runBuildPy, windowsCrossArgs, mergedEnv, pythonExe} from './common.mjs';
import {beginStdxBuild, finishStdxBuild, prepareStdxInstall, finishStdxInstall} from '../stdx-build-inputs.mjs';

function checkIncrementalConfiguration(config, directory, compilerInclude) {
  const cache=path.join(directory,'CMakeCache.txt');
  if(!fs.existsSync(cache))throw new BuildError('stdx.incremental','existing native CMake cache is required');
  const values=Object.fromEntries(fs.readFileSync(cache,'utf8').split(/\r?\n/)
    .filter(line=>/^[A-Za-z_][A-Za-z0-9_]*:[^=]+=/.test(line))
    .map(line=>[line.slice(0,line.indexOf(':')),line.slice(line.indexOf('=')+1)]));
  const limited=config.stdxProfile==='sdk-tools';
  const expected={CMAKE_HOME_DIRECTORY:config.repoPath('stdx'),CANGJIE_INCLUDE:compilerInclude,
    CMAKE_BUILD_TYPE:config.buildType,CANGJIE_BUILD_WITHOUT_CHIR:limited?'ON':'OFF',
    CANGJIE_BUILD_WITHOUT_SYNTAX:limited?'ON':'OFF',CANGJIE_BUILD_WITHOUT_EFFECT_HANDLERS:limited?'ON':'OFF',
    CANGJIE_BUILD_WITHOUT_PLUGIN:'OFF',CANGJIE_BUILD_WITHOUT_ASPECT_CJ:'OFF',
    CANGJIE_BUILD_STDLIB_WITH_COVERAGE:'OFF',CANGJIE_BUILD_ARGS:''};
  if(!config.target.spec.crossCompile)Object.assign(expected,{CANGJIE_TARGET_LIB:opensslLibPath(config)||'',
    CANGJIE_TARGET_TOOLCHAIN:'',CANGJIE_TARGET_SYSROOT:'',BUILD_GCC_TOOLCHAIN:config.stdxGccToolchain||''});
  for(const [key,value]of Object.entries(expected)) {
    const actual=key==='BUILD_GCC_TOOLCHAIN' ? values[key]??'' : values[key];
    if((key==='CMAKE_BUILD_TYPE'?actual?.toLowerCase():actual)!==value)
      throw new BuildError('stdx.incremental',`native configuration changed: ${key}=${actual} expected=${value}; select a separate build or clean explicitly`);
  }
}

// Consume the installed stdx payload before its directory is published.
export async function consumeStdx(config,prefix) {
  if(config.target.spec.crossCompile)return {status:'NOT_RUN',reason:'HOST_CROSS_EXEC'};
  const platform=config.target.spec.llvmPlatform,native=sdkPlatform(platform),sdk=consumerSdk(config);
  const work=fs.mkdtempSync(path.join(path.dirname(prefix),'stdx-consumer-'));
  const input=path.join(work,'json.cj'),output=path.join(work,'json'+native.exe),records=[];
  fs.writeFileSync(input,'import stdx.encoding.json.*\nmain(): Int64 { if (JsonValue.fromStr("42").toString() != "42") { return 42 }; println("STDX_INSTALLED_JSON_PASS"); return 0 }\n');
  const lib=path.join(prefix,config.target.stdxTargetSubdir(),'static','stdx');
  const env=cleanSdkEnvironment(sdk,platform);env.CANGJIE_STDX_PATH=lib;
  try {
    await command([path.join(sdk,'bin','cjc'+native.exe),input,'--import-path',lib,'-L',lib,
      '-lstdx.encoding.json','-lstdx.encoding.jsonFFI','-o',output],{cwd:work,env,records});
    await command([output],{cwd:work,env,records});
    return {status:'EXECUTED',commands:records};
  } finally {await atomicJson(path.join(work,'commands.json'),records);}
}

export async function run(config) {
  const stdxRoot = config.repoPath('stdx');
  const compilerInclude = path.join(config.repoPath('compiler'), 'include');
  await stage('stdx', async () => {
    await assertSourceIdentity(config.repo('stdx'), stdxRoot);
    let split;
    const hostSdk=bootstrapHostSdk(config);
    if (process.env.CANGJIE_BUILD_DRY_RUN !== '1') {
      split = assertRuntimeSplit({
        hostSdk,
        targetSdk: consumerSdk(config),
        target: config.target,
      });
    }
    const jobs = await selectBuildJobs(config.jobs);
    const hostClosureEnv = {CANGJIE_BUILD_JOBS: String(jobs),
      ...(split ? {STDX_HOST_CANGJIE_HOME:
        process.env.STDX_HOST_CANGJIE_HOME ?? hostSdk} : {})};
    const nativeBuild=path.join(stdxRoot,'build_temp',config.target.spec.crossCompile?'build-libs-'+TARGET_TRIPLE:'build');
    const checkCommands=()=>assertHostRuntimeCommands({buildFile:path.join(nativeBuild,'build.ninja'),
      hostRuntime:split.hostRuntime,targetRuntime:split.targetRuntime,loaderEnv:config.target.spec.loaderEnv,
      environment:mergedEnv(config,hostClosureEnv)});
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
      if (config.stdxGccToolchain) args.push(`--gcc-toolchain=${config.stdxGccToolchain}`);
      const openssl = opensslLibPath(config);
      if (openssl) args.push(`--target-lib=${openssl}`);
    }
    if(config.stdxProfile==='sdk-tools') {
      // The six SDK tool consumers use compression/crypto/encoding/network/log
      // libraries. They do not consume CHIR, syntax, plugin, aspect or effects.
      // Use the fixed stdx producer's own public options, never generate or edit
      // its compiler-schema bindings for this limited dependency build.
      args.push('--skip-chir','--skip-syntax','--without-effect-handlers');
    }
    args.push('--jobs', String(jobs));
    const limited=config.stdxProfile==='sdk-tools',dry=process.env.CANGJIE_BUILD_DRY_RUN==='1';
    const destination=consumerSdk(config,config.target.primaryCompilerOutput());
    const installRoot=limited?path.join(stdxRoot,'target'):dry?destination:fs.mkdtempSync(destination+'.stdx-pending-');
    const prefix=limited?installRoot:path.join(installRoot,'stdx');
    const installArgs=limited?['install']:['install','--prefix',prefix];
    const attempt = beginStdxBuild(config, {directory:nativeBuild, installRoot, prefix,
      argv:[pythonExe(), 'build.py', ...args], installArgv:[pythonExe(), 'build.py', ...installArgs],
      environment:{...process.env, ...mergedEnv(config, hostClosureEnv)}});
    if(config.stdxBuildMode==='incremental') {
      if(process.env.CANGJIE_BUILD_DRY_RUN!=='1') {
        checkIncrementalConfiguration(config,nativeBuild,compilerInclude);
        // A failed configure can leave a valid cache and built dependencies
        // without a generated graph. Let build.py resume that configuration;
        // existing graphs must still pass before any objects are reused.
        if(split && fs.existsSync(path.join(nativeBuild,'build.ninja')))checkCommands();
      }
    } else await runBuildPy(config, stdxRoot, ['clean'], {stageName: 'stdx.clean'});
    await runBuildPy(config, stdxRoot, args, {stageName:'stdx.build', extraEnv:hostClosureEnv});
    if (split) checkCommands();
    finishStdxBuild(config, attempt);
    prepareStdxInstall(attempt);
    await runBuildPy(config, stdxRoot, installArgs, {
      stageName: 'stdx.install', extraEnv: hostClosureEnv,
    });
    finishStdxInstall(config, attempt);
    if(!dry&&!limited) {
      await consumeStdx(config,prefix);
      await publishPaths(['stdx',STDX_BUILD_INPUTS].map(relative=>({pending:path.join(installRoot,relative),destination:path.join(destination,relative)})));
    }
  });
}

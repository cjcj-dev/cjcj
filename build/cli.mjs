#!/usr/bin/env zx
// Port of cangjie-build/src/cangjie_build/cli.py.

import path from 'node:path';
import fs from 'node:fs';
import {fileURLToPath} from 'node:url';
import {buildConfig, DEFAULT_BUILD_TYPE, REPO_NAMES, VALID_BUILD_TYPES} from './lib/config.mjs';
import {BuildError, ConfigError} from './lib/errors.mjs';
import {configureLogging, getLogger} from './lib/logging.mjs';
import {allTargets} from './lib/targets.mjs';
import {assertBuildHostContract} from './lib/build-target.mjs';
import * as sccache from './toolchain/sccache.mjs';
import * as mingw from './toolchain/mingw.mjs';
import * as staticLibs from './toolchain/static-libs.mjs';
import * as systemDeps from './toolchain/system-deps.mjs';
import * as targetPython from './toolchain/target-python.mjs';
import * as compiler from './srcbuild/stages/compiler.mjs';
import * as fetchStage from './srcbuild/stages/fetch.mjs';
import * as packageStage from './srcbuild/stages/package.mjs';
import * as runtime from './srcbuild/stages/runtime.mjs';
import * as stdlib from './srcbuild/stages/stdlib.mjs';
import * as stdx from './srcbuild/stages/stdx.mjs';
import * as tools from './srcbuild/stages/tools.mjs';
import * as verify from './srcbuild/stages/verify.mjs';
import {prepareSourceBuildInputs} from '../ci/bootstrap/sdk-inputs.mjs';
import {installProducts} from '../ci/bootstrap/sdk-flow.mjs';
import {verifyInstall} from '../ci/bootstrap/sdk-verify-install.mjs';

const VERSION = '0.1.0';
const logger = getLogger('cangjie_build.cli');
const COMMANDS = new Set([
  'install-system-deps', 'print-version', 'install-static-libs', 'install-mingw',
  'install-target-python', 'fetch', 'build', 'package', 'verify', 'run-all', 'sdk', 'install',
]);
const BUILD_STAGES = Object.freeze({compiler, runtime, stdlib, stdx, tools});
const LOG_LEVELS = new Set(['DEBUG', 'INFO', 'WARNING', 'ERROR']);

function usage() {
  return `Usage: npx --yes zx@8 build/cli.mjs [global options] COMMAND\n\n`
    + `Commands: ${[...COMMANDS].join(', ')}\n`
    + 'Global options:\n'
    + '  --workspace PATH\n'
    + '  --build-root PATH\n'
    + '  --tools-jni-home PATH --tools-runtime-header FILE --tools-lombok-jar FILE\n'
    + '  --tools-compiler-libs PATH --tools-runtime-config FILE --tools-llvm-shim FILE --tools-llvm-library FILE\n'
    + '  --official-sdk-root PATH (default: CJCJ_OFFICIAL_SDK_ROOT, pinned cjv SDK)\n'
    + '  --target TARGET (default: linux-x64)\n'
    + '  --host-profile generic|kkk2 (default: generic)\n'
    + `  --build-type TYPE (default: ${DEFAULT_BUILD_TYPE})\n`
    + '  --cangjie-version VERSION\n'
    + '  --stdx-version INTEGER (default: 1)\n'
    + '  --stdx-profile full|sdk-tools (default: full)\n'
    + '  --stdx-build-mode clean|incremental (default: clean)\n'
    + '  --stdx-gcc-toolchain PATH (native Clang GCC headers/libraries prefix)\n'
    + '  --tools-build-mode clean|incremental (default: clean)\n'
    + '  --tools-analysis-sdk PATH --tools-frontend-source PATH --tools-frontend-ref SHA (Cangjie cjlint analysis and fixed shared frontend)\n'
    + '  --tools-gcc-toolchain PATH (retired C++ cjlint option; rejected)\n'
    + '  --tools-dependencies PATH (legacy native dependency description; not a Cangjie tool input)\n'
    + '  --tools-build-set all|NAME,... (default: all; omitted tools reuse existing outputs)\n'
    + '  --tools-mangle-source DIR (compiler Cangjie demangler source for cjtrace-recover)\n'
    + '  --tools-phase all|build|install (default: all; build does not publish the shared SDK)\n'
    + '  --jobs INTEGER (tools total CPU budget; default: CANGJIE_BUILD_JOBS or available CPUs)\n'
    + '  --tools-package-jobs INTEGER (heavy producer limit, default/max: 4)\n'
    + '  --log-level LEVEL (default: INFO)\n'
    + '  --version\n'
    + '  --help\n'
    + `Targets: ${allTargets().join(', ')}\n`
    + `Build types: ${VALID_BUILD_TYPES.join(', ')}\n`
    + 'Log levels: DEBUG, INFO, WARNING, ERROR';
}

function commandUsage(command) {
  if (command === 'build') return 'Usage: npx --yes zx@8 build/cli.mjs [global options] build STAGE';
  if (command === 'fetch') {
    return 'Usage: npx --yes zx@8 build/cli.mjs [global options] fetch [--tag TAG] [--repo-url NAME=URL] [--repo-tag NAME=TAG]';
  }
  if (command === 'run-all') {
    return 'Usage: npx --yes zx@8 build/cli.mjs [global options] run-all [--skip-system-deps] [--skip-install-libs]';
  }
  return `Usage: npx --yes zx@8 build/cli.mjs [global options] ${command}`;
}

function optionValue(args, index, name) {
  const argument = args[index];
  if (argument.startsWith(`${name}=`)) return {value: argument.slice(name.length + 1), next: index + 1};
  if (argument !== name) return null;
  if (index + 1 >= args.length) throw new ConfigError(`${name}: missing value`);
  return {value: args[index + 1], next: index + 2};
}

function parseGlobal(args) {
  const options = {
    targetKey: 'linux-x64', buildType: DEFAULT_BUILD_TYPE, stdxVersion: 1, logLevel: 'INFO',
    hostProfile: process.env.CJCJ_SRCBUILD_HOST_PROFILE || 'generic',
  };
  let index = 0;
  while (index < args.length && !COMMANDS.has(args[index])) {
    const argument = args[index];
    if (argument === '--help') return {help: true, exitCode: 0};
    if (argument === '--version') return {version: true};
    if (!argument.startsWith('-')) return {options, command: argument, rest: args.slice(index + 1)};
    let parsed;
    for (const [flag, key] of [
      ['--workspace', 'workspace'], ['--build-root', 'buildRoot'], ['--target', 'targetKey'],
      ['--official-sdk-root', 'officialSdkRoot'],
      ['--host-profile', 'hostProfile'],
      ['--build-type', 'buildType'], ['--cangjie-version', 'cangjieVersion'],
      ['--stdx-version', 'stdxVersion'], ['--stdx-profile', 'stdxProfile'], ['--log-level', 'logLevel'],
      ['--stdx-build-mode', 'stdxBuildMode'], ['--stdx-gcc-toolchain', 'stdxGccToolchain'], ['--tools-build-mode','toolsBuildMode'], ['--tools-build-set','toolsBuildSet'],
      ['--tools-phase','toolsPhase'], ['--tools-install-prefix','toolsInstallPrefix'], ['--tools-dependencies','toolsDependencies'], ['--tools-gcc-toolchain','toolsGccToolchain'], ['--tools-mangle-source','toolsMangleSource'], ['--tools-jni-home','toolsJniHome'], ['--tools-runtime-header','toolsRuntimeHeader'], ['--tools-lombok-jar','toolsLombokJar'], ['--tools-analysis-sdk','toolsAnalysisSdk'], ['--tools-frontend-source','toolsFrontendSource'], ['--tools-frontend-ref','toolsFrontendRef'], ['--tools-compiler-libs','toolsCompilerLibs'], ['--tools-runtime-config','toolsRuntimeConfig'], ['--tools-llvm-shim','toolsLlvmShim'], ['--tools-llvm-library','toolsLlvmLibrary'], ['--jobs','jobs'], ['--tools-package-jobs','toolsPackageJobs'],
    ]) {
      parsed = optionValue(args, index, flag);
      if (parsed) {
        if (key === 'officialSdkRoot' && (!parsed.value.trim() || parsed.value.startsWith('--') || COMMANDS.has(parsed.value))) {
          throw new ConfigError('--official-sdk-root: expected a nonempty path');
        }
        options[key] = parsed.value;
        index = parsed.next;
        break;
      }
    }
    if (!parsed) throw new ConfigError(`unknown global option: ${argument}`);
  }
  if (index >= args.length) return {help: true, exitCode: 2};
  return {options, command: args[index], rest: args.slice(index + 1)};
}

function validateGlobalOptions(options) {
  if (!/^[-+]?\d+$/.test(String(options.stdxVersion))) {
    throw new ConfigError(`invalid value for --stdx-version: '${options.stdxVersion}' is not an integer`);
  }
  options.stdxVersion = Number(options.stdxVersion);
  if (!LOG_LEVELS.has(options.logLevel)) {
    throw new ConfigError(`invalid value for --log-level: '${options.logLevel}'; valid: ${[...LOG_LEVELS].join(', ')}`);
  }
}

function wantsHelp(args) {
  return args.includes('--help');
}

function requireNoArgs(command, args) {
  if (args.length !== 0) throw new ConfigError(`${command}: unexpected argument '${args[0]}'`);
}

export function parseRepoKv(items, option) {
  const output = {};
  for (const raw of items) {
    const separator = raw.indexOf('=');
    const name = separator < 0 ? '' : raw.slice(0, separator);
    const value = separator < 0 ? '' : raw.slice(separator + 1);
    if (!name) throw new ConfigError(`${option}: expected NAME=VALUE, got '${raw}'`);
    if (!REPO_NAMES.includes(name)) throw new ConfigError(`${option}: unknown repo '${name}'; valid: ${REPO_NAMES.join(', ')}`);
    if (name in output) throw new ConfigError(`${option}: repo '${name}' specified more than once`);
    output[name] = value;
  }
  return output;
}

function parseFetch(args) {
  let tag;
  const repoUrls = [];
  const repoTags = [];
  for (let index = 0; index < args.length;) {
    let parsed = optionValue(args, index, '--tag');
    if (parsed) {
      tag = parsed.value;
      index = parsed.next;
      continue;
    }
    parsed = optionValue(args, index, '--repo-url');
    if (parsed) {
      repoUrls.push(parsed.value);
      index = parsed.next;
      continue;
    }
    parsed = optionValue(args, index, '--repo-tag');
    if (parsed) {
      repoTags.push(parsed.value);
      index = parsed.next;
      continue;
    }
    throw new ConfigError(`fetch: unknown option: ${args[index]}`);
  }
  return {tag, repoUrls, repoTags};
}

async function dispatch(config, command, args) {
  if(command==='install'){
    const {main}=await import('../ci/bootstrap/sdk-flow.mjs');
    const index=args.indexOf('--inputs');
    if(index<0||!args[index+1])throw new ConfigError('install --inputs FILE [--no-package] [--dry-run|--build-only]');
    const forwarded=[...args];forwarded[index]='--install-inputs';return main(forwarded);
  }
  if(command==='sdk'){const {main}=await import('../ci/bootstrap/sdk-flow.mjs');return main(args);}
  if (!COMMANDS.has(command)) throw new ConfigError(`unknown command: ${command}`);
  if (wantsHelp(args)) {
    process.stdout.write(`${commandUsage(command)}\n`);
    return;
  }
  if (command === 'install-system-deps') {
    requireNoArgs(command, args);
    return systemDeps.install(config);
  }
  if (command === 'print-version') {
    requireNoArgs(command, args);
    process.stdout.write(`${config.cangjieVersion}\n`);
    return;
  }
  if (command === 'install-static-libs') {
    requireNoArgs(command, args);
    return staticLibs.install(config.buildRoot, {jobs:config.jobs});
  }
  if (command === 'install-mingw') {
    requireNoArgs(command, args);
    if (!config.target.spec.needsMingw) {
      logger.warning('Target %s does not need MinGW; skipping', config.target.spec.key);
      return;
    }
    return mingw.install(config.buildRoot);
  }
  if (command === 'install-target-python') {
    requireNoArgs(command, args);
    if (!config.target.spec.crossCompile) {
      logger.warning('Target %s is not cross-compile; skipping', config.target.spec.key);
      return;
    }
    return targetPython.install(config.buildRoot);
  }
  if (command === 'fetch') {
    const {tag, repoUrls, repoTags} = parseFetch(args);
    const urls = parseRepoKv(repoUrls, '--repo-url');
    const tags = parseRepoKv(repoTags, '--repo-tag');
    const repoOverrides = {};
    for (const name of new Set([...Object.keys(urls), ...Object.keys(tags)])) {
      repoOverrides[name] = {url: urls[name], tag: tags[name]};
    }
    const fetchConfig = buildConfig({
      workspace: config.workspace,
      buildRoot: config.buildRoot,
      targetKey: config.target.spec.key,
      buildType: config.buildType,
      cangjieVersion: config.cangjieVersion,
      stdxVersion: config.stdxVersion,
      stdxProfile: config.stdxProfile,
      stdxBuildMode: config.stdxBuildMode,
      stdxGccToolchain: config.stdxGccToolchain,
      toolsBuildMode: config.toolsBuildMode,
      toolsBuildSet: config.toolsBuildSet,
      toolsDependencies: config.toolsDependencies,
      toolsGccToolchain: config.toolsGccToolchain,
      toolsMangleSource: config.toolsMangleSource,
      toolsJniHome: config.toolsJniHome,
      toolsRuntimeHeader: config.toolsRuntimeHeader,
      toolsLombokJar: config.toolsLombokJar,
      toolsAnalysisSdk: config.toolsAnalysisSdk,
      toolsFrontendSource: config.toolsFrontendSource,
      toolsFrontendRef: config.toolsFrontendRef,
      toolsCompilerLibs: config.toolsCompilerLibs,
      toolsRuntimeConfig: config.toolsRuntimeConfig,
      toolsLlvmShim: config.toolsLlvmShim,
      toolsLlvmLibrary: config.toolsLlvmLibrary,
      toolsPhase: config.toolsPhase, toolsInstallPrefix: config.toolsInstallPrefix, jobs: config.jobs, toolsPackageJobs: config.toolsPackageJobs,
      officialSdkRoot: config.officialSdkRoot,
      consumerSdk: config.consumerSdk,
      useSavedSources: false,
      globalTag: tag,
      repoOverrides,
    });
    return fetchStage.run(fetchConfig);
  }
  if (command === 'build') {
    if (args.length === 0) {
      process.stdout.write(`${commandUsage(command)}\nStages: ${Object.keys(BUILD_STAGES).join(', ')}\n`);
      process.exitCode = 2;
      return;
    }
    if (args.length !== 1) throw new ConfigError(`build ${args[0]}: unexpected argument '${args[1]}'`);
    if (!(args[0] in BUILD_STAGES)) throw new ConfigError(`build: unknown stage '${args[0]}'`);
    if(['compiler','runtime','stdlib'].includes(args[0])) {
      if(process.env.CANGJIE_BUILD_DRY_RUN==='1'){console.log(JSON.stringify({status:'NOT_INSTALLED',reason:'DRY_RUN',sources:config.sources,stage:args[0]}));return;}
      const production=await prepareSourceBuildInputs(config,process.env,args[0]);
      await BUILD_STAGES[args[0]].run(production);
      if(args[0]==='stdlib'&&process.env.CANGJIE_BUILD_DRY_RUN!=='1')await installProducts(production.installInputs,{packageOutput:false});
      return;
    }
    return BUILD_STAGES[args[0]].run(config);
  }
  if (command === 'package') {
    requireNoArgs(command, args);
    return packageStage.run(config);
  }
  if (command === 'verify') {
    requireNoArgs(command, args);
    return verify.run(config);
  }
  if (command === 'run-all') {
    const valid = new Set(['--skip-system-deps', '--skip-install-libs','--build-only','--dry-run']);
    for (const argument of args) if (!valid.has(argument)) throw new ConfigError(`run-all: unknown option '${argument}'`);
    if(args.includes('--dry-run')||process.env.CANGJIE_BUILD_DRY_RUN==='1') {
      console.log(JSON.stringify({status:'NOT_INSTALLED',reason:'DRY_RUN',sources:config.sources,stages:['compiler','runtime','stdlib','stdx','tools','package']}));return;
    }
    if (!args.includes('--skip-system-deps')) await systemDeps.install(config);
    if (!args.includes('--skip-install-libs')) {
      if (config.target.spec.needsMingw) {
        await mingw.install(config.buildRoot);
        if (config.target.spec.crossCompile) await targetPython.install(config.buildRoot);
      } else if (config.target.spec.needsStaticLibs) {
        await staticLibs.install(config.buildRoot, {jobs:config.jobs});
      }
    }
    await fetchStage.run(config);
    const production=await prepareSourceBuildInputs(config);
    await compiler.run(production);
    await runtime.run(production);
    await stdlib.run(production);
    if(args.includes('--build-only')) {
      // Native intermediate output supplies the later producers. No public SDK
      // or archive is published, including when these consumers fail.
      await stdx.run(production);
      await tools.run(production);
      console.log(JSON.stringify({status:'NOT_INSTALLED',reason:'BUILD_ONLY',sources:production.sources}));return;
    }
    await installProducts(production.installInputs,{packageOutput:false,consume:async pending=>{
      const installed=Object.freeze({...production,producerSdk:null,consumerSdk:pending});
      await stdx.run(installed);
      await tools.run(installed);
      if(!config.target.spec.crossCompile)await verifyInstall({sdk:pending,
        work:path.join(config.workspace,'verify-installed'),platform:config.target.spec.llvmPlatform});
    }});
    const installed=Object.freeze({...production,producerSdk:null,consumerSdk:production.installInputs.install});
    await packageStage.run(installed);
    return verify.run(installed);
  }
}

async function main() {
  const scriptPath = fileURLToPath(import.meta.url);
  const scriptIndex = process.argv.findIndex(argument => path.resolve(argument) === scriptPath);
  const parsed = parseGlobal(process.argv.slice(scriptIndex >= 0 ? scriptIndex + 1 : 2));
  if (parsed.help) {
    process.stdout.write(`${usage()}\n`);
    process.exitCode = parsed.exitCode;
    return;
  }
  if (parsed.version) {
    process.stdout.write(`${VERSION}\n`);
    return;
  }
  validateGlobalOptions(parsed.options);
  configureLogging(parsed.options.logLevel);
  sccache.maybeEnable();
  if(['install','sdk'].includes(parsed.command))return dispatch(null,parsed.command,parsed.rest);
  const config = buildConfig({...parsed.options, useSavedSources: parsed.command !== 'fetch'});
  if (config.officialSdkRoot && !fs.statSync(config.officialSdkRoot, {throwIfNoEntry: false})?.isDirectory()) {
    throw new ConfigError(`officialSdkRoot: directory does not exist: ${config.officialSdkRoot}`);
  }
  assertBuildHostContract(parsed.options.targetKey, {profile: parsed.options.hostProfile});
  await dispatch(config, parsed.command, parsed.rest);
}

try {
  await main();
} catch (error) {
  if (error instanceof BuildError) {
    logger.error('%s', error.message);
    process.exitCode = 1;
  } else if (error instanceof ConfigError) {
    logger.error('%s', error.message);
    process.exitCode = 2;
  } else {
    throw error;
  }
}

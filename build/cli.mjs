#!/usr/bin/env zx
// Port of cangjie-build/src/cangjie_build/cli.py.

import path from 'node:path';
import {fileURLToPath} from 'node:url';
import {buildConfig, DEFAULT_BUILD_TYPE, REPO_NAMES, VALID_BUILD_TYPES} from './lib/config.mjs';
import {BuildError, ConfigError} from './lib/errors.mjs';
import {configureLogging, getLogger} from './lib/logging.mjs';
import {allTargets, assertHostContract} from './lib/targets.mjs';
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

const VERSION = '0.1.0';
const logger = getLogger('cangjie_build.cli');
const COMMANDS = new Set([
  'install-system-deps', 'print-version', 'install-static-libs', 'install-mingw',
  'install-target-python', 'fetch', 'build', 'package', 'verify', 'run-all',
]);
const BUILD_STAGES = Object.freeze({compiler, runtime, stdlib, stdx, tools});
const LOG_LEVELS = new Set(['DEBUG', 'INFO', 'WARNING', 'ERROR']);

function usage() {
  return `Usage: npx --yes zx@8 build/cli.mjs [global options] COMMAND\n\n`
    + `Commands: ${[...COMMANDS].join(', ')}\n`
    + 'Global options:\n'
    + '  --workspace PATH\n'
    + '  --build-root PATH\n'
    + '  --target TARGET (default: linux-x64)\n'
    + '  --host-profile generic|kkk2 (default: generic)\n'
    + `  --build-type TYPE (default: ${DEFAULT_BUILD_TYPE})\n`
    + '  --cangjie-version VERSION\n'
    + '  --stdx-version INTEGER (default: 1)\n'
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
      ['--host-profile', 'hostProfile'],
      ['--build-type', 'buildType'], ['--cangjie-version', 'cangjieVersion'],
      ['--stdx-version', 'stdxVersion'], ['--log-level', 'logLevel'],
    ]) {
      parsed = optionValue(args, index, flag);
      if (parsed) {
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
    return staticLibs.install(config.buildRoot);
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
    const valid = new Set(['--skip-system-deps', '--skip-install-libs']);
    for (const argument of args) if (!valid.has(argument)) throw new ConfigError(`run-all: unknown option '${argument}'`);
    if (!args.includes('--skip-system-deps')) await systemDeps.install(config);
    if (!args.includes('--skip-install-libs')) {
      if (config.target.spec.needsMingw) {
        await mingw.install(config.buildRoot);
        if (config.target.spec.crossCompile) await targetPython.install(config.buildRoot);
      } else if (config.target.spec.needsStaticLibs) {
        await staticLibs.install(config.buildRoot);
      }
    }
    await fetchStage.run(config);
    await compiler.run(config);
    await runtime.run(config);
    await stdlib.run(config);
    await stdx.run(config);
    await tools.run(config);
    await packageStage.run(config);
    return verify.run(config);
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
  const config = buildConfig(parsed.options);
  assertHostContract(parsed.options.targetKey, {profile: parsed.options.hostProfile});
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

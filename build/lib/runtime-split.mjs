import {spawnSync} from 'node:child_process';
import fs from 'node:fs';
import path from 'node:path';
import {BuildError} from './errors.mjs';

export const LOAD_BAD_MASK_SYMBOL = 'g_cjLoadBadMask';

function requireDirectory(directory, label) {
  if (!directory) throw new BuildError('runtime.split', `${label} is required`);
  const resolved = path.resolve(directory);
  if (!fs.statSync(resolved, {throwIfNoEntry: false})?.isDirectory()) {
    throw new BuildError('runtime.split', `${label} is not a directory: ${resolved}`);
  }
  return resolved;
}

function requireRuntime(file, label) {
  if (!fs.statSync(file, {throwIfNoEntry: false})?.isFile()) {
    throw new BuildError('runtime.split', `${label} runtime is missing: ${file}`);
  }
  return file;
}

export function runtimeSplitPaths({hostSdk, targetSdk, target}) {
  const hostRoot = requireDirectory(hostSdk, 'CJCJ_SRCBUILD_HOST_SDK');
  const targetRoot = requireDirectory(targetSdk, 'target SDK');
  const relative = path.join('runtime', 'lib', target.spec.runtimeTuple, target.spec.runtimeLibrary);
  return {
    hostSdk: hostRoot,
    targetSdk: targetRoot,
    hostRuntime: requireRuntime(path.join(hostRoot, relative), 'host'),
    targetRuntime: requireRuntime(path.join(targetRoot, relative), 'target'),
  };
}

export function readRuntimeSymbols(file, target) {
  const args = target.spec.os === 'darwin'
    ? ['-g', file]
    : ['-D', '--defined-only', file];
  const result = spawnSync('nm', args, {encoding: 'utf8'});
  if (result.status !== 0) {
    throw new BuildError(
      'runtime.split',
      `nm failed for ${file}: rc=${result.status} ${String(result.stderr || '').trim()}`,
    );
  }
  return result.stdout;
}

export function countLoadBadMask(symbols) {
  return String(symbols).split(/\r?\n/)
    .filter(line => new RegExp(`\\b${LOAD_BAD_MASK_SYMBOL}\\b`).test(line)).length;
}

export function assertRuntimeSplit({
  hostSdk,
  targetSdk,
  target,
  readSymbols = readRuntimeSymbols,
  log = console.log,
}) {
  const paths = runtimeSplitPaths({hostSdk, targetSdk, target});
  const hostCount = countLoadBadMask(readSymbols(paths.hostRuntime, target));
  const targetCount = countLoadBadMask(readSymbols(paths.targetRuntime, target));
  if (hostCount !== 0 || targetCount !== 1) {
    throw new BuildError(
      'runtime.split',
      `${LOAD_BAD_MASK_SYMBOL} count contract failed: host=${hostCount} path=${paths.hostRuntime}; ` +
      `target=${targetCount} path=${paths.targetRuntime}; expected host=0 target=1`,
    );
  }
  const hostReal = fs.realpathSync(paths.hostRuntime);
  const targetReal = fs.realpathSync(paths.targetRuntime);
  if (hostReal === targetReal) {
    throw new BuildError('runtime.split', `host and target runtime resolve to the same file: ${hostReal}`);
  }
  log(
    `RUNTIME_SPLIT_ASSERT_PASS host=${hostCount} path=${hostReal} ` +
    `target=${targetCount} path=${targetReal}`,
  );
  return {...paths, hostRuntime: hostReal, targetRuntime: targetReal, hostCount, targetCount};
}

export function hostLoaderPath({hostSdk, targetSdk, target, inherited = ''}) {
  const paths = runtimeSplitPaths({hostSdk, targetSdk, target});
  return [
    path.join(paths.targetSdk, 'third_party', 'llvm', 'lib'),
    path.dirname(paths.hostRuntime),
    path.join(paths.targetSdk, 'tools', 'lib'),
    inherited,
  ].filter(Boolean).join(path.delimiter);
}

export function targetLoaderPath({targetSdk, target, inherited = ''}) {
  const targetRoot = requireDirectory(targetSdk, 'target SDK');
  return [
    path.join(targetRoot, 'third_party', 'llvm', 'lib'),
    path.join(targetRoot, 'runtime', 'lib', target.spec.runtimeTuple),
    path.join(targetRoot, 'tools', 'lib'),
    inherited,
  ].filter(Boolean).join(path.delimiter);
}

export function assertRuntimeCommonCache({cache, runtimeTarget, log = console.log}) {
  if (!fs.statSync(cache, {throwIfNoEntry: false})?.isFile()) {
    throw new BuildError('runtime.split.cache', `CMake cache is missing after stdlib configure: ${cache}`);
  }
  const matches = fs.readFileSync(cache, 'utf8').split(/\r?\n/)
    .filter(line => line.startsWith('RUNTIME_COMMON_LIB_DIR:STRING='));
  if (matches.length !== 1) {
    throw new BuildError(
      'runtime.split.cache',
      `expected one RUNTIME_COMMON_LIB_DIR entry in ${cache}, found ${matches.length}`,
    );
  }
  const configured = path.resolve(matches[0].slice(matches[0].indexOf('=') + 1));
  const expectedRoot = path.resolve(runtimeTarget);
  if (configured !== expectedRoot && !configured.startsWith(`${expectedRoot}${path.sep}`)) {
    throw new BuildError(
      'runtime.split.cache',
      `RUNTIME_COMMON_LIB_DIR escaped target runtime: configured=${configured} expected_root=${expectedRoot}`,
    );
  }
  log(`RUNTIME_SPLIT_CMAKE_ASSERT_PASS configured=${configured} expected_root=${expectedRoot}`);
  return configured;
}

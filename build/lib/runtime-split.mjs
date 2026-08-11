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

function requireCompiler(file) {
  if (!fs.statSync(file, {throwIfNoEntry: false})?.isFile()) {
    throw new BuildError('runtime.sdk-abi', `packaged compiler is missing: ${file}`);
  }
  return file;
}

function runtimeRelativePath(target, role) {
  const host = role === 'host';
  return path.join(
    'runtime',
    'lib',
    host ? (target.spec.hostRuntimeTuple || target.spec.runtimeTuple) : target.spec.runtimeTuple,
    host ? (target.spec.hostRuntimeLibrary || target.spec.runtimeLibrary) : target.spec.runtimeLibrary,
  );
}

export function assertPlainHostRuntime({
  hostSdk,
  target,
  readSymbols = readRuntimeSymbols,
  log = console.log,
}) {
  const hostRoot = requireDirectory(hostSdk, 'CJCJ_SRCBUILD_HOST_SDK');
  const hostRuntime = requireRuntime(
    path.join(hostRoot, runtimeRelativePath(target, 'host')),
    'host',
  );
  const hostCount = countLoadBadMask(readSymbols(hostRuntime, target));
  if (hostCount !== 0) {
    throw new BuildError(
      'runtime.split',
      `${LOAD_BAD_MASK_SYMBOL} count contract failed: host=${hostCount} path=${hostRuntime}; expected host=0`,
    );
  }
  const hostReal = fs.realpathSync(hostRuntime);
  log(`HOST_RUNTIME_ASSERT_PASS host=${hostCount} path=${hostReal}`);
  return {hostSdk: hostRoot, hostRuntime: hostReal, hostCount};
}

export function runtimeSplitPaths({hostSdk, targetSdk, target}) {
  const hostRoot = requireDirectory(hostSdk, 'CJCJ_SRCBUILD_HOST_SDK');
  const targetRoot = requireDirectory(targetSdk, 'target SDK');
  const hostRelative = runtimeRelativePath(target, 'host');
  const targetRelative = runtimeRelativePath(target, 'target');
  return {
    hostSdk: hostRoot,
    targetSdk: targetRoot,
    hostRuntime: requireRuntime(path.join(hostRoot, hostRelative), 'host'),
    targetRuntime: requireRuntime(path.join(targetRoot, targetRelative), 'target'),
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

export function readCompilerSymbols(file, target) {
  const args = target.spec.os === 'darwin'
    ? ['-u', file]
    : ['-D', '--undefined-only', file];
  const result = spawnSync('nm', args, {encoding: 'utf8'});
  if (result.status !== 0) {
    throw new BuildError(
      'runtime.sdk-abi',
      `nm failed for packaged compiler ${file}: rc=${result.status} ${String(result.stderr || '').trim()}`,
    );
  }
  return result.stdout;
}

export function countLoadBadMask(symbols) {
  return String(symbols).split(/\r?\n/)
    .filter(line => new RegExp(`\\b${LOAD_BAD_MASK_SYMBOL}\\b`).test(line)).length;
}

export function assertSdkCompilerRuntimeAbi({
  sdk,
  target,
  readCompiler = readCompilerSymbols,
  readRuntime = readRuntimeSymbols,
  log = console.log,
}) {
  const sdkRoot = requireDirectory(sdk, 'SDK');
  const compiler = requireCompiler(path.join(sdkRoot, 'bin', 'cjc'));
  const runtime = requireRuntime(
    path.join(sdkRoot, runtimeRelativePath(target, 'target')),
    'packaged',
  );
  const compilerCount = countLoadBadMask(readCompiler(compiler, target));
  const runtimeCount = countLoadBadMask(readRuntime(runtime, target));
  if (![compilerCount, runtimeCount].every(count => count === 0 || count === 1)) {
    throw new BuildError(
      'runtime.sdk-abi',
      `${LOAD_BAD_MASK_SYMBOL} ABI count is not boolean: compiler=${compilerCount} path=${compiler}; ` +
      `runtime=${runtimeCount} path=${runtime}`,
    );
  }
  if (compilerCount !== runtimeCount) {
    throw new BuildError(
      'runtime.sdk-abi',
      `${LOAD_BAD_MASK_SYMBOL} ABI mismatch: compiler=${compilerCount} path=${compiler}; ` +
      `runtime=${runtimeCount} path=${runtime}`,
    );
  }
  const compilerReal = fs.realpathSync(compiler);
  const runtimeReal = fs.realpathSync(runtime);
  log(
    `SDK_COLOUR_ABI_ASSERT_PASS compiler=${compilerCount} path=${compilerReal} ` +
    `runtime=${runtimeCount} path=${runtimeReal}`,
  );
  return {
    sdk: sdkRoot,
    compiler: compilerReal,
    runtime: runtimeReal,
    compilerCount,
    runtimeCount,
  };
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

export function hostLoaderPath({hostSdk, targetSdk, target, inherited = '', includeTargetLlvm = true}) {
  const hostRoot = requireDirectory(hostSdk, 'CJCJ_SRCBUILD_HOST_SDK');
  const targetRoot = requireDirectory(targetSdk, 'target SDK');
  const hostRuntime = requireRuntime(
    path.join(hostRoot, runtimeRelativePath(target, 'host')),
    'host',
  );
  return [
    includeTargetLlvm ? path.join(targetRoot, 'third_party', 'llvm', 'lib') : '',
    path.dirname(hostRuntime),
    path.join(targetRoot, 'tools', 'lib'),
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

export function assertHostRuntimeCommands({
  buildFile,
  hostRuntime,
  targetRuntime,
  loaderEnv,
  log = console.log,
}) {
  if (!fs.statSync(buildFile, {throwIfNoEntry: false})?.isFile()) {
    throw new BuildError('runtime.split.commands', `generated build file is missing: ${buildFile}`);
  }
  const hostDirectory = path.dirname(fs.realpathSync(hostRuntime));
  const targetDirectory = path.dirname(fs.realpathSync(targetRuntime));
  const marker = `${loaderEnv}=`;
  let checked = 0;
  for (const line of fs.readFileSync(buildFile, 'utf8').split(/\r?\n/)) {
    if (!line.includes(marker) || !/(?:^|\s)cjc(?:\s|$)/.test(line)) continue;
    const value = line.slice(line.indexOf(marker) + marker.length).split(/\s/, 1)[0];
    const entries = value.split(path.delimiter);
    const hostIndex = entries.indexOf(hostDirectory);
    const targetIndex = entries.indexOf(targetDirectory);
    if (targetIndex >= 0 && (hostIndex < 0 || targetIndex < hostIndex)) {
      throw new BuildError(
        'runtime.split.commands',
        `generated cjc command selects target runtime before host: ${line}`,
      );
    }
    if (hostIndex >= 0) checked += 1;
  }
  if (checked === 0) {
    throw new BuildError(
      'runtime.split.commands',
      `no generated cjc command selects host runtime ${hostDirectory} in ${buildFile}`,
    );
  }
  log(
    `RUNTIME_SPLIT_COMMAND_ASSERT_PASS checked=${checked} host=${hostDirectory} ` +
    `target=${targetDirectory}`,
  );
  return checked;
}

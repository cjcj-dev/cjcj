// Port of cangjie-build/src/cangjie_build/stages/_common.py.

import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import {BuildError} from '../../lib/errors.mjs';
import {getLogger} from '../../lib/logging.mjs';
import {run} from '../../lib/runner.mjs';
import {hostLoaderPath} from '../../lib/runtime-split.mjs';
import {atomicJson} from '../../../ci/bootstrap/sdk-flow.mjs';
import * as mingw from '../../toolchain/mingw.mjs';
import * as staticLibs from '../../toolchain/static-libs.mjs';

const logger = getLogger('cangjie_build.stages');
export const WINDOWS_TARGET = 'windows-x86_64';

function joinPathsep(...parts) {
  return parts.filter(Boolean).join(path.delimiter);
}

export function consumerSdk(config, output = 'output') {
  const sdk = config.producerSdk || config.consumerSdk || path.join(config.softwareDir,'cangjie');
  if (config.consumerSdk && !config.producerSdk) requireDir(sdk, {stage: 'consumer.sdk'});
  return sdk;
}

// Old standalone adapters may only carry an environment; a resolved source
// build always supplies the selected plan and takes precedence over that input.
export function bootstrapHostSdk(config, env = process.env) {
  return config.selection?.bootstrapHost.install ?? config.officialSdkRoot ?? env.CJCJ_OFFICIAL_SDK_ROOT;
}

export function baseEnv(config, base = process.env) {
  const spec = config.target.spec;
  const hostSdk = bootstrapHostSdk(config, base);
  const dryRun = base.CANGJIE_BUILD_DRY_RUN === '1';
  if (!dryRun && (process.platform !== spec.nodePlatform || process.arch !== spec.nodeArch)) {
    throw new BuildError(
      'environment',
      `target ${spec.key} requires host ${spec.nodePlatform}/${spec.nodeArch}, current ${process.platform}/${process.arch}`,
    );
  }
  if (spec.nodePlatform === 'win32') {
    for (const [name, value] of [['CJCJ_NATIVE_LLVM_BIN', spec.llvmBinDir], ['CJCJ_NATIVE_OPENSSL_LIB', spec.opensslLibDir]]) {
      if (!value || !path.isAbsolute(value)) throw new BuildError('environment', `${name} must name an absolute native dependency directory`);
    }
  }
  for (const directory of [spec.llvmBinDir, spec.opensslLibDir].filter(Boolean)) {
    if (!dryRun && !fs.statSync(directory, {throwIfNoEntry: false})?.isDirectory()) {
      throw new BuildError('environment', `required platform dependency directory missing: ${directory}`);
    }
  }
  const env = {
    ...base,
    ...(hostSdk ? {CJCJ_OFFICIAL_SDK_ROOT: hostSdk} : {}),
    ARCH: spec.arch,
    SDK_NAME: spec.sdkName,
    CANGJIE_VERSION: config.cangjieVersion,
    STDX_VERSION: String(config.stdxVersion),
    BUILD_ROOT: config.buildRoot,
    WORKSPACE: config.workspace,
    // Formal source-build children are strict even when the invoking shell has
    // verifier report variables left over.  The kkk2 driver sets the private
    // active variable for step 19 only after applying its diagnostic-run caps.
    CJ_IR_VERIFIER_MODE: 'strict',
    CJ_IR_VERIFIER_REPORT: null,
  };
  const verifierReport = base.CJCJ_SRCBUILD_VERIFIER_REPORT_ACTIVE || '';
  if (verifierReport) {
    if (!path.isAbsolute(verifierReport)) {
      throw new BuildError('environment', 'CJCJ_SRCBUILD_VERIFIER_REPORT_ACTIVE must be an absolute path');
    }
    env.CJ_IR_VERIFIER_MODE = 'report';
    env.CJ_IR_VERIFIER_REPORT = verifierReport;
  }
  // Keep compiler outputs independent of the per-run workspace prefix.  This
  // is deliberately passed through CFLAGS/CXXFLAGS (rather than only to the
  // cache launcher): compiler/build.py and runtime/build.py inherit these
  // variables and use them when initializing their CMake projects.  ccache's
  // CCACHE_BASEDIR may present relative argv paths on a cache hit, while a
  // no-launcher build presents absolute paths; -ffile-prefix-map makes both
  // forms produce identical __FILE__ and DWARF records.
  const workspace = path.resolve(config.workspace);
  const sourcePrefixMap = [
    `-ffile-prefix-map=${workspace}=.`,
    `-ffile-prefix-map=${workspace}/cangjie_compiler=.`,
    `-ffile-prefix-map=${workspace}/cangjie_runtime/runtime=.`,
    '-ffile-prefix-map=..=.',
    '-ffile-prefix-map=../..=.',
    '-ffile-prefix-map=../../..=.',
    '-fdebug-compilation-dir=.',
  ].join(' ');
  for (const flag of ['CFLAGS', 'CXXFLAGS']) {
    env[flag] = [base[flag], sourcePrefixMap].filter(Boolean).join(' ');
  }
  // Official Linux builds select lld; the macOS guide relies on Apple's linker.
  if (spec.os === 'linux' || spec.crossCompile) env.LDFLAGS = '-fuse-ld=lld';
  const extraPathDirs = [spec.llvmBinDir];
  if (spec.needsMingw) {
    env.MINGW_PATH = mingw.installPath(config.buildRoot);
    extraPathDirs.unshift(path.join(mingw.installPath(config.buildRoot), 'bin'));
  }

  const ldPaths = [];
  if (spec.opensslLibDir) {
    env.OPENSSL_PATH = spec.opensslLibDir;
    ldPaths.push(spec.opensslLibDir);
  }

  const cangjieHome = consumerSdk(config);
  // The caller's whole environment is handed through (see `...base` above), so a
  // loader variable that is already present may be an inherited value rather than
  // this function's own platform derivation.  Track the derivation explicitly:
  // asking whether the key is merely non-empty would let an inherited value
  // suppress the dependency/tools prefixes below.
  let derivedLoaderPath = false;
  if (fs.statSync(cangjieHome, {throwIfNoEntry: false})?.isDirectory()) {
    env.CANGJIE_HOME = cangjieHome;
    extraPathDirs.unshift(path.join(cangjieHome, 'tools', 'bin'));
    extraPathDirs.unshift(path.join(cangjieHome, 'bin'));
    const runtimeLib = path.join(cangjieHome, 'runtime', 'lib', config.target.runtimeLibSubdir(config.buildType));
    if (fs.statSync(runtimeLib, {throwIfNoEntry: false})?.isDirectory()) {
      env[spec.loaderEnv] = hostLoaderPath({
        hostSdk,
        targetSdk: cangjieHome,
        target: config.target,
        inherited: joinPathsep(...ldPaths, base[spec.loaderEnv] || ''),
        includeTargetLlvm: false,
      });
      derivedLoaderPath = true;
    }
    const toolsLib = path.join(cangjieHome, 'tools', 'lib');
    if (!derivedLoaderPath && fs.statSync(toolsLib, {throwIfNoEntry: false})?.isDirectory()) {
      ldPaths.unshift(toolsLib);
    }
  }
  if (hostSdk && fs.statSync(hostSdk, {throwIfNoEntry: false})?.isDirectory()) {
    extraPathDirs.unshift(path.join(hostSdk, 'tools', 'bin'));
    extraPathDirs.unshift(path.join(hostSdk, 'bin'));
  }

  if (!config.target.spec.crossCompile && (config.consumerSdk || config.producerSdk)) extraPathDirs.unshift(path.join(cangjieHome, 'bin'));

  const stdxPath = config.stdxProfile === 'sdk-tools'
    ? path.join(config.repoPath('stdx'), 'target', config.target.stdxTargetSubdir(), 'static', 'stdx')
    : path.join(consumerSdk(config, config.target.primaryCompilerOutput()), 'stdx', config.target.stdxTargetSubdir(), 'static', 'stdx');
  env.CANGJIE_STDX_PATH = fs.statSync(stdxPath, {throwIfNoEntry: false})?.isDirectory() ? stdxPath : null;
  if (!derivedLoaderPath && ldPaths.length && spec.loaderEnv) {
    env[spec.loaderEnv] = joinPathsep(...ldPaths, base[spec.loaderEnv] || '');
  }
  env.PATH = joinPathsep(...extraPathDirs, spec.loaderEnv === 'PATH' ? env.PATH || base.PATH || '' : base.PATH || '');
  return env;
}

export function opensslLibPath(config) {
  return config.target.spec.opensslLibDir || null;
}

export function windowsCrossArgs(config, {sysroot = true} = {}) {
  const mingwPath = mingw.installPath(config.buildRoot);
  const args = ['--target', WINDOWS_TARGET];
  if (sysroot) args.push('--target-sysroot', `${mingwPath}/`);
  args.push('--target-toolchain', path.join(mingwPath, 'bin'));
  return args;
}

export function applyCompilerPathNeutralFlags(repoDir) {
  const file = path.join(repoDir, 'cmake', 'linux_toolchain.cmake');
  if (!fs.existsSync(file)) return;
  applyTextPatch(file, [
    [
      'set(C_FLAGS "${WARNINGS_SETTINGS} ${C_OTHER_FLAGS} ${OTHER_FLAGS}")\nset(CPP_FLAGS "${WARNINGS_SETTINGS} ${CXX_OTHER_FLAGS} ${OTHER_FLAGS}")',
      'set(C_FLAGS "${WARNINGS_SETTINGS} ${C_OTHER_FLAGS} ${OTHER_FLAGS} $ENV{CFLAGS}")\nset(CPP_FLAGS "${WARNINGS_SETTINGS} ${CXX_OTHER_FLAGS} ${OTHER_FLAGS} $ENV{CXXFLAGS}")',
    ],
  ], {stage: 'compiler.path-neutral-flags', marker: '$ENV{CXXFLAGS}'});
}

export function applyTextPatch(file, edits, {stage: stageName, marker} = {}) {
  requireFile(file, {stage: stageName});
  let text = fs.readFileSync(file, 'utf8');
  if (marker && text.includes(marker)) return;
  for (const [oldText, newText] of edits) {
    if (!text.includes(oldText)) throw new BuildError(stageName, `patch shape drift: ${JSON.stringify(oldText)} not found in ${file}`);
    text = text.replace(oldText, newText);
  }
  fs.writeFileSync(file, text);
  logger.info('Patched %s', file);
}

export function cmakePrefixPathFor(config) {
  const parts = [];
  if (config.target.spec.needsMingw) {
    parts.push(path.join(mingw.installPath(config.buildRoot), mingw.TARGET_TRIPLE));
  } else if (config.target.spec.needsStaticLibs) {
    const {ncurses:ncursesRoot,libedit:libeditRoot}=staticLibs.installationPaths(config.buildRoot);
    if (fs.existsSync(ncursesRoot) || fs.existsSync(libeditRoot)) parts.push(staticLibs.cmakePrefixPath(config.buildRoot));
  }
  return parts.length ? parts.join(path.delimiter) : null;
}

// A caller-supplied environment is a base, not a pair of loose key/value
// overrides.  Deriving the child environment from process.env while the caller
// decided what to do from its own environment silently strips that caller's
// selection -- the child then runs without the host SDK the gate was enabled
// for.  Take the base explicitly so a caller can hand over the environment it
// actually ran under.
export function envFrom(config, base, ...extra) {
  const env = baseEnv(config, base);
  const cmakePrefix = cmakePrefixPathFor(config);
  if (cmakePrefix) env.CMAKE_PREFIX_PATH = cmakePrefix;
  for (const layer of extra) Object.assign(env, layer);
  return env;
}

export function mergedEnv(config, ...extra) {
  return envFrom(config, process.env, ...extra);
}

export function explicitBuildJobs(maximum=Infinity, fallback) {
  const value=process.env.CANGJIE_BUILD_JOBS??(fallback===undefined?undefined:String(fallback));
  if(value===undefined)return [];
  if(!/^[1-9][0-9]*$/.test(value)||!Number.isSafeInteger(Number(value)))
    throw new BuildError('build.jobs','CANGJIE_BUILD_JOBS must be a positive integer');
  return ['--jobs',String(Math.min(Number(value),os.availableParallelism(),maximum))];
}

export function pythonExe() {
  return 'python3';
}

export async function runBuildScript(config, cwd, args, {stageName, extraEnv, cpuSet, script = 'build.py'} = {}) {
  requireDir(cwd, {stage: stageName});
  const envOverlay = extraEnv ? mergedEnv(config, extraEnv) : mergedEnv(config);
  const argv=[...(cpuSet?['taskset','-c',cpuSet]:[]), script.endsWith('.mjs') ? process.execPath : pythonExe(), script, ...args];
  const observation={stage:stageName,argv,cwd};
  try {
    const result=await run(argv,{cwd,envOverlay,stage:stageName});
    observation.exitCode=process.env.CANGJIE_BUILD_DRY_RUN==='1'?null:result.exitCode;
  } catch(error) {
    observation.exitCode=error.exitCode??null;observation.error=error.message;throw error;
  } finally {
    if(config.production&&process.env.CANGJIE_BUILD_DRY_RUN!=='1') {
      config.production.commands.push(observation);
      await atomicJson(path.join(config.workspace,'build/native-build.json'),config.production);
    }
  }
}

export function runBuildPy(config, cwd, args, options = {}) {
  return runBuildScript(config, cwd, args, {...options, script:'build.py'});
}

export function ensureDir(directory) {
  fs.mkdirSync(directory, {recursive: true});
  return directory;
}

export function requireDir(directory, {stage: stageName}) {
  if (!fs.statSync(directory, {throwIfNoEntry: false})?.isDirectory()) {
    throw new BuildError(stageName, `required directory missing: ${directory}`);
  }
  return directory;
}

export function requireFile(file, {stage: stageName}) {
  if (!fs.statSync(file, {throwIfNoEntry: false})?.isFile()) {
    throw new BuildError(stageName, `required file missing: ${file}`);
  }
  return file;
}

function copy(source, target) {
  fs.cpSync(source, target, {
    recursive: true,
    dereference: false,
    preserveTimestamps: true,
    verbatimSymlinks: true,
    force: true,
  });
}

export function copytree(source, destination, {stage: stageName}) {
  requireDir(source, {stage: stageName});
  fs.mkdirSync(path.dirname(destination), {recursive: true});
  copy(source, destination);
}

export function copyInto(source, destinationDirectory, {stage: stageName}) {
  requireFile(source, {stage: stageName});
  fs.mkdirSync(destinationDirectory, {recursive: true});
  const target = path.join(destinationDirectory, path.basename(source));
  copy(source, target);
  return target;
}

export function copyContents(sourceDirectory, destinationDirectory, {stage: stageName}) {
  requireDir(sourceDirectory, {stage: stageName});
  fs.mkdirSync(destinationDirectory, {recursive: true});
  for (const entry of fs.readdirSync(sourceDirectory)) {
    copy(path.join(sourceDirectory, entry), path.join(destinationDirectory, entry));
  }
}

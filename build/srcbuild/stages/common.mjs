// Port of cangjie-build/src/cangjie_build/stages/_common.py.

import fs from 'node:fs';
import path from 'node:path';
import {BuildError} from '../../lib/errors.mjs';
import {getLogger} from '../../lib/logging.mjs';
import {run} from '../../lib/runner.mjs';
import {hostLoaderPath} from '../../lib/runtime-split.mjs';
import * as mingw from '../../toolchain/mingw.mjs';
import * as staticLibs from '../../toolchain/static-libs.mjs';

const logger = getLogger('cangjie_build.stages');
export const WINDOWS_TARGET = 'windows-x86_64';

function joinPathsep(...parts) {
  return parts.filter(Boolean).join(path.delimiter);
}

export function baseEnv(config) {
  const spec = config.target.spec;
  const dryRun = process.env.CANGJIE_BUILD_DRY_RUN === '1';
  if (!dryRun && (process.platform !== spec.nodePlatform || process.arch !== spec.nodeArch)) {
    throw new BuildError(
      'environment',
      `target ${spec.key} requires host ${spec.nodePlatform}/${spec.nodeArch}, current ${process.platform}/${process.arch}`,
    );
  }
  for (const directory of [spec.llvmBinDir, spec.opensslLibDir].filter(Boolean)) {
    if (!dryRun && !fs.statSync(directory, {throwIfNoEntry: false})?.isDirectory()) {
      throw new BuildError('environment', `required platform dependency directory missing: ${directory}`);
    }
  }
  const env = {
    ARCH: spec.arch,
    SDK_NAME: spec.sdkName,
    CANGJIE_VERSION: config.cangjieVersion,
    STDX_VERSION: String(config.stdxVersion),
    BUILD_ROOT: config.buildRoot,
    WORKSPACE: config.workspace,
  };
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

  const cangjieHome = path.join(config.workspace, 'cangjie_compiler', 'output');
  if (fs.statSync(cangjieHome, {throwIfNoEntry: false})?.isDirectory()) {
    env.CANGJIE_HOME = cangjieHome;
    extraPathDirs.unshift(path.join(cangjieHome, 'tools', 'bin'));
    extraPathDirs.unshift(path.join(cangjieHome, 'bin'));
    const runtimeLib = path.join(cangjieHome, 'runtime', 'lib', config.target.runtimeLibSubdir(config.buildType));
    if (fs.statSync(runtimeLib, {throwIfNoEntry: false})?.isDirectory()) {
      env[spec.loaderEnv] = hostLoaderPath({
        hostSdk: process.env.CJCJ_SRCBUILD_HOST_SDK,
        targetSdk: cangjieHome,
        target: config.target,
        inherited: joinPathsep(...ldPaths, process.env[spec.loaderEnv] || ''),
        includeTargetLlvm: false,
      });
    }
    const toolsLib = path.join(cangjieHome, 'tools', 'lib');
    if (!env[spec.loaderEnv] && fs.statSync(toolsLib, {throwIfNoEntry: false})?.isDirectory()) {
      ldPaths.unshift(toolsLib);
    }
  }
  const hostSdk = process.env.CJCJ_SRCBUILD_HOST_SDK;
  if (hostSdk && fs.statSync(hostSdk, {throwIfNoEntry: false})?.isDirectory()) {
    extraPathDirs.unshift(path.join(hostSdk, 'tools', 'bin'));
    extraPathDirs.unshift(path.join(hostSdk, 'bin'));
  }

  const stdxPath = path.join(
    config.workspace, 'cangjie_stdx', 'target', config.target.stdxTargetSubdir(), 'static', 'stdx',
  );
  if (fs.statSync(stdxPath, {throwIfNoEntry: false})?.isDirectory()) env.CANGJIE_STDX_PATH = stdxPath;
  if (!env[spec.loaderEnv] && ldPaths.length && spec.loaderEnv) {
    env[spec.loaderEnv] = joinPathsep(...ldPaths, process.env[spec.loaderEnv] || '');
  }
  env.PATH = joinPathsep(...extraPathDirs, process.env.PATH || '');
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
    const ncursesRoot = path.join(config.buildRoot, `ncurses-${staticLibs.NCURSES_VERSION}`, 'usr');
    const libeditRoot = path.join(config.buildRoot, 'libedit-3.1');
    if (fs.existsSync(ncursesRoot) || fs.existsSync(libeditRoot)) parts.push(staticLibs.cmakePrefixPath(config.buildRoot));
  }
  return parts.length ? parts.join(path.delimiter) : null;
}

export function mergedEnv(config, ...extra) {
  const env = baseEnv(config);
  const cmakePrefix = cmakePrefixPathFor(config);
  if (cmakePrefix) env.CMAKE_PREFIX_PATH = cmakePrefix;
  for (const layer of extra) Object.assign(env, layer);
  return env;
}

export function pythonExe() {
  return 'python3';
}

export async function runBuildPy(config, cwd, args, {stageName, extraEnv} = {}) {
  requireDir(cwd, {stage: stageName});
  const envOverlay = extraEnv ? mergedEnv(config, extraEnv) : mergedEnv(config);
  await run([pythonExe(), 'build.py', ...args], {cwd, envOverlay, stage: stageName});
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
  fs.cpSync(source, target, {recursive: true, dereference: false, preserveTimestamps: true, force: true});
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

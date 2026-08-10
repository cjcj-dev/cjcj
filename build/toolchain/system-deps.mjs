// Port of cangjie-build/src/cangjie_build/toolchain/system_deps.py.

import fs from 'node:fs';
import {createHash} from 'node:crypto';
import path from 'node:path';
import {download, extract} from '../lib/archive.mjs';
import {BuildError} from '../lib/errors.mjs';
import {getLogger} from '../lib/logging.mjs';
import {RELEASE_PYTHON_VERSION} from '../lib/python-bundle.mjs';
import {run} from '../lib/runner.mjs';

const logger = getLogger('cangjie_build.toolchain.system_deps');

export const APT_PACKAGES = Object.freeze([
  'tar', 'unzip', 'wget', 'curl', 'libcurl4', 'expat', 'openssl', 'make', 'gcc', 'g++',
  'gettext', 'nfs-common', 'libtool', 'sqlite3', 'zlib1g-dev', 'libssl-dev', 'cmake',
  'ninja-build', 'libcurl4-openssl-dev', 'sudo', 'autoconf', 'build-essential',
  'rapidjson-dev', 'texinfo', 'binutils', 'libelf-dev', 'libdwarf-dev', 'openssh-client',
  'ssh', 'dos2unix', 'libxext-dev', 'libxtst-dev', 'libxt-dev', 'libcups2-dev', 'clang',
  'clang-15', 'lld', 'libxrender-dev', 'zip', 'bzip2', 'libopenmpi-dev', 'vim', 'gdb',
  'lldb', 'libclang-15-dev', 'libgtest-dev', 'rpm', 'patch', 'libtinfo5', 'cpio',
  'rpm2cpio', 'libncurses5', 'libncurses5-dev', 'strace', 'net-tools', 'swig', 'python3-dev',
]);

// cangjie_build/docs/macos.md:52-82 and docs/env.md:21-34. coreutils and
// gnu-tar are orchestration-only additions: bounded gates need gtimeout and the
// official package recipe requires GNU tar rather than BSD tar.
export const BREW_PACKAGES = Object.freeze([
  'ninja', 'llvm@16', 'openssl@3', 'bison', 'googletest', 'gnu-tar', 'swig', 'coreutils',
]);

export function pythonSeries(version) {
  const match = String(version).match(/^(\d+)\.(\d+)\.\d+$/);
  if (!match) throw new BuildError('system_deps', `unsupported Python version: ${version || '<empty>'}`);
  return `${match[1]}.${match[2]}`;
}

// Two constraints select one series, so derive it instead of writing it twice.
// Our LLDB sources still use CPython interfaces removed after 3.12
// (_Py_IsFinalizing, PyEval_ThreadsInitialized), and every release package
// ships CPython RELEASE_PYTHON_VERSION beside a cjdb whose _lldb extension only
// loads in that exact series (build/lib/python-bundle.mjs:43-48,267). The
// official nightly SDK links its own LLDB against the same series, which is
// why third_party/llvm/lib/python3.11 is what the packager finds there.
export const LLVM_PYTHON_VERSION = pythonSeries(RELEASE_PYTHON_VERSION);
export const LLVM_PYTHON_FORMULA = `python@${LLVM_PYTHON_VERSION}`;

// cangjie_build/docs/macos.md:52-76 still requires CMake >=3.17 and <4 and
// explicitly directs macOS users to Kitware's 3.x archive. Homebrew/core has no
// versioned CMake 3 formula, so keep the official archive and digest explicit.
export const CMAKE_VERSION = '3.31.10';
export const CMAKE_ARCHIVE = `cmake-${CMAKE_VERSION}-macos-universal.tar.gz`;
export const CMAKE_URL = `https://github.com/Kitware/CMake/releases/download/v${CMAKE_VERSION}/${CMAKE_ARCHIVE}`;
export const CMAKE_SHA256 = 'be9f3faeeaf7921cc2d77cea711dd5e6f72c63af2810cacd9205b3ce8d1593c9';

function which(name) {
  for (const directory of (process.env.PATH || '').split(path.delimiter)) {
    const candidate = path.join(directory, name);
    try {
      fs.accessSync(candidate, fs.constants.X_OK);
      return candidate;
    } catch {}
  }
  return null;
}

function isFile(file) {
  return fs.statSync(file, {throwIfNoEntry: false})?.isFile() === true;
}

function isExecutable(file) {
  try {
    fs.accessSync(file, fs.constants.X_OK);
    return true;
  } catch {
    return false;
  }
}

async function fileSha256(file) {
  const hash = createHash('sha256');
  for await (const chunk of fs.createReadStream(file)) hash.update(chunk);
  return hash.digest('hex');
}

function publishPath(directory) {
  process.env.PATH = `${directory}${path.delimiter}${process.env.PATH || ''}`;
  if (process.env.GITHUB_ACTIONS === 'true' && !process.env.GITHUB_PATH) {
    throw new BuildError('system_deps.cmake', 'GITHUB_PATH is required on GitHub Actions');
  }
  if (process.env.GITHUB_PATH) fs.appendFileSync(process.env.GITHUB_PATH, `${directory}\n`);
}

function parseToolVersion(stdout, pattern, requirement) {
  const match = String(stdout).match(pattern);
  if (!match) throw new BuildError('system_deps', `${requirement}, got: ${String(stdout).trim()}`);
  return match.slice(1).map(Number);
}

export function assertCmakeVersion(stdout) {
  const [major, minor] = parseToolVersion(stdout, /cmake version (\d+)\.(\d+)/, 'cmake >=3.17 and <4 is required');
  if (major >= 4 || major < 3 || (major === 3 && minor < 17)) {
    throw new BuildError('system_deps', `cmake >=3.17 and <4 is required, got: ${String(stdout).trim()}`);
  }
}

async function assertPython(python, {
  runCommand = run,
  fileExists = isFile,
  expectedVersion,
} = {}) {
  const result = await runCommand([
    python,
    '-c',
    'import sys, sysconfig; print(f"{sys.version_info.major}.{sys.version_info.minor}"); print(sysconfig.get_config_var("INCLUDEPY") or "")',
  ], {stage: 'system_deps.python', capture: true, logOutput: false});
  const [version = '', includeDir = ''] = result.stdout.trim().split(/\r?\n/);
  const match = version.match(/^(\d+)\.(\d+)$/);
  if (!match || Number(match[1]) < 3 || (Number(match[1]) === 3 && Number(match[2]) <= 7)) {
    throw new BuildError('system_deps', `Python >3.7 is required, got: ${version || '<empty>'}`);
  }
  if (expectedVersion && version !== expectedVersion) {
    throw new BuildError('system_deps', `Python ${expectedVersion} is required, got: ${version}`);
  }
  const header = path.join(includeDir, 'Python.h');
  if (!includeDir || !fileExists(header)) {
    throw new BuildError('system_deps', `Python headers are required, missing: ${header}`);
  }
  return version;
}

async function llvmPythonPrefix(runCommand) {
  const prefix = await runCommand(['brew', '--prefix', LLVM_PYTHON_FORMULA], {
    stage: 'system_deps.python.prefix', capture: true, logOutput: false,
  });
  return prefix.stdout.trim();
}

// Versioned Homebrew Python formulae keep their unversioned python3 shim in
// libexec/bin, so libexec is the keg root whose bin/python3 exists.
function llvmPythonHome(prefix) {
  return path.join(prefix, 'libexec');
}

async function installLlvmPython({
  runCommand = run,
  fileExists = isFile,
  exposePath = publishPath,
} = {}) {
  await runCommand(['brew', 'install', '--skip-link', LLVM_PYTHON_FORMULA], {
    stage: 'system_deps.python.install',
  });
  // Publish only the shim directory: the keg remains unlinked, while later
  // Actions steps resolve the same supported interpreter.
  const pythonBin = path.join(llvmPythonHome(await llvmPythonPrefix(runCommand)), 'bin');
  const kegPython = path.join(pythonBin, 'python3');
  const version = await assertPython(kegPython, {
    runCommand,
    fileExists,
    expectedVersion: LLVM_PYTHON_VERSION,
  });
  exposePath(pythonBin);
  logger.info('Selected unlinked %s (%s) from %s', LLVM_PYTHON_FORMULA, version, pythonBin);
}

// PATH does not decide which Python LLDB compiles against. The nested LLDB
// CMake runs its own find_package(Python3 COMPONENTS Interpreter Development),
// and on macOS that takes the newest framework Python it can see. The one hook
// that reaches it is TARGET_PYTHON_PATH: cangjie_compiler
// third_party/cmake/BuildCJDB.cmake:39-45 forwards
// -DPython3_EXECUTABLE=${TARGET_PYTHON_PATH}/bin/python3 only when that
// variable is set, and :101-106 derives the site-packages version from the same
// interpreter. Return the keg root that owns that bin/python3, refusing any
// other series so a runner's Homebrew upgrade cannot silently pick it up.
export async function cjdbPythonHome({runCommand = run, fileExists = isFile} = {}) {
  const home = llvmPythonHome(await llvmPythonPrefix(runCommand));
  const version = await assertPython(path.join(home, 'bin', 'python3'), {
    runCommand,
    fileExists,
    expectedVersion: LLVM_PYTHON_VERSION,
  });
  logger.info('cjdb LLDB builds against Python %s from %s', version, home);
  return home;
}

export async function installCmake3(buildRoot, {
  downloadArchive = download,
  extractArchive = extract,
  hashFile = fileSha256,
  executable = isExecutable,
  exposePath = publishPath,
} = {}) {
  fs.mkdirSync(buildRoot, {recursive: true});
  const archive = path.join(buildRoot, CMAKE_ARCHIVE);
  const root = path.join(buildRoot, `cmake-${CMAKE_VERSION}-macos-universal`);
  const cmake = path.join(root, 'CMake.app', 'Contents', 'bin', 'cmake');
  await downloadArchive(CMAKE_URL, archive);
  const digest = await hashFile(archive);
  if (digest !== CMAKE_SHA256) {
    throw new BuildError('system_deps.cmake', `CMake archive SHA-256 mismatch: ${digest}`);
  }
  if (!executable(cmake)) await extractArchive(archive, buildRoot);
  if (!executable(cmake)) {
    throw new BuildError('system_deps.cmake', `CMake executable is missing after extraction: ${cmake}`);
  }
  exposePath(path.dirname(cmake));
  return cmake;
}

function assertNativeHost(config) {
  const spec = config.target.spec;
  if (process.platform !== spec.nodePlatform || process.arch !== spec.nodeArch) {
    throw new BuildError(
      'system_deps',
      `target ${spec.key} requires host ${spec.nodePlatform}/${spec.nodeArch}, current ${process.platform}/${process.arch}`,
    );
  }
}

function aptPackagesFor(config) {
  if (config.target.spec.legacyNcursesPackages) return APT_PACKAGES;
  const legacy = new Set(['libtinfo5', 'libncurses5', 'libncurses5-dev']);
  return [...APT_PACKAGES.filter(name => !legacy.has(name)), 'libtinfo6', 'libncurses-dev'];
}

async function installLinux(config) {
  if (!which('apt-get')) throw new BuildError('system_deps', 'apt-get not found; an Ubuntu/Debian host is required');
  const packages = aptPackagesFor(config);
  const sudo = which('sudo') ? ['sudo'] : [];
  logger.info('Installing %d apt packages', packages.length);
  await run([...sudo, 'apt-get', 'update'], {stage: 'system_deps.update'});
  await run([...sudo, 'apt-get', 'install', '-y', '--no-install-recommends', ...packages], {
    stage: 'system_deps.install',
    envOverlay: {DEBIAN_FRONTEND: 'noninteractive'},
  });
}

export async function installDarwin(config, {
  runCommand = run,
  fileExists = isFile,
  cmakeInstaller = installCmake3,
  findExecutable = which,
  exposePath = publishPath,
} = {}) {
  if (!findExecutable('brew')) throw new BuildError('system_deps', 'Homebrew is required by docs/macos.md');
  await installLlvmPython({runCommand, fileExists, exposePath});
  logger.info('Installing %d Homebrew packages', BREW_PACKAGES.length);
  await runCommand(['brew', 'install', ...BREW_PACKAGES], {stage: 'system_deps.install'});
  const pythonVersion = await assertPython('python3', {
    runCommand,
    fileExists,
    expectedVersion: LLVM_PYTHON_VERSION,
  });
  logger.info('Selected host Python %s with development headers', pythonVersion);
  const cmakeExecutable = await cmakeInstaller(config.buildRoot);
  const cmake = await runCommand([cmakeExecutable, '--version'], {
    stage: 'system_deps.cmake', capture: true, logOutput: false,
  });
  assertCmakeVersion(cmake.stdout);
  logger.info('Selected %s at %s', cmake.stdout.trim().split(/\r?\n/, 1)[0], cmakeExecutable);
  const llvm = await runCommand([path.join(config.target.spec.llvmBinDir, 'llvm-config'), '--version'], {
    stage: 'system_deps.llvm', capture: true, logOutput: false,
  });
  if (!/^16\./.test(llvm.stdout.trim())) {
    throw new BuildError('system_deps', `LLVM >=16 and <17 is required, got: ${llvm.stdout.trim()}`);
  }
  logger.info('Selected LLVM %s', llvm.stdout.trim());
  const openssl = await runCommand([path.resolve(config.target.spec.opensslLibDir, '..', 'bin', 'openssl'), 'version'], {
    stage: 'system_deps.openssl', capture: true, logOutput: false,
  });
  if (!/^OpenSSL 3\./.test(openssl.stdout.trim())) {
    throw new BuildError('system_deps', `OpenSSL 3 is required, got: ${openssl.stdout.trim()}`);
  }
  logger.info('Selected %s', openssl.stdout.trim());
  await runCommand(['xcrun', '--sdk', 'macosx', '--show-sdk-path'], {stage: 'system_deps.xcode'});
}

export async function install(config) {
  assertNativeHost(config);
  if (config.target.spec.os === 'darwin') return installDarwin(config);
  if (config.target.spec.nodePlatform === 'linux') return installLinux(config);
  throw new BuildError('system_deps', `unsupported source-build host: ${process.platform}`);
}

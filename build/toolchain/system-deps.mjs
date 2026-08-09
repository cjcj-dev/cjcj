// Port of cangjie-build/src/cangjie_build/toolchain/system_deps.py.

import fs from 'node:fs';
import path from 'node:path';
import {BuildError} from '../lib/errors.mjs';
import {getLogger} from '../lib/logging.mjs';
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
  'python3', 'ninja', 'llvm@16', 'openssl@3', 'bison', 'googletest', 'gnu-tar', 'swig', 'coreutils',
]);

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

async function installDarwin(config) {
  if (!which('brew')) throw new BuildError('system_deps', 'Homebrew is required by docs/macos.md');
  logger.info('Installing %d Homebrew packages', BREW_PACKAGES.length);
  await run(['brew', 'install', ...BREW_PACKAGES], {stage: 'system_deps.install'});
  const cmake = await run(['cmake', '--version'], {
    stage: 'system_deps.cmake', capture: true, logOutput: false,
  });
  const version = cmake.stdout.match(/cmake version (\d+)\.(\d+)/);
  if (!version || Number(version[1]) >= 4 || Number(version[1]) < 3 || (Number(version[1]) === 3 && Number(version[2]) < 17)) {
    throw new BuildError('system_deps', `cmake >=3.17 and <4 is required, got: ${cmake.stdout.trim()}`);
  }
  const llvm = await run([path.join(config.target.spec.llvmBinDir, 'llvm-config'), '--version'], {
    stage: 'system_deps.llvm', capture: true, logOutput: false,
  });
  if (!/^16\./.test(llvm.stdout.trim())) {
    throw new BuildError('system_deps', `LLVM >=16 and <17 is required, got: ${llvm.stdout.trim()}`);
  }
  const openssl = await run([path.resolve(config.target.spec.opensslLibDir, '..', 'bin', 'openssl'), 'version'], {
    stage: 'system_deps.openssl', capture: true, logOutput: false,
  });
  if (!/^OpenSSL 3\./.test(openssl.stdout.trim())) {
    throw new BuildError('system_deps', `OpenSSL 3 is required, got: ${openssl.stdout.trim()}`);
  }
  await run(['xcrun', '--sdk', 'macosx', '--show-sdk-path'], {stage: 'system_deps.xcode'});
}

export async function install(config) {
  assertNativeHost(config);
  if (config.target.spec.os === 'darwin') return installDarwin(config);
  if (config.target.spec.nodePlatform === 'linux') return installLinux(config);
  throw new BuildError('system_deps', `unsupported source-build host: ${process.platform}`);
}

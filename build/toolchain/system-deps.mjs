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

export async function install() {
  if (process.platform !== 'linux') {
    throw new BuildError('system_deps', `install-system-deps only supports Linux (current: ${process.platform})`);
  }
  if (!which('apt-get')) throw new BuildError('system_deps', 'apt-get not found; an Ubuntu/Debian host is required');
  const sudo = which('sudo') ? ['sudo'] : [];
  logger.info('Installing %d apt packages', APT_PACKAGES.length);
  await run([...sudo, 'apt-get', 'update'], {stage: 'system_deps.update'});
  await run([...sudo, 'apt-get', 'install', '-y', '--no-install-recommends', ...APT_PACKAGES], {
    stage: 'system_deps.install',
    envOverlay: {DEBIAN_FRONTEND: 'noninteractive'},
  });
}

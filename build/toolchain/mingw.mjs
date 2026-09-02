// Port of cangjie-build/src/cangjie_build/toolchain/mingw.py.

import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import {download, extract} from '../lib/archive.mjs';
import {fetchSource, shallowClone} from '../lib/git.mjs';
import {getLogger, stage} from '../lib/logging.mjs';
import {run} from '../lib/runner.mjs';

const logger = getLogger('cangjie_build.toolchain.mingw');

export const LLVM_MINGW_TAG = '20220906';
export const LLVM_MINGW_URL = `https://github.com/mstorsjo/llvm-mingw/archive/refs/tags/${LLVM_MINGW_TAG}.tar.gz`;
export const LLVM_PROJECT_REMOTE = 'https://gitee.com/openharmony/third_party_llvm-project.git';
export const LLVM_PROJECT_COMMIT = '5c68a1cb123161b54b72ce90e7975d95a8eaf2a4';
export const MINGW_W64_REMOTE = 'https://gitee.com/openharmony/third_party_mingw-w64.git';
export const OPENSSL_VERSION = '3.0.9';
export const OPENSSL_URL = `https://github.com/openssl/openssl/archive/refs/tags/openssl-${OPENSSL_VERSION}.tar.gz`;
export const INSTALL_DIR_NAME = 'llvm-mingw-w64';
export const TARGET_TRIPLE = 'x86_64-w64-mingw32';

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

export function installPath(buildRoot) {
  return path.join(buildRoot, INSTALL_DIR_NAME);
}

export function isInstalled(buildRoot) {
  const installRoot = installPath(buildRoot);
  return fs.existsSync(path.join(installRoot, 'bin', `${TARGET_TRIPLE}-clang`))
    && fs.existsSync(path.join(installRoot, TARGET_TRIPLE, 'lib', 'libssl.a'));
}

export async function install(buildRoot, {jobs} = {}) {
  if (isInstalled(buildRoot)) {
    logger.info('MinGW toolchain already present at %s; skipping', installPath(buildRoot));
    return;
  }
  fs.mkdirSync(buildRoot, {recursive: true});
  const cpus = jobs ?? os.cpus().length ?? 2;
  const installRoot = installPath(buildRoot);

  await stage('mingw:llvm-mingw', async () => {
    const archive = path.join(buildRoot, `llvm-mingw-${LLVM_MINGW_TAG}.tar.gz`);
    await download(LLVM_MINGW_URL, archive);
    const source = await extract(archive, buildRoot);

    const llvmProject = path.join(source, 'llvm-project');
    if (!fs.existsSync(llvmProject)) {
      fs.mkdirSync(llvmProject, {recursive: true});
      await run(['git', 'init'], {cwd: llvmProject, stage: 'mingw.llvm.init'});
      await run(['git', 'remote', 'add', 'origin', LLVM_PROJECT_REMOTE], {
        cwd: llvmProject, stage: 'mingw.llvm.remote',
      });
      await fetchSource(LLVM_PROJECT_REMOTE, LLVM_PROJECT_COMMIT, {
        cwd: llvmProject, stage: 'mingw.llvm.fetch',
      });
      await run(['git', 'checkout', 'FETCH_HEAD'], {cwd: llvmProject, stage: 'mingw.llvm.checkout'});
    }

    const mingwW64 = path.join(source, 'mingw-w64');
    if (!fs.existsSync(mingwW64)) {
      await shallowClone(MINGW_W64_REMOTE, mingwW64);
    }

    const toolchainEnv = {TOOLCHAIN_ARCHS: 'x86_64'};
    const hostBootstrapEnv = which('ld.lld') ? {LLVM_CMAKEFLAGS: '-DLLVM_USE_LINKER=lld'} : {};
    const script = async (name, extra = [], {host = false} = {}) => {
      const envOverlay = {...toolchainEnv, MAKEFLAGS: `-j${cpus}`};
      if (host) Object.assign(envOverlay, hostBootstrapEnv);
      await run([path.join(source, name), installRoot, ...extra], {
        cwd: source, envOverlay, stage: `mingw.${name}`,
      });
    };

    await script('build-llvm.sh', ['--disable-lldb'], {host: true});
    await script('strip-llvm.sh');
    await script('install-wrappers.sh');
    await script('build-mingw-w64.sh', ['--with-default-msvcrt=msvcrt']);
    await script('build-mingw-w64-tools.sh');
    await script('build-compiler-rt.sh');
    await script('build-libcxx.sh');
    await script('build-mingw-w64-libraries.sh');

    const targetLibDir = path.join(installRoot, TARGET_TRIPLE, 'lib');
    const sourceLibrary = path.join(targetLibDir, 'libmingwex.a');
    for (const alias of ['libssp.a', 'libssp_nonshared.a']) {
      const target = path.join(targetLibDir, alias);
      if (!fs.existsSync(target)) fs.copyFileSync(sourceLibrary, target);
    }
  });

  await stage('mingw:openssl', async () => {
    const archive = path.join(buildRoot, `openssl-${OPENSSL_VERSION}.tar.gz`);
    await download(OPENSSL_URL, archive);
    const source = await extract(archive, buildRoot);
    const buildDir = path.join(source, 'build');
    fs.mkdirSync(buildDir, {recursive: true});
    const envOverlay = {PATH: `${path.join(installRoot, 'bin')}${path.delimiter}${process.env.PATH || ''}`};
    await run([
      path.join(source, 'Configure'),
      'mingw64',
      `--prefix=${path.join(installRoot, TARGET_TRIPLE)}`,
      `--cross-compile-prefix=${TARGET_TRIPLE}-`,
      '--libdir=lib',
    ], {cwd: buildDir, envOverlay, stage: 'mingw.openssl.configure'});
    await run(['make', `-j${cpus}`], {cwd: buildDir, envOverlay, stage: 'mingw.openssl.make'});
    await run(['make', 'install'], {cwd: buildDir, envOverlay, stage: 'mingw.openssl.install'});
  });
}

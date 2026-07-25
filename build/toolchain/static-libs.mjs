// Port of cangjie-build/src/cangjie_build/toolchain/static_libs.py.

import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import {download, extract} from '../lib/archive.mjs';
import {getLogger, stage} from '../lib/logging.mjs';
import {run} from '../lib/runner.mjs';

const logger = getLogger('cangjie_build.toolchain.static_libs');

export const NCURSES_VERSION = '6.5';
export const NCURSES_URL = `https://ftp.gnu.org/pub/gnu/ncurses/ncurses-${NCURSES_VERSION}.tar.gz`;
export const LIBEDIT_TARBALL = 'libedit-20210910-3.1';
export const LIBEDIT_URL = `https://thrysoee.dk/editline/${LIBEDIT_TARBALL}.tar.gz`;

function ncursesLib(buildRoot) {
  return path.join(buildRoot, `ncurses-${NCURSES_VERSION}`, 'usr', 'lib', 'libncurses.a');
}

function libeditLib(buildRoot) {
  return path.join(buildRoot, 'libedit-3.1', 'lib', 'libedit.a');
}

export function isInstalled(buildRoot) {
  return fs.statSync(ncursesLib(buildRoot), {throwIfNoEntry: false})?.isFile() === true
    && fs.statSync(libeditLib(buildRoot), {throwIfNoEntry: false})?.isFile() === true;
}

export async function install(buildRoot, {jobs} = {}) {
  if (isInstalled(buildRoot)) {
    logger.info('Static libs already present at %s; skipping', buildRoot);
    return;
  }
  fs.mkdirSync(buildRoot, {recursive: true});
  const cpus = jobs ?? os.cpus().length ?? 2;

  await stage('static_libs:ncurses', async () => {
    const archive = path.join(buildRoot, `ncurses-${NCURSES_VERSION}.tar.gz`);
    await download(NCURSES_URL, archive);
    const source = await extract(archive, buildRoot);
    const installRoot = path.join(buildRoot, `ncurses-${NCURSES_VERSION}`);
    await run([
      './configure',
      '--with-termlib',
      '--with-terminfo-dirs=/etc/terminfo:/lib/terminfo:/usr/share/terminfo',
      '--disable-widec',
      '--disable-overwrite',
      '--disable-root-environ',
    ], {
      cwd: source,
      envOverlay: {
        CC: 'clang',
        CXX: 'clang++',
        CFLAGS: '-fPIC -fstack-protector-strong -Wl,-z,relro,-z,now,-z,noexecstack',
        CXXFLAGS: '-fstack-protector-strong -Wl,-z,relro,-z,now,-z,noexecstack',
      },
      stage: 'static_libs.ncurses.configure',
    });
    await run(['make', `-j${cpus}`], {cwd: source, stage: 'static_libs.ncurses.make'});
    await run(['make', 'install', `DESTDIR=${installRoot}`], {
      cwd: source, stage: 'static_libs.ncurses.install',
    });
  });

  await stage('static_libs:libedit', async () => {
    const archive = path.join(buildRoot, `${LIBEDIT_TARBALL}.tar.gz`);
    await download(LIBEDIT_URL, archive);
    const source = await extract(archive, buildRoot);
    const prefix = path.join(buildRoot, 'libedit-3.1');
    await run(['./configure', '--with-pic', '--enable-shared=no', `--prefix=${prefix}`], {
      cwd: source, stage: 'static_libs.libedit.configure',
    });
    await run(['make', `-j${cpus}`], {cwd: source, stage: 'static_libs.libedit.make'});
    await run(['make', 'install'], {cwd: source, stage: 'static_libs.libedit.install'});
  });
}

export function cmakePrefixPath(buildRoot) {
  return [
    path.join(buildRoot, 'libedit-3.1'),
    path.join(buildRoot, `ncurses-${NCURSES_VERSION}`, 'usr'),
  ].join(path.delimiter);
}

export function targetLibPath(buildRoot) {
  return path.join(buildRoot, `ncurses-${NCURSES_VERSION}`, 'usr', 'lib');
}

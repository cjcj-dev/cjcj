// Port of cangjie-build/src/cangjie_build/toolchain/static_libs.py.

import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import {download, extract} from '../lib/archive.mjs';
import {getLogger, stage} from '../lib/logging.mjs';
import {run} from '../lib/runner.mjs';

const logger = getLogger('cangjie_build.toolchain.static_libs');

export const NCURSES_VERSION = '6.6';
export const NCURSES_URL = `https://ftp.gnu.org/pub/gnu/ncurses/ncurses-${NCURSES_VERSION}.tar.gz`;
export const LIBEDIT_TARBALL = 'libedit-20260512-3.1';
export const LIBEDIT_URL = `https://thrysoee.dk/editline/${LIBEDIT_TARBALL}.tar.gz`;

export function installationPaths(buildRoot) {
  return {ncurses:path.join(buildRoot, `ncurses-${NCURSES_VERSION}`, 'usr'),
    libedit:path.join(buildRoot, LIBEDIT_TARBALL)};
}

function componentInstalled(buildRoot, component) {
  const prefix=installationPaths(buildRoot)[component];
  const required=component==='ncurses'
    ? ['lib/libncurses.a','lib/libtinfo.a','lib/libpanel.a','lib/libform.a','include/ncurses/curses.h','include/ncurses/term.h','include/ncurses/panel.h']
    : ['lib/libedit.a','include/histedit.h','lib/pkgconfig/libedit.pc'];
  if(!required.every(file=>fs.statSync(path.join(prefix,file),{throwIfNoEntry:false})?.isFile()))return false;
  if(component==='ncurses')return fs.readFileSync(path.join(prefix,'include/ncurses/curses.h'),'utf8')
    .includes('#define NCURSES_VERSION \"'+NCURSES_VERSION+'\"');
  return true;
}

export function isInstalled(buildRoot) {
  return componentInstalled(buildRoot,'ncurses') && componentInstalled(buildRoot,'libedit');
}

export async function install(buildRoot, {jobs} = {}) {
  if (isInstalled(buildRoot)) {
    logger.info('Static libs already present at %s; skipping', buildRoot);
    return;
  }
  fs.mkdirSync(buildRoot, {recursive: true});
  const cpus = jobs ?? os.availableParallelism();
  if(!Number.isSafeInteger(cpus)||cpus<1)throw new Error('STATIC_LIBS_JOBS');
  // autotools has no launcher variable; the compiler cache cmake-driven stages
  // use (CMAKE_*_COMPILER_LAUNCHER, sccache on GitHub Actions) rides in CC/CXX.
  const cc = [process.env.CMAKE_C_COMPILER_LAUNCHER, 'clang'].filter(Boolean).join(' ');
  const cxx = [process.env.CMAKE_CXX_COMPILER_LAUNCHER, 'clang++'].filter(Boolean).join(' ');

  if(!componentInstalled(buildRoot,'ncurses'))await stage('static_libs:ncurses', async () => {
    const archive = path.join(buildRoot, `ncurses-${NCURSES_VERSION}.tar.gz`);
    await download(NCURSES_URL, archive);
    const source = await extract(archive, path.join(buildRoot,'sources'));
    const installRoot = path.join(buildRoot, `ncurses-${NCURSES_VERSION}`);
    await run([
      './configure',
      '--prefix=/usr',
      '--libdir=/usr/lib',
      '--with-termlib',
      '--with-terminfo-dirs=/etc/terminfo:/lib/terminfo:/usr/share/terminfo',
      '--disable-widec',
      '--disable-overwrite',
      '--disable-root-environ',
    ], {
      cwd: source,
      envOverlay: {
        CC: cc,
        CXX: cxx,
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

  if(!componentInstalled(buildRoot,'libedit'))await stage('static_libs:libedit', async () => {
    const archive = path.join(buildRoot, `${LIBEDIT_TARBALL}.tar.gz`);
    await download(LIBEDIT_URL, archive);
    const source = await extract(archive, path.join(buildRoot,'sources'));
    const {libedit:prefix,ncurses}=installationPaths(buildRoot);
    // libedit keeps configure's own compiler choice; only the launcher is added.
    const launcher = process.env.CMAKE_C_COMPILER_LAUNCHER;
    await run(['./configure', '--with-pic', '--enable-shared=no', `--prefix=${prefix}`], {
      cwd: source,
      envOverlay: {
        ...(launcher?{CC:`${launcher} ${process.env.CC || 'cc'}`} : {}),
        CPPFLAGS:[`-I${path.join(ncurses,'include')}`,`-I${path.join(ncurses,'include/ncurses')}`,process.env.CPPFLAGS].filter(Boolean).join(' '),
        LDFLAGS:[`-L${path.join(ncurses,'lib')}`,process.env.LDFLAGS].filter(Boolean).join(' '),
      },
      stage: 'static_libs.libedit.configure',
    });
    await run(['make', `-j${cpus}`], {cwd: source, stage: 'static_libs.libedit.make'});
    await run(['make', 'install'], {cwd: source, stage: 'static_libs.libedit.install'});
  });
  if(!isInstalled(buildRoot))throw new Error('STATIC_LIBS_INSTALL_INCOMPLETE');
}

export function cmakePrefixPath(buildRoot) {
  const {libedit,ncurses}=installationPaths(buildRoot);
  return [libedit,ncurses].join(path.delimiter);
}

export function targetLibPath(buildRoot) {
  return path.join(buildRoot, `ncurses-${NCURSES_VERSION}`, 'usr', 'lib');
}

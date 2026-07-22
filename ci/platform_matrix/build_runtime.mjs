#!/usr/bin/env zx
// Build the exact pinned runtime on the current host. Windows enters MSYS2
// CLANG64 only for build.py, whose Windows recipe requires POSIX make/PATH.

import fs from 'node:fs/promises';
import path from 'node:path';
import {printCommonVersions, stageBegin} from './common.mjs';

const {root} = stageBegin('runtime');
const source = process.env.RUNTIME_SOURCE || path.join(process.cwd(), 'runtime-source');
const version = process.env.RUNTIME_VERSION || '1.2.0-alpha.20260721165458';
const installRoot = path.join(root, 'runtime-install');

await printCommonVersions();
console.log(`runtime_source=${source}\nruntime_ref=${process.env.RUNTIME_REF || 'unknown'}`);
const buildPy = path.join(source, 'runtime', 'build.py');
try { await fs.access(buildPy); } catch {
  console.error(`FATAL: pinned runtime checkout missing: ${buildPy}`);
  process.exit(2);
}
if (process.env.RUNTIME_REF) {
  const actualRef = (await $({stdio: 'pipe', verbose: false})`git -C ${source} rev-parse HEAD`).stdout.trim();
  if (actualRef !== process.env.RUNTIME_REF) {
    console.error(`FATAL: runtime checkout is ${actualRef}, expected ${process.env.RUNTIME_REF}`);
    process.exit(3);
  }
}
await fs.mkdir(installRoot, {recursive: true});
const runtimeDirectory = path.join(source, 'runtime');
const preinstall = path.join(process.env.RUNNER_TEMP || path.join(root, 'runtime-preinstall'));

if (process.platform === 'linux') {
  await $`sudo apt-get update -qq`;
  await $`sudo apt-get install -y -qq clang cmake make`;
  await $({cwd: runtimeDirectory})`python3 build.py build --target native --build-type release --prefix ${preinstall} -v ${version}`;
  await $({cwd: runtimeDirectory})`python3 build.py install --prefix ${installRoot}`;
} else if (process.platform === 'darwin') {
  await $({nothrow: true})`xcodebuild -version`;
  await $({nothrow: true})`xcrun --sdk macosx --show-sdk-version`;
  await $({cwd: runtimeDirectory})`python3 build.py build --target native --build-type release --prefix ${preinstall} -v ${version}`;
  await $({cwd: runtimeDirectory})`python3 build.py install --prefix ${installRoot}`;
} else if (process.platform === 'win32') {
  const msysBash = process.env.MSYS2_BASH || 'C:\\msys64\\usr\\bin\\bash.exe';
  const env = {
    ...process.env,
    PLATFORM_RUNTIME_SOURCE: runtimeDirectory,
    PLATFORM_RUNTIME_PREINSTALL: preinstall,
    PLATFORM_RUNTIME_INSTALL: installRoot,
    PLATFORM_RUNTIME_VERSION: version,
    MSYSTEM: 'CLANG64',
    MSYS2_PATH_TYPE: 'inherit',
    CHERE_INVOKING: '1',
  };
  const script = [
    'set -euo pipefail',
    'runtime_source="$(cygpath -u "$PLATFORM_RUNTIME_SOURCE")"',
    'runtime_preinstall="$(cygpath -u "$PLATFORM_RUNTIME_PREINSTALL")"',
    'runtime_install="$(cygpath -u "$PLATFORM_RUNTIME_INSTALL")"',
    'cd "$runtime_source"',
    'python3 build.py build --target windows-x86_64 --build-type release --target-toolchain /clang64 --prefix "$runtime_preinstall" -v "$PLATFORM_RUNTIME_VERSION"',
    'python3 build.py install --prefix "$runtime_install"',
  ].join('; ');
  await $({env})`${msysBash} -lc ${script}`;
} else {
  console.error(`FATAL: unsupported runtime build host: ${process.platform}/${process.arch}`);
  process.exit(5);
}

async function collectFiles(directory) {
  const files = [];
  for (const entry of await fs.readdir(directory, {withFileTypes: true})) {
    const target = path.join(directory, entry.name);
    if (entry.isDirectory()) files.push(...await collectFiles(target));
    else if (entry.isFile()) files.push(target);
  }
  return files;
}
const installedFiles = (await collectFiles(installRoot)).sort();
console.log(installedFiles.join('\n'));
const runtimeLib = installedFiles.find((file) =>
  ['libcangjie-runtime.so', 'libcangjie-runtime.dylib', 'libcangjie-runtime.dll', 'cangjie-runtime.dll'].includes(path.basename(file).toLowerCase()),
);
if (!runtimeLib) {
  console.error(`FATAL: libcangjie-runtime was not installed under ${installRoot}`);
  process.exit(6);
}
await $({nothrow: true})`file ${runtimeLib}`;

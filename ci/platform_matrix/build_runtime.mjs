#!/usr/bin/env zx
// Build the exact pinned runtime on the current host. Windows enters MSYS2
// CLANG64 only for build.py, whose Windows recipe requires POSIX make/PATH.

import fs from 'node:fs/promises';
import path from 'node:path';
import {printCommonVersions, stageBegin, toCommandPath} from './common.mjs';

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
  const actualRef = (await $({stdio: 'pipe', verbose: false})`git -C ${toCommandPath(source)} rev-parse HEAD`).stdout.trim();
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
  const shellQuote = (value) => "'" + value.replace(/'/g, "'\\''") + "'";
  const runtimeTarget = 'windows-x86_64';
  const buildType = 'release';
  const targetSeparator = runtimeTarget.lastIndexOf('-');
  const targetPlatform = runtimeTarget.slice(0, targetSeparator);
  const targetArch = runtimeTarget.slice(targetSeparator + 1);
  const configuredInstallRoot = path.join(installRoot, `${targetPlatform}_${buildType}_${targetArch}`);
  const script = [
    'set -euo pipefail',
    'export PATH=/clang64/bin:/usr/bin:$PATH',
    // build.py drives the main tree with `make cangjie-runtime`; Ninja files have no
    // such rule (round-9 root), so force the Makefiles generator (make is installed).
    "export CMAKE_GENERATOR='Unix Makefiles'",
    'command -v cmake ninja clang; cmake --version | head -1',
    `runtime_source="$(cygpath -u ${shellQuote(runtimeDirectory)})"`,
    `runtime_preinstall="$(cygpath -u ${shellQuote(installRoot)})"`,
    `runtime_install="$(cygpath -u ${shellQuote(configuredInstallRoot)})"`,
    'cd "$runtime_source"',
    `python3 build.py build --target ${runtimeTarget} --build-type ${buildType} --target-toolchain /clang64 --prefix "$runtime_preinstall" -v ${shellQuote(version)}`,
    'python3 build.py install --prefix "$runtime_install"',
  ].join('\n');
  const scriptPath = path.join(process.cwd(), 'rtbuild-msys2.sh');
  await fs.writeFile(scriptPath, `${script}\n`);
  const scriptMixedPath = scriptPath.replaceAll('\\', '/');
  const command = 'export MSYSTEM=CLANG64 MSYS2_PATH_TYPE=inherit CHERE_INVOKING=1; exec /usr/bin/bash -l ' + scriptMixedPath;
  await $`${toCommandPath(msysBash)} -c ${command}`;
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
await $({nothrow: true})`file ${toCommandPath(runtimeLib)}`;

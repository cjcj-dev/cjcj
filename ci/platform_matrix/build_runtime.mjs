#!/usr/bin/env zx
// Build the exact pinned runtime on the current host. Windows enters MSYS2
// MINGW64 only for build.py, whose Windows recipe requires POSIX make/PATH.

import fs from 'node:fs/promises';
import {readSourcePins} from '../native-llvm-inputs.mjs';
import path from 'node:path';
import {fileURLToPath} from 'node:url';
import {printCommonVersions, stageBegin, toCommandPath} from './common.mjs';
import {pickWindowsCC} from './pick_cc.mjs';
import {runMsysScript} from './windows_runtime_shell.mjs';
import {configureNativeRuntime, installNativeRuntimeDependencies, installNativeRuntimeInputs, recordNativeRuntime} from './native_runtime.mjs';

const {root} = stageBegin('runtime');
const source = process.env.RUNTIME_SOURCE || path.join(process.cwd(), 'runtime-source');
const version = process.env.RUNTIME_VERSION || readSourcePins().runtime.RUNTIME_VERSION;
process.env.RUNTIME_VERSION = version;
const buildType = process.env.RUNTIME_BUILD_TYPE || 'release';
const runtimeTarget = process.env.RUNTIME_TARGET || (process.platform === 'win32' ? 'windows-x86_64' : 'native');
const runtimeToolchain = process.env.RUNTIME_TOOLCHAIN || '';
const installRoot = path.join(root, 'runtime-install');
let artifactRoot = installRoot;
const nativePair = process.env.RUNTIME_NATIVE_PAIR === '1';
let nativeCommands;
if (nativePair) configureNativeRuntime({runtimeTarget});

if (runtimeToolchain) {
  process.env.PATH = `${path.join(runtimeToolchain, 'bin')}${path.delimiter}${process.env.PATH || ''}`;
}

await printCommonVersions();
console.log(`runtime_source=${source}\nruntime_ref=${process.env.RUNTIME_REF || 'unknown'}\nruntime_target=${runtimeTarget}`);
const buildPy = path.join(source, 'runtime', 'build.py');
try { await fs.access(buildPy); } catch {
  console.error(`FATAL: pinned runtime checkout missing: ${buildPy}`);
  process.exit(2);
}
const objectRepository=process.env.RUNTIME_GIT_REPOSITORY || source;
const actualRef = (await $({stdio: 'pipe', verbose: false})`git -C ${toCommandPath(objectRepository)} rev-parse ${process.env.RUNTIME_GIT_REPOSITORY ? process.env.RUNTIME_REF+'^{commit}' : 'HEAD'}`).stdout.trim();
if (!/^[0-9a-f]{40}$/.test(actualRef)) {
  console.error(`FATAL: runtime checkout did not resolve to a full commit SHA: ${actualRef}`);
  process.exit(3);
}
if (process.env.RUNTIME_REF) {
  if (actualRef !== process.env.RUNTIME_REF) {
    console.error(`FATAL: runtime checkout is ${actualRef}, expected ${process.env.RUNTIME_REF}`);
    process.exit(3);
  }
}
await fs.mkdir(installRoot, {recursive: true});
const runtimeDirectory = path.join(source, 'runtime');
if(nativePair&&process.platform==='linux') {
  process.env.GC_UNIT_GATE_STATUS=path.join(runtimeDirectory,'CMakebuild/gc-unit.status');
  await fs.rm(process.env.GC_UNIT_GATE_STATUS,{force:true});
}
const preinstall = path.join(process.env.RUNNER_TEMP || path.join(root, 'runtime-preinstall'));

if (process.platform === 'linux') {
  await $`sudo apt-get update -qq`;
  await $`sudo apt-get install -y -qq clang cmake make gdb coreutils`;
  if (runtimeTarget === 'windows-x86_64') {
    if (!runtimeToolchain) {
      console.error('FATAL: RUNTIME_TOOLCHAIN is required for the Windows cross target');
      process.exit(4);
    }
    const configuredInstallRoot = path.join(installRoot, `windows_${buildType}_x86_64`);
    artifactRoot = configuredInstallRoot;
    await $({cwd: runtimeDirectory})`python3 build.py build --target ${runtimeTarget} --build-type ${buildType} --target-toolchain ${runtimeToolchain} --prefix ${preinstall} -v ${version}`;
    await $({cwd: runtimeDirectory})`python3 build.py install --prefix ${configuredInstallRoot}`;
  } else if (runtimeTarget === 'native') {
    await $`npx --yes zx@8 ${toCommandPath(path.join(import.meta.dirname, 'qualify_teardown_tools.mjs'))} ${toCommandPath(path.join(root, 'logs', 'teardown-tools.log'))}`;
    await $({cwd: runtimeDirectory})`python3 build.py build --target native --build-type ${buildType} --prefix ${preinstall} -v ${version}`;
    await $({cwd: runtimeDirectory})`python3 build.py install --prefix ${installRoot}`;
  } else {
    console.error(`FATAL: unsupported Linux runtime target: ${runtimeTarget}`);
    process.exit(5);
  }
} else if (process.platform === 'darwin') {
  if (runtimeTarget !== 'native') {
    console.error(`FATAL: unsupported Darwin runtime target: ${runtimeTarget}`);
    process.exit(5);
  }
  await $({nothrow: true})`xcodebuild -version`;
  await $({nothrow: true})`xcrun --sdk macosx --show-sdk-version`;
  await $({cwd: runtimeDirectory})`python3 build.py build --target native --build-type ${buildType} --prefix ${preinstall} -v ${version}`;
  await $({cwd: runtimeDirectory})`python3 build.py install --prefix ${installRoot}`;
} else if (process.platform === 'win32') {
  const windowsCC = await pickWindowsCC(runtimeToolchain
    ? [path.join(runtimeToolchain, 'bin', 'clang.exe')] : undefined);
  if (!/[\\/]mingw64[\\/]bin[\\/]clang\.exe$/i.test(windowsCC)) {
    console.error(`FATAL: runtime requires working MINGW64/MSVCRT clang, probe selected ${windowsCC}`);
    process.exit(4);
  }
  const msysBash = process.env.MSYS2_BASH || 'C:\\msys64\\usr\\bin\\bash.exe';
  const selectedToolchain = path.dirname(path.dirname(windowsCC));
  const shellQuote = (value) => "'" + value.replace(/'/g, "'\\''") + "'";
  const targetSeparator = runtimeTarget.lastIndexOf('-');
  const targetPlatform = runtimeTarget.slice(0, targetSeparator);
  const targetArch = runtimeTarget.slice(targetSeparator + 1);
  const configuredInstallRoot = nativePair ? installRoot : path.join(installRoot, `${targetPlatform}_${buildType}_${targetArch}`);
  artifactRoot = configuredInstallRoot;
  const jobs=Number(process.env.RUNTIME_BUILD_JOBS||0);
  if(!Number.isSafeInteger(jobs)||jobs<0)throw Error('invalid RUNTIME_BUILD_JOBS');
  const evidence = path.resolve(root, 'windows-native');
  const captureScript = fileURLToPath(new URL('./windows_runtime_capture.mjs', import.meta.url));
  Object.assign(process.env, {WINDOWS_RUNTIME_EVIDENCE:evidence, WINDOWS_RUNTIME_BUILD_ROOT:path.join(runtimeDirectory,'CMakebuild'),
    WINDOWS_RUNTIME_CAPTURE_SCRIPT:captureScript, WINDOWS_RUNTIME_NODE:process.execPath, WINDOWS_RUNTIME_TOOLCHAIN:selectedToolchain});
  await fs.mkdir(evidence,{recursive:true});
  const linkerToolchain = fileURLToPath(new URL('./windows_runtime_toolchain.cmake', import.meta.url));
  const script = [
    'set -euo pipefail',
    `runtime_toolchain="$(cygpath -u ${shellQuote(selectedToolchain)})"`,
    'export PATH="$runtime_toolchain/bin:/usr/bin:$PATH"',
    // build.py drives the main tree with `make cangjie-runtime`; Ninja files have no
    // such rule (round-9 root), so force the Makefiles generator (make is installed).
    "export CMAKE_GENERATOR='Unix Makefiles'",
    // Select the official llvm-mingw linker before build.py configures CMake.
    `export CMAKE_TOOLCHAIN_FILE="$(cygpath -m ${shellQuote(linkerToolchain)})"`,
    ...(nativePair ? [`export SCCACHE_PATH="$(cygpath -m ${shellQuote(process.env.SCCACHE_PATH)})"`] : []),
    'command -v cmake ninja clang llvm-readobj; cmake --version | head -1; llvm-readobj --version',
    `runtime_source="$(cygpath -u ${shellQuote(runtimeDirectory)})"`,
    `runtime_preinstall="$(cygpath -u ${shellQuote(preinstall)})"`,
    `runtime_install="$(cygpath -u ${shellQuote(configuredInstallRoot)})"`,
    `capture_node="$(cygpath -u ${shellQuote(process.execPath)})"`,
    `capture_script="$(cygpath -u ${shellQuote(captureScript)})"`,
    'cd "$runtime_source"',
    `"$capture_node" "$capture_script" run build -- python3 build.py build${jobs?' --jobs '+jobs:''} --target ${runtimeTarget} --build-type ${buildType} --target-toolchain "$runtime_toolchain" --prefix "$runtime_preinstall" -v ${shellQuote(version)}`,
    '"$capture_node" "$capture_script" run install -- python3 build.py install --prefix "$runtime_install"',
  ].join('\n');
  const scriptFile = path.join(evidence, 'runtime-native-script.txt');
  await fs.writeFile(scriptFile, script + '\n');
  nativeCommands = [[msysBash, '--login', '-s']];
  let result;
  try {
    result = await runMsysScript(msysBash, script);
    if (result.exitCode !== 0 || result.error) throw new Error(`MSYS runtime entry failed: rc=${result.exitCode} signal=${result.signal} error=${result.error || 'none'}`);
  }
  finally {
    await fs.writeFile(path.join(evidence, 'runtime-native-command.json'), JSON.stringify({
      argv:nativeCommands[0], runtimeRef:actualRef, llvmRef:process.env.LLVM_SHA,
      rc:result?.exitCode ?? null, signal:result?.signal ?? null, error:result?.error,
      stdinFile:scriptFile, environment:{MSYSTEM:'MINGW64',MSYS2_PATH_TYPE:'inherit',CHERE_INVOKING:'1'},
      source:runtimeDirectory, install:configuredInstallRoot, buildType, version,
    }, null, 2) + '\n');
    if(nativePair)await fs.copyFile(path.join(evidence,'runtime-native-command.json'),path.join(installRoot,'runtime-native-command.json'));
  }
} else {
  console.error(`FATAL: unsupported runtime build host: ${process.platform}/${process.arch}`);
  process.exit(5);
}

if (runtimeTarget === 'windows-x86_64') {
  const runtimeExportDefinition = path.join(runtimeDirectory, 'src', 'windows_x86_64_exports.def');
  await fs.copyFile(runtimeExportDefinition, path.join(artifactRoot, 'windows_x86_64_exports.def'));
  console.log(`WINDOWS_RUNTIME_EXPORT_DEF staged_from=${runtimeExportDefinition}`);
}

if (nativePair) installNativeRuntimeDependencies({source, installRoot, buildType});

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
if (!nativePair) await fs.writeFile(path.join(artifactRoot, 'SOURCE_SHA'), `${actualRef}\n`);
console.log(`runtime_provenance=${path.join(artifactRoot, 'SOURCE_SHA')} source_ref=${actualRef}`);
await $({nothrow: true})`file ${toCommandPath(runtimeLib)}`;

if (nativePair) {
  installNativeRuntimeInputs({source, installRoot});
  await recordNativeRuntime({source, installRoot, actualRef, version, buildType, commands:nativeCommands});
}

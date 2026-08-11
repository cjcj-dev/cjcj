#!/usr/bin/env zx
// Provision the official host nightly SDK, activate the native fixed LLVM
// tuple, then attempt the O1 workspace build.

import crypto from 'node:crypto';
import fs from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';
import zlib from 'node:zlib';
import {spawnSync} from 'node:child_process';
import {parseLlvmToolsManifest} from '../llvm-tools-manifest.mjs';
import {
  persistBaseSdkProvenance,
  verifyBaseSdkProvenance,
} from '../../build/lib/release-component-provenance.mjs';
import {emitBlockedSummary, printCommonVersions, stageBegin, toCommandPath} from './common.mjs';
import {platformizeCjcToml} from './link_option.mjs';

const {root} = stageBegin('cjcj');
const toolchain = process.env.CJCJ_TOOLCHAIN || 'nightly-1.2.0-alpha.20260721165458';
const heapSize = process.env.CJ_HEAP_SIZE || '12GB';
const provisionOnly = process.platform === 'win32' && process.env.CJCJ_SDK_PROVISION_ONLY === '1';
const sdkAlreadyProvisioned = process.platform === 'win32' && process.env.CJCJ_SDK_ALREADY_PROVISIONED === '1';
let setupRc = 0;
let baseSdkRetention;

async function isDirectory(target) {
  try { return (await fs.stat(target)).isDirectory(); } catch { return false; }
}
async function isFile(target) {
  try { return (await fs.stat(target)).isFile(); } catch { return false; }
}
async function findFirst(directory, name) {
  for (const entry of await fs.readdir(directory, {withFileTypes: true})) {
    const target = path.join(directory, entry.name);
    if (entry.isFile() && entry.name.toLowerCase() === name.toLowerCase()) return target;
    if (entry.isDirectory()) {
      const found = await findFirst(target, name);
      if (found) return found;
    }
  }
  return '';
}

let home;
if (process.platform === 'win32') {
  home = process.env.USERPROFILE || process.env.HOME;
  if (!home) throw new Error('USERPROFILE is required');
  if (process.arch !== 'x64') throw new Error(`unsupported Windows architecture: ${process.arch}`);
  const cjvVersion = process.env.CJV_VERSION || 'v0.2.20';
  const tools = path.join(home, '.local', 'bin');
  const cjv = path.join(tools, 'cjv.exe');
  if (!sdkAlreadyProvisioned && !(await isFile(cjv))) {
    await fs.mkdir(tools, {recursive: true});
    const archive = path.join(process.env.RUNNER_TEMP || os.tmpdir(), 'cjv_windows_amd64.zip');
    const extract = path.join(process.env.RUNNER_TEMP || os.tmpdir(), 'cjv-windows');
    const url = `https://github.com/Zxilly/cjv/releases/download/${cjvVersion}/cjv_windows_amd64.zip`;
    console.log(`[platform setup_sdk] install cjv ${cjvVersion} from ${url}`);
    const response = await fetch(url);
    if (!response.ok) throw new Error(`cjv download failed: HTTP ${response.status}`);
    await fs.writeFile(archive, Buffer.from(await response.arrayBuffer()));
    await fs.rm(extract, {recursive: true, force: true});
    const archiveCommandPath = toCommandPath(archive).replaceAll("'", "''");
    const extractCommandPath = toCommandPath(extract).replaceAll("'", "''");
    await $`pwsh -NoLogo -NoProfile -Command ${`Expand-Archive -LiteralPath '${archiveCommandPath}' -DestinationPath '${extractCommandPath}' -Force`}`;
    const downloaded = await findFirst(extract, 'cjv.exe');
    if (!downloaded) throw new Error(`cjv.exe missing from ${archive}`);
    await fs.copyFile(downloaded, cjv);
  }
  if (!sdkAlreadyProvisioned) {
    process.env.PATH = `${tools};${process.env.PATH || ''}`;
    if (process.env.GITCODE_API_KEY) {
      await $({nothrow: true, stdio: 'pipe', verbose: false})`${toCommandPath(cjv)} set gitcode-api-key ${process.env.GITCODE_API_KEY}`;
      console.log('[platform setup_sdk] gitcode-api-key set');
    }
    const baseSdkArchive = process.env.BASE_SDK_ARCHIVE || '';
    const baseSdkProvenance = process.env.BASE_SDK_PROVENANCE || '';
    const releasePlatform = process.env.RELEASE_PLATFORM || '';
    let install;
    if (baseSdkArchive || baseSdkProvenance || releasePlatform) {
      if (!baseSdkArchive || !baseSdkProvenance || !releasePlatform) {
        throw new Error('BASE_SDK_ARCHIVE, BASE_SDK_PROVENANCE and RELEASE_PLATFORM must be supplied together');
      }
      const provenance = await verifyBaseSdkProvenance({
        archive: baseSdkArchive,
        sidecar: baseSdkProvenance,
        platform: releasePlatform,
        toolchain,
      });
      baseSdkRetention = {archive: baseSdkArchive, sidecar: baseSdkProvenance, platform: releasePlatform};
      console.log(`[platform setup_sdk] cjv toolchain link ${toolchain} ${baseSdkArchive} --force --sha256 ${provenance.artifact.sha256}`);
      install = await $({nothrow: true})`${toCommandPath(cjv)} toolchain link ${toolchain} ${toCommandPath(baseSdkArchive)} --force --sha256 ${provenance.artifact.sha256}`;
      if (install.exitCode === 0) {
        console.log(`[platform setup_sdk] cjv component add stdx --toolchain ${toolchain}`);
        install = await $({nothrow: true})`${toCommandPath(cjv)} component add stdx --toolchain ${toolchain}`;
      }
    } else {
      console.log(`[platform setup_sdk] cjv install ${toolchain} -c stdx`);
      install = await $({nothrow: true})`${toCommandPath(cjv)} install ${toolchain} -c stdx`;
    }
    setupRc = install.exitCode;
  }
} else {
  home = process.env.HOME;
  if (!home) throw new Error('HOME is required');
  const setup = await $({nothrow: true, env: {...process.env, CI: '', FIXED_LLC_GZ: ''}})`npx --yes zx@8 ci/setup_sdk.mjs`;
  setupRc = setup.exitCode;
}

const cangjieHome = path.join(home, '.cjv', 'toolchains', toolchain);
const stdxPath = path.join(home, '.cjv', 'stdx', toolchain, 'static', 'stdx');
if (setupRc === 0 && !(await isDirectory(cangjieHome))) throw new Error(`toolchain directory missing: ${cangjieHome}`);
if (setupRc === 0 && baseSdkRetention) {
  const retained = await persistBaseSdkProvenance({
    ...baseSdkRetention,
    toolchainDir: cangjieHome,
    toolchain,
  });
  console.log(`[platform setup_sdk] base SDK provenance retained: sidecar=${retained.sidecar} archive=${retained.cachedArchive}`);
}
process.env.CANGJIE_HOME = cangjieHome;
process.env.CANGJIE_STDX_PATH = stdxPath;
process.env.cjHeapSize = heapSize;
const pathEntries = [path.join(cangjieHome, 'bin'), path.join(cangjieHome, 'tools', 'bin')];
if (process.platform === 'win32') {
  pathEntries.push(path.join(cangjieHome, 'runtime', 'lib', 'windows_x86_64_cjnative'), path.join(cangjieHome, 'tools', 'lib'), path.join(home, '.local', 'bin'));
  process.env.PATH = `${pathEntries.join(';')};${process.env.PATH || ''}`;
  if (process.env.GITHUB_ENV) {
    await fs.appendFile(process.env.GITHUB_ENV, `CANGJIE_HOME=${cangjieHome}\nCANGJIE_STDX_PATH=${stdxPath}\ncjHeapSize=${heapSize}\nPATH=${process.env.PATH}\n`);
    if (!process.env.GITHUB_PATH) throw new Error('GITHUB_PATH is required when GITHUB_ENV is set');
    await fs.appendFile(process.env.GITHUB_PATH, `${pathEntries.join('\n')}\n`);
  }
  console.log(`[platform setup_sdk] CANGJIE_HOME=${cangjieHome}`);
} else {
  pathEntries.push(path.join(home, '.local', 'bin'));
  process.env.PATH = `${pathEntries.join(':')}:${process.env.PATH || ''}`;
  const libraryPath = `${path.join(cangjieHome, 'third_party', 'llvm', 'lib')}:${path.join(cangjieHome, 'runtime', 'lib', process.env.SDK_RUNTIME_DIR || '')}:${path.join(cangjieHome, 'tools', 'lib')}`;
  if (process.platform === 'darwin') {
    const sdkRoot = (await $({stdio: 'pipe', verbose: false})`xcrun --sdk macosx --show-sdk-path`).stdout.trim();
    if (!sdkRoot) throw new Error('xcrun returned an empty macOS SDK path');
    process.env.SDKROOT = sdkRoot;
    console.log(`[platform setup_sdk] SDKROOT=${sdkRoot}`);
    process.env.DYLD_LIBRARY_PATH = libraryPath;
    await $({nothrow: true})`xattr -dr com.apple.quarantine ${cangjieHome}`;
  } else process.env.LD_LIBRARY_PATH = libraryPath;
}
if (setupRc !== 0) process.exit(setupRc);
if (process.platform === 'win32') {
  const installedCjc = path.join(cangjieHome, 'bin', 'cjc.exe');
  const baseFile = await $({nothrow: true, stdio: 'pipe'})`file ${toCommandPath(installedCjc)}`;
  const baseLinked = await $({nothrow: true, stdio: 'pipe'})`objdump -p ${toCommandPath(installedCjc)}`;
  const baseVersion = await $({nothrow: true, stdio: 'pipe'})`${toCommandPath(installedCjc)} --version`;
  if (baseFile.exitCode !== 0 || baseLinked.exitCode !== 0 || baseVersion.exitCode !== 0) {
    throw new Error(`installed base SDK failed file/objdump/--version verification: file=${baseFile.exitCode} linked=${baseLinked.exitCode} version=${baseVersion.exitCode}`);
  }
  console.log(`[platform setup_sdk] base cjc file: ${baseFile.stdout.trim()}`);
  console.log('[platform setup_sdk] base cjc PE dependency table: readable');
  console.log(`[platform setup_sdk] base cjc version:\n${baseVersion.stdout.trim()}`);
}
if (provisionOnly) {
  console.log(`[platform setup_sdk] provisioned Windows SDK at ${cangjieHome}`);
  process.exit(0);
}

const fixedLlcGz = process.env.FIXED_LLC_GZ || '';
const fixedOptGz = process.env.FIXED_OPT_GZ || '';
const fixedLldGz = process.env.FIXED_LLD_GZ || '';
const fixedLlvmManifest = process.env.FIXED_LLVM_MANIFEST || '';
if (!(await isFile(path.join('runtime_shim', 'cjselfhost_llvmshim.o'))) ||
    !(await isFile(fixedLlcGz)) || !(await isFile(fixedOptGz)) || !(await isFile(fixedLldGz)) ||
    !(await isFile(fixedLlvmManifest))) {
  emitBlockedSummary('no complete per-OS/arch fixed LLVM tuple (needs llc + opt + native LLD + manifest + source-built shim)');
  process.exit(78);
}

async function sdkToolPath(name) {
  let target = path.join(cangjieHome, 'third_party', 'llvm', 'bin', name);
  if (!(await isFile(target)) && await isFile(`${target}.exe`)) target = `${target}.exe`;
  if (!(await isFile(target))) throw new Error(`SDK ${name} missing: ${target}`);
  return target;
}
function sha256(buffer) {
  return crypto.createHash('sha256').update(buffer).digest('hex');
}

const parsedManifest = parseLlvmToolsManifest(await fs.readFile(fixedLlvmManifest, 'utf8'), {
  label: fixedLlvmManifest,
  schema: 'core-or-native',
});
const manifest = parsedManifest.values;
if (parsedManifest.schema !== 'core-lineage') {
  throw new Error(`fixed LLVM tuple requires core-lineage manifest, got ${parsedManifest.schema}`);
}
const llvmSourceSha = manifest.get('LLVM_SHA') || '';
const pinText = await fs.readFile(path.join('ci', 'llvm_pin.env'), 'utf8');
const pinnedLlvmSha = pinText.match(/^LLVM_SHA=([0-9a-f]{40})$/m)?.[1] || '';
if (llvmSourceSha !== pinnedLlvmSha) {
  throw new Error(`fixed LLVM source mismatch (manifest=${llvmSourceSha}, pin=${pinnedLlvmSha})`);
}
const expectedLldTool = process.platform === 'darwin' ? 'ld64.lld' : 'ld.lld';
if (manifest.get('LLD_TOOL') !== expectedLldTool) {
  throw new Error(`fixed LLVM LLD tool mismatch (manifest=${manifest.get('LLD_TOOL') || ''}, expected=${expectedLldTool})`);
}
const fixedTools = [
  {name: 'llc', archive: fixedLlcGz, manifestKey: 'LLC_SHA256', versionKey: 'LLC_VERSION'},
  {name: 'opt', archive: fixedOptGz, manifestKey: 'OPT_SHA256', versionKey: 'OPT_VERSION'},
  {name: expectedLldTool, archive: fixedLldGz, manifestKey: 'LLD_SHA256', versionKey: 'LLD_VERSION'},
];
for (const tool of fixedTools) {
  tool.sdk = await sdkToolPath(tool.name);
  tool.expectedSha = manifest.get(tool.manifestKey) || '';
  if (!/^[0-9a-f]{64}$/.test(tool.expectedSha)) {
    throw new Error(`${tool.manifestKey} missing from fixed LLVM manifest`);
  }
  tool.payload = zlib.gunzipSync(await fs.readFile(tool.archive));
  const artifactSha = sha256(tool.payload);
  if (artifactSha !== tool.expectedSha) {
    throw new Error(`fixed ${tool.name} artifact sha mismatch (${artifactSha})`);
  }
  // Windows refuses to execute a PE without an .exe suffix (round-12: exit
  // 127 on `llc.exe.tuple --version`), so keep tuple temp names ending in .exe.
  tool.tuple = process.platform === 'win32'
    ? `${tool.sdk.replace(/\.exe$/i, '')}.tuple.exe`
    : `${tool.sdk}.tuple`;
  tool.rollback = `${tool.sdk}.tuple.rollback`;
  await fs.writeFile(tool.tuple, tool.payload);
  if (process.platform !== 'win32') await fs.chmod(tool.tuple, 0o755);
}

// The Windows tuple llc links against MinGW runtime DLLs (libstdc++-6.dll,
// libwinpthread-1.dll; round-13/14 exit 127 = loader failure even with PATH
// appended). Same-directory DLL resolution always wins on Windows, so copy the
// runtime DLLs next to the tools; probe via spawnSync for a discriminating error.
if (process.platform === 'win32') {
  process.env.PATH = `${process.env.PATH};C:\\mingw64\\bin`;
  const llvmBin = path.dirname(fixedTools[0].sdk);
  for (const dll of ['libstdc++-6.dll', 'libwinpthread-1.dll', 'libgcc_s_seh-1.dll']) {
    for (const dir of ['C:\\mingw64\\bin', 'C:\\msys64\\mingw64\\bin', 'C:\\Program Files\\Git\\mingw64\\bin']) {
      const cand = path.join(dir, dll);
      if (await isFile(cand)) {
        await fs.copyFile(cand, path.join(llvmBin, dll));
        console.log(`staged ${dll} from ${dir}`);
        break;
      }
    }
  }
}

function probeLlvmTool(tool, phase, expectedVersion) {
  const probe = spawnSync(tool, ['--version'], {encoding: 'utf8'});
  console.log(`${phase} ${path.basename(tool)} probe: status=${probe.status} error=${probe.error ? probe.error.code : 'none'}`);
  if (probe.stdout) console.log(probe.stdout.slice(0, 400));
  if (probe.stderr) console.error(probe.stderr.slice(0, 400));
  if (probe.status !== 0) throw new Error(`${phase} LLVM tool probe failed: ${tool}`);
  const reportedVersion = probe.stdout.split(/\r?\n/).map(line => line.trim())
    .find(line => /LLVM version |^LLD /.test(line)) || '';
  if (reportedVersion !== expectedVersion) {
    throw new Error(`${phase} LLVM tool version mismatch: ${tool} (${reportedVersion} != ${expectedVersion})`);
  }
}

// Validate the complete tuple before changing any SDK binary.
for (const tool of fixedTools) probeLlvmTool(tool.tuple, 'tuple', manifest.get(tool.versionKey));

for (const tool of fixedTools) {
  if (!(await isFile(`${tool.sdk}.orig`))) await fs.copyFile(tool.sdk, `${tool.sdk}.orig`);
  await fs.rm(tool.rollback, {force: true});
  await fs.copyFile(tool.sdk, tool.rollback);
}
try {
  for (const tool of fixedTools) {
    await fs.rm(tool.sdk, {force: true});
    await fs.rename(tool.tuple, tool.sdk);
  }
  for (const tool of fixedTools) {
    const installedSha = sha256(await fs.readFile(tool.sdk));
    if (installedSha !== tool.expectedSha) {
      throw new Error(`installed ${tool.name} sha mismatch (${installedSha})`);
    }
    probeLlvmTool(tool.sdk, 'installed', manifest.get(tool.versionKey));
    console.log(`SDK ${tool.name} -> source-built fixed LLVM (${installedSha})`);
  }
} catch (error) {
  for (const tool of fixedTools) {
    if (await isFile(tool.rollback)) {
      await fs.rm(tool.sdk, {force: true});
      await fs.rename(tool.rollback, tool.sdk);
    }
  }
  throw error;
}
for (const tool of fixedTools) await fs.rm(tool.rollback, {force: true});
console.log(`activated fixed LLVM tuple ${process.env.PLATFORM_TUPLE || 'unknown'} at ${llvmSourceSha}: llc + opt + ${expectedLldTool}`);

async function findNamedFile(directory, names) {
  const wanted = new Set(names.map((n) => n.toLowerCase()));
  let entries;
  try { entries = await fs.readdir(directory, {withFileTypes: true}); } catch { return ''; }
  for (const entry of entries) {
    const target = path.join(directory, entry.name);
    if (entry.isFile() && wanted.has(entry.name.toLowerCase())) return target;
    if (entry.isDirectory()) {
      const found = await findNamedFile(target, names);
      if (found) return found;
    }
  }
  return '';
}
async function installFile(source, destination) {
  await fs.copyFile(source, `${destination}.new`);
  if (process.platform !== 'win32') await fs.chmod(`${destination}.new`, 0o755);
  await fs.rename(`${destination}.new`, destination);
}
const sdkRuntimeDirName = process.env.SDK_RUNTIME_DIR || {
  'linux/x64': 'linux_x86_64_cjnative',
  'linux/arm64': 'linux_aarch64_cjnative',
  'darwin/arm64': 'darwin_aarch64_cjnative',
  'darwin/x64': 'darwin_x86_64_cjnative',
  'win32/x64': 'windows_x86_64_cjnative',
}[`${process.platform}/${process.arch}`] || '';
if (!sdkRuntimeDirName) throw new Error(`unsupported host for bootstrap runtime install: ${process.platform}/${process.arch}`);
const sdkRuntimeDir = path.join(cangjieHome, 'runtime', 'lib', sdkRuntimeDirName);
if (!(await isDirectory(sdkRuntimeDir))) throw new Error(`SDK runtime dir missing: ${sdkRuntimeDir}`);
const runtimeLibNames = process.platform === 'darwin'
  ? ['libcangjie-runtime.dylib']
  : process.platform === 'win32'
    ? ['libcangjie-runtime.dll', 'cangjie-runtime.dll']
    : ['libcangjie-runtime.so'];
// platform-matrix: .platform-ci/runtime-install (native or windows_release_*)
// release package: dist-runtime (build_patched_runtime.mjs) before bootstrap link
const runtimeSearchRoots = [
  path.join(root, 'runtime-install'),
  path.resolve('dist-runtime'),
  process.env.BOOTSTRAP_RUNTIME_DIR || '',
].filter(Boolean);
let builtRuntimeLib = '';
let runtimeSearchUsed = '';
for (const searchRoot of runtimeSearchRoots) {
  if (!(await isDirectory(searchRoot))) continue;
  const found = await findNamedFile(searchRoot, runtimeLibNames);
  if (found) {
    builtRuntimeLib = found;
    runtimeSearchUsed = searchRoot;
    break;
  }
}
if (!builtRuntimeLib) {
  throw new Error(
    `pinned runtime library missing under ${runtimeSearchRoots.join(' | ')} (need ${runtimeLibNames.join('|')})`,
  );
}
console.log(`bootstrap runtime source=${builtRuntimeLib} search=${runtimeSearchUsed}`);
const installedRuntimeLib = path.join(sdkRuntimeDir, path.basename(builtRuntimeLib));
await installFile(builtRuntimeLib, installedRuntimeLib);
// Windows PE link consumes -l:libcangjie-runtime.dll from this directory; the
// cross-build also stages import/static side-cars and libboundscheck next to
// the DLL. Mirror the whole host runtime lib dir so the bootstrap link matches
// the product install (see run_smoke.mjs combined Windows path).
if (process.platform === 'win32') {
  const builtRuntimeDir = path.dirname(builtRuntimeLib);
  for (const entry of await fs.readdir(builtRuntimeDir)) {
    const source = path.join(builtRuntimeDir, entry);
    if (!(await isFile(source))) continue;
    const destination = path.join(sdkRuntimeDir, entry);
    if (path.resolve(source) === path.resolve(installedRuntimeLib)) continue;
    await installFile(source, destination);
    console.log(`bootstrap runtime staged ${entry} -> ${destination}`);
  }
  const installRoot = path.resolve(builtRuntimeDir, '..', '..', '..');
  const libSide = path.join(installRoot, 'lib', sdkRuntimeDirName);
  const sdkLibDir = path.join(cangjieHome, 'lib', sdkRuntimeDirName);
  if (await isDirectory(libSide) && await isDirectory(sdkLibDir)) {
    for (const entry of await fs.readdir(libSide)) {
      const source = path.join(libSide, entry);
      if (!(await isFile(source))) continue;
      const destination = path.join(sdkLibDir, entry);
      await installFile(source, destination);
      console.log(`bootstrap lib staged ${entry} -> ${destination}`);
    }
  }
}
console.log(`bootstrap runtime installed: ${installedRuntimeLib}`);

await printCommonVersions();
console.log(`sdk_toolchain=${toolchain}\nsdk_archive=${process.env.SDK_ARCHIVE || 'unknown'}\nsdk_home=${cangjieHome}\noptimization=O1\nsetup_rc=${setupRc}`);
await $({nothrow: true})`cjv --version`;
await $({nothrow: true})`cjc --version`;
await $({nothrow: true})`cjpm --version`;
await $({nothrow: true})`${toCommandPath(sdkLlc)} --version`;

const cjcTomlPath = path.join('packages', 'cjc', 'cjpm.toml');
const cjcToml = await fs.readFile(cjcTomlPath, 'utf8');

const cjpmToml = await fs.readFile('cjpm.toml', 'utf8');
await fs.writeFile(path.join(root, 'cjpm.O1.toml'), cjpmToml.replace('compile-option = "-O2"', 'compile-option = "-O1"'));
await fs.copyFile(path.join(root, 'cjpm.O1.toml'), 'cjpm.toml');

let shim;
let build;
if (process.platform === 'win32') {
  const msysBash = process.env.MSYS2_BASH || 'C:\\msys64\\usr\\bin\\bash.exe';
  const shellQuote = (value) => "'" + value.replace(/'/g, "'\\''") + "'";
  // Nested `bash -c` quoting exploded at the cygpath `$(` (round-15); write a
  // script file and exec a login shell on it, mirroring build_runtime.mjs.
  const runInMsys = async (command, tag) => {
    const lines = [
      'set -euo pipefail',
      `repo="$(cygpath -u ${shellQuote(process.cwd())})"`,
      `cangjie_home="$(cygpath -u ${shellQuote(cangjieHome)})"`,
      `stdx_path="$(cygpath -u ${shellQuote(stdxPath)})"`,
      'cd "$repo"',
      `export CANGJIE_HOME="$cangjie_home" CANGJIE_STDX_PATH="$stdx_path" cjHeapSize=${shellQuote(heapSize)}`,
      // The msys2 login profile drops USERPROFILE; cjpm needs it (round-16).
      `export USERPROFILE=${shellQuote(process.env.USERPROFILE || '')}`,
      // Evidence: what LLVM link artifacts does the Windows SDK actually ship?
      'ls "$cangjie_home/third_party/llvm/lib" 2>/dev/null | head -20 || true',
      'export PATH="$cangjie_home/bin:$cangjie_home/tools/bin:/clang64/bin:$PATH:/c/mingw64/bin"',
      command,
    ].join('\n');
    const scriptPath = path.join(process.cwd(), `cjcjbuild-${tag}.sh`);
    await fs.writeFile(scriptPath, `${lines}\n`);
    const mixed = scriptPath.replaceAll('\\', '/');
    return $({nothrow: true})`${toCommandPath(msysBash)} -c ${'export MSYSTEM=CLANG64 MSYS2_PATH_TYPE=inherit CHERE_INVOKING=1; exec /usr/bin/bash -l ' + mixed}`;
  };
  const mingwCxxLinkRsp = path.resolve(root, 'mingw-cxx-link.rsp');
  const resolveCxxRuntime = await runInMsys([
    'cxx=/mingw64/bin/clang++.exe',
    'test -x "$cxx"',
    'probe_dir=.platform-ci/mingw-cxx-probe',
    'mkdir -p "$probe_dir"',
    'trap \'rm -rf "$probe_dir"\' EXIT',
    'printf \'int main() { return 0; }\\n\' > "$probe_dir/empty.cc"',
    '"$cxx" -v -static -pthread "$probe_dir/empty.cc" -o "$probe_dir/empty.exe" > "$probe_dir/driver.log" 2>&1',
    'grep -oE -- \'(^|[[:space:]])"?-l[A-Za-z0-9_+:.,-]+"?\' "$probe_dir/driver.log" | sed -E \'s/^[[:space:]]*"?//; s/"$//\' | grep -E -- \'^-l(stdc\\+\\+|gcc|gcc_eh|pthread|msvcrt|mingwex)$\' > "$probe_dir/libraries.txt"',
    'test -s "$probe_dir/libraries.txt"',
    'for required in -lstdc++ -lgcc -lgcc_eh -lpthread -lmsvcrt -lmingwex; do',
    '  grep -Fx -- "$required" "$probe_dir/libraries.txt" >/dev/null',
    'done',
    // Whole-archive msvcrt/mingwex duplicate the SDK CRT generation and their
    // static atexit/_onexit copies call each other forever (round-16 wine
    // forensics: startup STACK_OVERFLOW with a two-frame recursion cycle), so
    // only the members resolving the needed symbols are extracted.
    'crt_extract=.platform-ci/mingw-crt64',
    'rm -rf "$crt_extract" && mkdir -p "$crt_extract"',
    // nm -A is unusable here: C:/-style paths add a drive colon that shifts
    // the field split (round-18). Parse the archive section headers instead;
    // both GNU nm ("member.o:") and llvm-nm ("lib.a(member.o):") forms parse.
    'crt_member_for() {',
    '  nm --defined-only "$1" 2>/dev/null | awk -v s="$2" \'/:[[:space:]]*$/ { line=$0; sub(/:[[:space:]]*$/, "", line); n=split(line, parts, /[()]/); m=(n>=2? parts[2] : line); next } !done && NF>=3 && $NF==s { print m; done=1 }\'',
    '}',
    `printf '%s\\n' '--start-group' > ${shellQuote(mingwCxxLinkRsp.replaceAll('\\', '/'))}`,
    'while IFS= read -r option; do',
    '  name="${option#-l}"',
    '  case "$name" in :*) filename="${name#:}" ;; *) filename="lib${name}.a" ;; esac',
    '  library="$("$cxx" -print-file-name="$filename")"',
    '  test "$library" != "$filename" && test -f "$library"',
    '  mixed="$(cygpath -m "$library")"',
    '  case "$name" in',
    '    msvcrt) MSVCRT_LIB="$library"; continue ;;',
    '    mingwex) MINGWEX_LIB="$library"; continue ;;',
    '  esac',
    `  printf '\"%s\"\\n' "$mixed" >> ${shellQuote(mingwCxxLinkRsp.replaceAll('\\', '/'))}`,
    '  printf \'MINGW_CXX_LIB %s=%s\\n\' "$option" "$mixed"',
    'done < "$probe_dir/libraries.txt"',
    'test -n "$MSVCRT_LIB" && test -n "$MINGWEX_LIB"',
    'SSP_LIB="$("$cxx" -print-file-name=libssp.a)"',
    '{ test "$SSP_LIB" != libssp.a && test -f "$SSP_LIB"; } || SSP_LIB=""',
    // gcc-16 libstdc++ pulls the C99 wide-char/errno family the SDK-era msvcrt
    // lacks (round-19), and the SDK runtime import lib (gcc --export-all leaks
    // its static CRT helpers into the DLL export table) otherwise satisfies
    // them as DLL imports the fork/UCRT runtime can never provide (round-25:
    // 0xC0000139 on __mingw_vfprintf & co). Extracted objects are always
    // position-winning, so pull each needed member — and its transitive CRT
    // closure, or the closure's own undefineds regress to DLL imports.
    'seed_syms="fstat64 __mingw_fix_fstat_finish mbsrtowcs _set_errno wctype wctob btowc wcrtomb mbrtowc wcsrtombs mbrlen __mingw_mbrtowc_cp __mingw_wcrtomb_cp __mingw_isleadbyte_cp __mingw_vfprintf __mingw_vsnprintf __ms_vsnprintf __mingw_pformat __mingw_strtod __mingw_strtof strtold __cosl_internal __stack_chk_fail"',
    'queue="$seed_syms"; seen=" "; rounds=0',
    'while [ -n "${queue// /}" ]; do',
    '  rounds=$((rounds+1)); test "$rounds" -le 12 || { echo "MINGW_CRT64_FAIL closure did not converge: $queue"; exit 1; }',
    '  next=""',
    '  for sym in $queue; do',
    '    case "$seen" in *" $sym "*) continue ;; esac',
    '    seen="$seen$sym "',
    '    member=""',
    '    for library in "$MSVCRT_LIB" "$MINGWEX_LIB" $SSP_LIB; do',
    '      member="$(crt_member_for "$library" "$sym")"',
    '      test -n "$member" && break',
    '    done',
    // No static CRT archive defines it: a system DLL, the SDK CRT generation,
    // or a grouped archive resolves it — nothing to extract.
    '    test -n "$member" || continue',
    '    test -f "$crt_extract/$member" && continue',
    '    (cd "$crt_extract" && ar x "$library" "$member")',
    // libmsvcrt.a doubles as the msvcrt.dll import library; its dll-import
    // stub members (nm type I) must stay unextracted so those symbols keep
    // resolving as ordinary msvcrt.dll imports.
    '    if nm "$crt_extract/$member" 2>/dev/null | awk \'$(NF-1)=="I"{f=1} END{exit f?0:1}\'; then',
    '      rm -f "$crt_extract/$member"',
    '      printf \'MINGW_CRT64_SKIP import stub member %s wanted for %s\\n\' "$member" "$sym"',
    '      continue',
    '    fi',
    // Never extract the atexit family: mixing its two CRT generations is the
    // round-16 infinite recursion. Leave such demands to the SDK CRT.
    // (awk consumes all input — grep -q would SIGPIPE nm under pipefail and
    // turn a hit into a 141 miss.)
    '    if nm --defined-only "$crt_extract/$member" 2>/dev/null | awk \'$NF ~ /^(atexit|_onexit|__dllonexit|_cexit)$/ {f=1} END{exit f?0:1}\'; then',
    '      rm -f "$crt_extract/$member"',
    '      printf \'MINGW_CRT64_SKIP poison member %s (atexit family) wanted for %s\\n\' "$member" "$sym"',
    '      continue',
    '    fi',
    '    printf \'MINGW_CRT64 %s<=%s:%s\\n\' "$sym" "$library" "$member"',
    '    next="$next $(nm --undefined-only "$crt_extract/$member" 2>/dev/null | awk \'{print $NF}\' | tr \'\\n\' \' \')"',
    '  done',
    '  queue="$next"',
    'done',
    // Every seed must have landed in an extracted object — a miss regresses to
    // a DLL import of a symbol the fork runtime cannot export.
    'for sym in $seed_syms; do',
    '  nm --defined-only "$crt_extract"/*.o 2>/dev/null | awk -v s="$sym" \'$NF==s{f=1} END{exit f?0:1}\' || { echo "MINGW_CRT64_FAIL seed $sym not extracted"; exit 1; }',
    'done',
    'for object in "$crt_extract"/*.o; do',
    '  test -f "$object"',
    `  printf '\"%s\"\\n' "$(cygpath -m "$object")" >> ${shellQuote(mingwCxxLinkRsp.replaceAll('\\', '/'))}`,
    'done',
    `printf '%s\\n' '--end-group' >> ${shellQuote(mingwCxxLinkRsp.replaceAll('\\', '/'))}`,
  ].join('\n'), 'cxx-libs');
  if (resolveCxxRuntime.exitCode !== 0) process.exit(resolveCxxRuntime.exitCode);
  await fs.writeFile(cjcTomlPath, platformizeCjcToml(
    cjcToml, process.platform, cangjieHome, process.env.CJCJ_LLVM_LINK_RSP || '', mingwCxxLinkRsp));
  shim = await runInMsys('npx --yes zx@8 runtime_shim/build_shim.mjs', 'shim');
  console.log(`shim_rc=${shim.exitCode}; continuing to cjpm build so the platform frontier is recorded`);
  // cjpm's up-to-date check does not cover link-option changes, so a cached
  // target keeps stale link flags (round-15: --stack never reached the link).
  // Dropping the linked product forces a fresh final link, keeping .o caches.
  await fs.rm(path.join('target', 'release', 'bin', 'cjcj.exe'), {force: true});
  await fs.rm(path.join('target', 'release', 'bin', 'cjcj::cjc.exe'), {force: true});
  build = await runInMsys('cjpm build', 'build');
} else {
  await fs.writeFile(cjcTomlPath, platformizeCjcToml(
    cjcToml, process.platform, cangjieHome, process.env.CJCJ_LLVM_LINK_RSP || ''));
  shim = await $({nothrow: true})`npx --yes zx@8 runtime_shim/build_shim.mjs`;
  console.log(`shim_rc=${shim.exitCode}; continuing to cjpm build so the platform frontier is recorded`);
  build = await $({nothrow: true})`cjpm build`;
}
console.log(`setup_rc=${setupRc} shim_rc=${shim.exitCode} build_rc=${build.exitCode}`);
if (shim.exitCode !== 0) process.exit(shim.exitCode);
process.exit(build.exitCode);

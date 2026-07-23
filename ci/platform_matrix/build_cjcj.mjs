#!/usr/bin/env zx
// Provision the official host nightly SDK, activate the native fixed LLVM
// tuple, then attempt the O1 workspace build.

import fs from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';
import zlib from 'node:zlib';
import {spawnSync} from 'node:child_process';
import {emitBlockedSummary, printCommonVersions, stageBegin, toCommandPath} from './common.mjs';
import {platformizeCjcToml} from './link_option.mjs';

const {root} = stageBegin('cjcj');
const toolchain = process.env.CJCJ_TOOLCHAIN || 'nightly-1.2.0-alpha.20260721165458';
const heapSize = process.env.CJ_HEAP_SIZE || '12GB';
let setupRc = 0;

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
  if (!(await isFile(cjv))) {
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
  process.env.PATH = `${tools};${process.env.PATH || ''}`;
  if (process.env.GITCODE_API_KEY) {
    await $({nothrow: true, stdio: 'pipe', verbose: false})`${toCommandPath(cjv)} set gitcode-api-key ${process.env.GITCODE_API_KEY}`;
    console.log('[platform setup_sdk] gitcode-api-key set');
  }
  console.log(`[platform setup_sdk] cjv install ${toolchain} -c stdx`);
  const install = await $({nothrow: true})`${toCommandPath(cjv)} install ${toolchain} -c stdx`;
  setupRc = install.exitCode;
} else {
  home = process.env.HOME;
  if (!home) throw new Error('HOME is required');
  const setup = await $({nothrow: true, env: {...process.env, CI: '', FIXED_LLC_GZ: ''}})`npx --yes zx@8 ci/setup_sdk.mjs`;
  setupRc = setup.exitCode;
}

const cangjieHome = path.join(home, '.cjv', 'toolchains', toolchain);
const stdxPath = path.join(home, '.cjv', 'stdx', toolchain, 'static', 'stdx');
if (setupRc === 0 && !(await isDirectory(cangjieHome))) throw new Error(`toolchain directory missing: ${cangjieHome}`);
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
  const llvmBin = path.join(cangjieHome, 'third_party', 'llvm', 'bin');
  const sdkLd = path.join(llvmBin, 'ld.lld.exe');
  const realLd = path.join(llvmBin, 'ld.lld-real.exe');
  // Build the wrapper inside llvmBin so the final rename onto ld.lld.exe stays
  // on one volume (RUNNER_TEMP is D:, the SDK lives on C: — rename = EXDEV).
  const wrapper = path.join(llvmBin, 'ld.lld-wrap.exe');
  const wrapperSource = path.join(import.meta.dirname, 'lldwrap.c');
  const gcc = 'C:\\msys64\\mingw64\\bin\\gcc.exe';
  if (!(await isFile(realLd)) && !(await isFile(sdkLd))) throw new Error(`SDK ld.lld missing: ${sdkLd}`);
  if (!(await isFile(wrapperSource))) throw new Error(`ld.lld wrapper source missing: ${wrapperSource}`);
  await $`${toCommandPath(gcc)} -std=c11 -O2 -Wall -Wextra ${toCommandPath(wrapperSource)} -o ${toCommandPath(wrapper)}`;
  if (!(await isFile(wrapper))) throw new Error(`ld.lld wrapper compile produced no executable: ${wrapper}`);
  if (!(await isFile(realLd))) await fs.rename(sdkLd, realLd);
  if (!(await isFile(realLd))) throw new Error(`real SDK linker missing after rename: ${realLd}`);
  await fs.rm(sdkLd, {force: true});
  await fs.rename(wrapper, sdkLd);
  const probe = spawnSync(sdkLd, ['--version'], {encoding: 'utf8'});
  console.log(`ld.lld wrapper probe: status=${probe.status} real=${realLd}`);
  if (probe.stdout) console.log(probe.stdout.slice(0, 200));
  if (probe.stderr) console.error(probe.stderr.slice(0, 400));
  if (probe.status !== 0) throw new Error(`ld.lld wrapper --version failed: status=${probe.status} error=${probe.error?.code || 'none'}`);
}

const fixedLlcGz = process.env.FIXED_LLC_GZ || '';
if (!(await isFile(path.join('runtime_shim', 'cjselfhost_llvmshim.o'))) || !(await isFile(fixedLlcGz))) {
  emitBlockedSummary('no per-OS/arch fixed LLVM tuple (needs llc + source-built shim)');
  process.exit(78);
}

let sdkLlc = path.join(cangjieHome, 'third_party', 'llvm', 'bin', 'llc');
if (!(await isFile(sdkLlc)) && await isFile(`${sdkLlc}.exe`)) sdkLlc = `${sdkLlc}.exe`;
if (!(await isFile(sdkLlc))) throw new Error(`SDK llc missing: ${sdkLlc}`);
// Windows refuses to execute a PE without an .exe suffix (round-12: exit 127 on
// `llc.exe.tuple --version`), so keep the temp name ending in .exe there.
const tupleLlc = process.platform === 'win32' ? `${sdkLlc.replace(/\.exe$/, '')}.tuple.exe` : `${sdkLlc}.tuple`;
await fs.writeFile(tupleLlc, zlib.gunzipSync(await fs.readFile(fixedLlcGz)));
if (process.platform !== 'win32') await fs.chmod(tupleLlc, 0o755);
// The Windows tuple llc links against MinGW runtime DLLs (libstdc++-6.dll,
// libwinpthread-1.dll; round-13/14 exit 127 = loader failure even with PATH
// appended). Same-directory DLL resolution always wins on Windows, so copy the
// runtime DLLs next to the llc; probe via spawnSync for a discriminating error.
if (process.platform === 'win32') {
  process.env.PATH = `${process.env.PATH};C:\\mingw64\\bin`;
  const llvmBin = path.dirname(sdkLlc);
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
  const probe = spawnSync(tupleLlc, ['--version'], {encoding: 'utf8'});
  console.log(`tuple llc probe: status=${probe.status} error=${probe.error ? probe.error.code : 'none'}`);
  if (probe.stdout) console.log(probe.stdout.slice(0, 200));
  if (probe.stderr) console.error(probe.stderr.slice(0, 400));
  if (probe.status !== 0) process.exit(41);
} else {
  await $`${toCommandPath(tupleLlc)} --version`;
}
if (!(await isFile(`${sdkLlc}.orig`))) await fs.copyFile(sdkLlc, `${sdkLlc}.orig`);
await fs.rm(sdkLlc, {force: true});
await fs.rename(tupleLlc, sdkLlc);
console.log(`activated fixed LLVM tuple ${process.env.PLATFORM_TUPLE || 'unknown'}: ${sdkLlc}`);

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
    // only the members defining the missing *64 symbols are extracted.
    'crt_extract=.platform-ci/mingw-crt64',
    'rm -rf "$crt_extract" && mkdir -p "$crt_extract"',
    'extract_syms() {',
    '  library="$1"; shift',
    '  for sym in "$@"; do',
    // nm -A is unusable here: C:/-style paths add a drive colon that shifts
    // the field split (round-18). Parse the archive section headers instead;
    // both GNU nm ("member.o:") and llvm-nm ("lib.a(member.o):") forms parse.
    '    member="$(nm --defined-only "$library" 2>/dev/null | awk -v s="$sym" \'/:[[:space:]]*$/ { line=$0; sub(/:[[:space:]]*$/, "", line); n=split(line, parts, /[()]/); m=(n>=2? parts[2] : line); next } !done && ($2=="T"||$2=="W") && $3==s { print m; done=1 }\')"',
    '    test -n "$member" || return 1',
    '    (cd "$crt_extract" && ar x "$library" "$member")',
    '    printf \'MINGW_CRT64 %s<=%s:%s\\n\' "$sym" "$library" "$member"',
    '  done',
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
    // gcc-16 libstdc++ pulls the C99 wide-char/errno family as dllimports the
    // SDK-era msvcrt lacks (round-19); resolve each from the new import libs,
    // member-by-member, msvcrt first then mingwex.
    'for sym in fstat64 __mingw_fix_fstat_finish mbsrtowcs _set_errno wctype wctob btowc wcrtomb mbrtowc wcsrtombs mbrlen __mingw_mbrtowc_cp __mingw_wcrtomb_cp __mingw_isleadbyte_cp; do',
    '  found=""',
    '  for library in "$MSVCRT_LIB" "$MINGWEX_LIB"; do',
    '    if extract_syms "$library" "$sym" 2>/dev/null; then found=1; break; fi',
    '  done',
    '  test -n "$found"',
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

#!/usr/bin/env zx
// Cross-platform two-sample compile/run smoke, followed by a pinned-runtime
// combination smoke when the runtime stage produced a host library.

import fs from 'node:fs/promises';
import path from 'node:path';
import {spawnSync} from 'node:child_process';
import {printCommonVersions, stageBegin, toCommandPath} from './common.mjs';

const {root} = stageBegin('test');
await printCommonVersions();
const exeSuffix = process.platform === 'win32' ? '.exe' : '';

if (process.platform === 'darwin' && !process.env.SDKROOT) {
  // The cjcj Darwin driver consumes SDKROOT for -syslibroot; without it every
  // smoke link probes / and misses libSystem.tbd (rounds 19-20). Set it before
  // the FIRST runOne — the two-sample smoke, not just the combined one.
  process.env.SDKROOT = (await $({stdio: 'pipe', verbose: false})`xcrun --sdk macosx --show-sdk-path`).stdout.trim();
  console.log(`smoke SDKROOT=${process.env.SDKROOT}`);
}

async function isFile(target) {
  try { return (await fs.stat(target)).isFile(); } catch { return false; }
}

async function findFirst(directory, predicate) {
  let entries;
  try { entries = await fs.readdir(directory, {withFileTypes: true}); } catch { return ''; }
  for (const entry of entries) {
    const target = path.join(directory, entry.name);
    if (entry.isFile() && predicate(entry.name)) return target;
    if (entry.isDirectory()) {
      const found = await findFirst(target, predicate);
      if (found) return found;
    }
  }
  return '';
}

let product = '';
const productNames = process.platform === 'win32' ? ['cjcj.exe'] : ['cjcj::cjc', 'cjcj', 'cjc'];
for (const name of productNames) {
  const candidate = path.join('target', 'release', 'bin', name);
  if (await isFile(candidate)) { product = candidate; break; }
}
if (!product) {
  product = await findFirst('target', (name) => productNames.includes(name));
}
if (!product) {
  console.error('FATAL: cjcj build product not found; cjcj stage did not reach link success');
  process.exit(2);
}

const bin = path.join(root, 'bin');
const deploy = path.join(bin, `cjcj${exeSuffix}`);
await fs.mkdir(bin, {recursive: true});
await fs.copyFile(product, deploy);
try { await fs.chmod(deploy, 0o755); } catch {}
if (process.platform === 'win32') {
  // Same-directory DLL resolution always wins on Windows (see the tuple llc
  // staging in build_cjcj.mjs); stage the runtime and MinGW DLLs next to the
  // deployed compiler so a PATH miss cannot produce a silent loader 127.
  const dllSources = [path.join(process.env.CANGJIE_HOME || '', 'runtime', 'lib', 'windows_x86_64_cjnative')];
  for (const dir of ['C:\\mingw64\\bin', 'C:\\msys64\\mingw64\\bin']) dllSources.push(dir);
  const wanted = ['libcangjie-runtime.dll', 'cangjie-runtime.dll', 'libstdc++-6.dll', 'libwinpthread-1.dll', 'libgcc_s_seh-1.dll'];
  for (const name of wanted) {
    for (const dir of dllSources) {
      const source = path.join(dir, name);
      if (await isFile(source)) {
        await fs.copyFile(source, path.join(bin, name));
        console.log(`staged ${name} from ${dir}`);
        break;
      }
    }
  }
  const imports = spawnSync('objdump', ['-p', deploy], {encoding: 'utf8', maxBuffer: 256 * 1024 * 1024});
  const importNames = [...(imports.stdout || '').matchAll(/DLL Name: (\S+)/g)].map((m) => m[1]);
  console.log(`import table: ${importNames.join(' ') || '(objdump unavailable)'}`);
  for (const name of importNames) {
    const local = await isFile(path.join(bin, name));
    const located = local ? 'staged' : (await $({nothrow: true, stdio: 'pipe', verbose: false})`where ${name}`).stdout.split(/\r?\n/).find(Boolean) || 'MISSING';
    console.log(`import ${name}: ${located}`);
  }
  // Transitive closure: the top-level table resolving proves nothing about the
  // DLLs' own imports — msys2 ldd walks the full PE dependency tree.
  // -c (not -lc): a login shell resets PATH and reports SDK DLLs as spuriously
  // "not found" (round-12 artifact).
  const ldd = spawnSync('C:\\msys64\\usr\\bin\\bash.exe', ['-c', `ldd '${toCommandPath(deploy)}'`],
    {encoding: 'utf8', env: {...process.env, MSYSTEM: 'MSYS', CHERE_INVOKING: '1'}, maxBuffer: 16 * 1024 * 1024});
  console.log(`ldd status=${ldd.status}\n${(ldd.stdout || '').trim()}\n${(ldd.stderr || '').trim()}`);
  // Raw NTSTATUS: bash flattens loader failures to 127; cmd surfaces the code.
  const rawProbe = spawnSync('cmd.exe', ['/d', '/s', '/c', `"${deploy}" --version & echo RAWEXIT=%ERRORLEVEL%`],
    {encoding: 'utf8', windowsVerbatimArguments: true});
  console.log(`cmd probe status=${rawProbe.status}\nstdout: ${(rawProbe.stdout || '').trim()}\nstderr: ${(rawProbe.stderr || '').trim()}`);
  const bashProbe = spawnSync(deploy, ['--version'], {encoding: 'utf8'});
  console.log(`direct spawn status=${bashProbe.status} error=${bashProbe.error ? bashProbe.error.code : 'none'}\nstdout: ${(bashProbe.stdout || '').trim()}\nstderr: ${(bashProbe.stderr || '').trim()}`);
}
if (process.env.CANGJIE_HOME) {
  const sourceRuntime = path.join(process.env.CANGJIE_HOME, 'runtime');
  const targetRuntime = path.join(root, 'runtime');
  try {
    await fs.access(targetRuntime);
  } catch {
    try { await fs.cp(sourceRuntime, targetRuntime, {recursive: true}); } catch (error) {
      if (error.code !== 'ENOENT') throw error;
    }
  }
}
// Round-12 forensics: the exe is healthy under cmd.exe (RAWEXIT=0) but takes
// an access violation when spawned without a console (bash/node direct spawn),
// so every Windows invocation goes through cmd.exe. The console-less crash
// itself is tracked as a runtime debt.
function runCmd(exe, args, env = process.env) {
  // /s strips exactly one outer quote pair from the /c payload, so the fully
  // quoted line needs one extra wrapping pair to survive intact.
  const line = [`"${exe}"`, ...args.map((a) => `"${a}"`)].join(' ');
  return spawnSync('cmd.exe', ['/d', '/s', '/c', `"${line}"`], {encoding: 'utf8', env, windowsVerbatimArguments: true, maxBuffer: 64 * 1024 * 1024});
}
if (process.platform === 'win32') {
  // The coroutine runtime sizes cjthread stacks from cjStackSize; the PE
  // main-thread reserve (now 64MB) does not cover them.
  process.env.cjStackSize = process.env.cjStackSize || '64MB';
  const reserve = spawnSync('objdump', ['-x', deploy], {encoding: 'utf8', maxBuffer: 256 * 1024 * 1024});
  console.log(((reserve.stdout || '').match(/SizeOfStack\w+\s+\S+/g) || ['(no stack header)']).join('\n'));
  const version = runCmd(deploy, ['--version']);
  console.log(`cjcj --version status=${version.status}\n${(version.stdout || '').trim()}`);
  if (version.status !== 0) {
    const cdb = 'C:\\Program Files (x86)\\Windows Kits\\10\\Debuggers\\x64\\cdb.exe';
    if (await isFile(cdb)) {
      const trace = spawnSync(cdb, ['-o', '-c', 'g; kb; lm; q', deploy, '--version'], {encoding: 'utf8', maxBuffer: 64 * 1024 * 1024, env: process.env});
      console.log(`cdb status=${trace.status}\n${(trace.stdout || '').slice(-8000)}\n${(trace.stderr || '').slice(-2000)}`);
    } else {
      console.log('cdb unavailable for backtrace');
    }
  }
} else {
  await $({nothrow: true})`${toCommandPath(deploy)} --version`;
}

async function runOne(name, expected, env = process.env) {
  const output = path.join(root, `${name}${exeSuffix}`);
  if (process.platform === 'win32') {
    const compile = runCmd(deploy, [path.join('ci', 'smoke', `${name}.cj`), '-o', output], env);
    if (compile.status !== 0) {
      console.error(`ERROR: ${name} compile status=${compile.status} spawn_error=${compile.error ? compile.error.code : 'none'}\n${compile.stdout}\n${compile.stderr}`);
      return false;
    }
    const ran = runCmd(output, [], env);
    if (ran.status !== 0) {
      console.error(`ERROR: ${name} run status=${ran.status}\n${ran.stdout}\n${ran.stderr}`);
      return false;
    }
    const got = (ran.stdout || '').trimEnd();
    console.log(`${name} => [${got}]`);
    if (got !== expected) {
      console.error(`ERROR: ${name} expected [${expected}], got [${got}]`);
      return false;
    }
    return true;
  }
  await $({env})`${toCommandPath(deploy)} ${toCommandPath(path.join('ci', 'smoke', `${name}.cj`))} -o ${toCommandPath(output)}`;
  const got = (await $({env, stdio: 'pipe', verbose: false})`${toCommandPath(output)}`).stdout.trimEnd();
  console.log(`${name} => [${got}]`);
  if (got !== expected) {
    console.error(`ERROR: ${name} expected [${expected}], got [${got}]`);
    return false;
  }
  return true;
}
if (!(await runOne('01_hello', 'hello from cjcj'))) process.exit(1);
if (!(await runOne('02_generics', '42 hi 7'))) process.exit(1);

const runtimeLib = await findFirst(path.join(root, 'runtime-install'), (name) =>
  ['libcangjie-runtime.so', 'libcangjie-runtime.dylib', 'libcangjie-runtime.dll', 'cangjie-runtime.dll'].includes(name.toLowerCase()),
);
if (!runtimeLib) {
  console.error('ERROR: combined runtime smoke unavailable: runtime stage produced no host library');
  process.exit(3);
}
console.log(`combined runtime smoke: ${runtimeLib}`);
const runtimeDir = path.dirname(runtimeLib);
const env = {...process.env};
if (process.platform === 'darwin') env.DYLD_LIBRARY_PATH = `${runtimeDir}:${env.DYLD_LIBRARY_PATH || ''}`;
else if (process.platform !== 'win32') env.LD_LIBRARY_PATH = `${runtimeDir}:${env.LD_LIBRARY_PATH || ''}`;
if (process.platform === 'win32') {
  // Swapping only the DLL under an SDK-import-lib-linked exe is a pairing the
  // product never ships: the SDK import lib leaks mingw CRT helpers as DLL
  // imports the UCRT-based fork can never export (R26: __mingw_vfprintf,
  // __stack_chk_fail). Install the fork runtime INTO the toolchain — import
  // lib, DLL, and static side — and relink the samples, which is the actual
  // product configuration.
  const installRoot = path.resolve(runtimeDir, '..', '..', '..');
  for (const sub of [path.join('runtime', 'lib', 'windows_x86_64_cjnative'), path.join('lib', 'windows_x86_64_cjnative')]) {
    const from = path.join(installRoot, sub);
    const to = path.join(process.env.CANGJIE_HOME || '', sub);
    if (!(await fs.stat(from).then((s) => s.isDirectory(), () => false))) continue;
    for (const entry of await fs.readdir(from)) {
      await fs.cp(path.join(from, entry), path.join(to, entry), {recursive: true, force: true});
      console.log(`combined smoke installed ${path.join(sub, entry)}`);
    }
  }
  // Diagnostic: the relinked sample's runtime imports must all exist in the
  // fork DLL — diff the tables so any gap is named, not guessed.
  // Import entries are "<vma> [<ordinal>] <hint> <name>" lines inside the DLL's
  // block; export names are the last field of "[<n>] +base[<m>] <hint> <name>"
  // lines in the [Ordinal/Name Pointer] Table.
  const dumpImports = (file, dll) => {
    const out = spawnSync('objdump', ['-p', file], {encoding: 'utf8', maxBuffer: 256 * 1024 * 1024}).stdout || '';
    const block = out.split(/DLL Name: /).find((s) => s.toLowerCase().startsWith(dll.toLowerCase()));
    if (!block) return [];
    return block.split('\n\n')[0].split('\n')
      .map((line) => /^\s*[0-9a-fA-F]+\s+(?:<none>\s+|\d+\s+)?[0-9a-fA-F]+\s+(\S+)\s*$/.exec(line))
      .filter(Boolean).map((m) => m[1]);
  };
  const dumpExports = (dll) => {
    const out = spawnSync('objdump', ['-p', dll], {encoding: 'utf8', maxBuffer: 256 * 1024 * 1024}).stdout || '';
    return new Set([...out.matchAll(/^\s*\[\s*\d+\]\s+\+base\[\s*\d+\]\s+[0-9a-fA-F]+\s+(\S+)\s*$/gm)].map((m) => m[1]));
  };
  const combinedOk = await runOne('01_hello', 'hello from cjcj', env);
  const imported = dumpImports(path.join(root, `01_hello${exeSuffix}`), 'libcangjie-runtime.dll');
  const forkExports = dumpExports(runtimeLib);
  const missingInFork = imported.filter((s) => !forkExports.has(s));
  console.log(`combined smoke export diff: hello imports=${imported.length} fork_exports=${forkExports.size}`);
  console.log(`relinked hello imports missing from the fork DLL: ${missingInFork.join(', ') || '(none)'}`);
  if (!combinedOk) process.exit(1);
} else if (!(await runOne('01_hello', 'hello from cjcj', env))) process.exit(1);

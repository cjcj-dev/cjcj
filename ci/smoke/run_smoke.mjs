#!/usr/bin/env zx
// Smoke driver: compile and run each deployed self-host compiler sample, preserving the legacy transcript and exit status.

import fs from 'node:fs/promises';
import {existsSync} from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import {spawnSync} from 'node:child_process';

const cjcj = argv._[0];
if (!cjcj) {
  console.error('[smoke] usage: run_smoke.mjs <compiler-binary> [workdir]');
  process.exit(1);
}

const here = import.meta.dirname;
const work = argv._[1] || await fs.mkdtemp(path.join(os.tmpdir(), 'cjcj-smoke-'));
const exeSuffix = process.platform === 'win32' ? '.exe' : '';
await fs.mkdir(work, {recursive: true});
try {
  await fs.access(cjcj, fs.constants.X_OK);
} catch {
  console.error(`[smoke] compiler not executable: ${cjcj}`);
  process.exit(2);
}

let pass = 0;
let fail = 0;
if (process.platform === 'win32') process.env.cjStackSize = process.env.cjStackSize || '64MB';

async function runCommand(executable, args, cwd) {
  const t0 = performance.now();
  let out;
  if (process.platform !== 'win32') {
    out = await $({cwd, nothrow: true, quiet: true})`${executable} ${args}`;
  } else {
    const line = [`"${executable}"`, ...args.map((arg) => `"${arg}"`)].join(' ');
    const result = spawnSync('cmd.exe', ['/d', '/s', '/c', `"${line}"`], {
      cwd,
      encoding: 'utf8',
      env: process.env,
      windowsVerbatimArguments: true,
      maxBuffer: 64 * 1024 * 1024,
    });
    out = {exitCode: result.status ?? 1, stdout: result.stdout || '', stderr: result.stderr || String(result.error || ''), signal: result.signal || null};
  }
  const ms = Math.round(performance.now() - t0);
  return {
    exitCode: out.exitCode ?? 1,
    stdout: out.stdout || '',
    stderr: out.stderr || '',
    signal: out.signal ?? null,
    ms,
  };
}

function reportFailure(kind, name, result) {
  const rc = result.exitCode;
  const sig = result.signal ?? 'none';
  const ms = result.ms ?? -1;
  const so = result.stdout || '';
  const se = result.stderr || '';
  console.log(`[smoke] ${kind} failed: name=${name} rc=${rc} signal=${sig} ms=${ms} stdout_bytes=${so.length} stderr_bytes=${se.length}`);
  if (so.length === 0 && se.length === 0) {
    console.log('[smoke]   (compiler stdout+stderr empty)');
  } else {
    if (so.length) {
      for (const line of so.replace(/\r\n/g, '\n').split('\n').filter((l, i, a) => i < a.length - 1 || l)) {
        console.log(`    [stdout] ${line}`);
      }
    } else {
      console.log('[smoke]   stdout: EMPTY');
    }
    if (se.length) {
      for (const line of se.replace(/\r\n/g, '\n').split('\n').filter((l, i, a) => i < a.length - 1 || l)) {
        console.log(`    [stderr] ${line}`);
      }
    } else {
      console.log('[smoke]   stderr: EMPTY');
    }
  }
}

const expect = new Map([
  ['01_hello', 'hello from cjcj'],
  ['02_generics', '42 hi 7'],
  ['03_closures', '30'],
  ['04_iface_enum', '12.560000 3'],
  ['05_ffi', '7'],
]);

function inspectPe(file) {
  const result = spawnSync('objdump', ['-p', file], {encoding: 'utf8', maxBuffer: 64 * 1024 * 1024});
  const imports = new Map();
  const exports = new Set();
  let currentImport = '';
  let inImports = false;
  let inExports = false;
  for (const line of (result.stdout || '').split(/\r?\n/)) {
    if (line.startsWith('The Import Tables')) { inImports = true; inExports = false; continue; }
    if (line.startsWith('[Ordinal/Name Pointer] Table')) { inImports = false; inExports = true; continue; }
    if (line.startsWith('The Export Tables') || line.startsWith('The Function Table')) {
      inImports = false;
      if (line.startsWith('The Function Table')) inExports = false;
      continue;
    }
    if (inImports) {
      const dll = line.match(/^\s*DLL Name:\s*(\S+)/)?.[1];
      if (dll) {
        currentImport = dll;
        if (!imports.has(dll)) imports.set(dll, []);
        continue;
      }
      const symbol = line.match(/^\s*[0-9a-f]+\s+<none>\s+[0-9a-f]+\s+(\S.*)$/i)?.[1];
      if (currentImport && symbol) imports.get(currentImport).push(symbol.trim());
    } else if (inExports) {
      const symbol = line.match(/^\s*\[\s*\d+\]\s+\+base\[\s*\d+\]\s+[0-9a-f]+\s+(\S.*)$/i)?.[1];
      if (symbol) exports.add(symbol.trim());
    }
  }
  return {status: result.status, stderr: result.stderr || '', imports, exports};
}

function resolveWindowsDll(name) {
  const result = spawnSync('where', [name], {encoding: 'utf8'});
  return (result.stdout || '').split(/\r?\n/).find(Boolean) || '';
}

function resolveOfficialWindowsDll(name) {
  const root = process.env.CJCJ_OFFICIAL_SDK_HOME;
  if (!root) return '';
  for (const directory of [
    path.join(root, 'runtime', 'lib', 'windows_x86_64_cjnative'),
    path.join(root, 'tools', 'lib'),
    path.join(root, 'bin'),
  ]) {
    const candidate = path.join(directory, name);
    if (existsSync(candidate)) return candidate;
  }
  return '';
}

function isWindowsSystemDll(file) {
  const windowsRoot = (process.env.SystemRoot || 'C:\\Windows').toLowerCase();
  return path.resolve(file).toLowerCase().startsWith(`${windowsRoot}\\`);
}

async function diagnoseWindowsMacroLoad(macroDll) {
  const ldd = spawnSync('ldd', [macroDll], {encoding: 'utf8', maxBuffer: 64 * 1024 * 1024});
  console.log(`[smoke] macro ldd status=${ldd.status ?? 'spawn-failed'}`);
  for (const line of `${ldd.stdout || ''}${ldd.stderr || ''}`.split(/\r?\n/).filter(Boolean)) {
    console.log(`[smoke]   ldd: ${line}`);
  }

  const probe = [
    'Add-Type -TypeDefinition @"',
    'using System;',
    'using System.Runtime.InteropServices;',
    'public static class CjcjNativeLoader {',
    '  [DllImport("kernel32.dll", CharSet = CharSet.Ansi, SetLastError = true)]',
    '  public static extern IntPtr LoadLibraryA(string fileName);',
    '  [DllImport("kernel32.dll", SetLastError = true)]',
    '  public static extern bool FreeLibrary(IntPtr module);',
    '}',
    '"@',
    '$module = [CjcjNativeLoader]::LoadLibraryA($args[0])',
    '$code = [Runtime.InteropServices.Marshal]::GetLastWin32Error()',
    'if ($module -eq [IntPtr]::Zero) {',
    '  $message = [ComponentModel.Win32Exception]::new($code).Message',
    '  Write-Output "LOADLIBRARYA=FAIL WIN32=$code HEX=0x$($code.ToString(\'X8\')) MESSAGE=$message"',
    '} else {',
    '  Write-Output "LOADLIBRARYA=PASS HANDLE=0x$($module.ToInt64().ToString(\'X\'))"',
    '  [void][CjcjNativeLoader]::FreeLibrary($module)',
    '}',
  ].join('\n');
  const loaded = spawnSync('pwsh', ['-NoLogo', '-NoProfile', '-Command', probe, macroDll], {
    encoding: 'utf8',
    maxBuffer: 64 * 1024 * 1024,
  });
  for (const line of `${loaded.stdout || ''}${loaded.stderr || ''}`.split(/\r?\n/).filter(Boolean)) {
    console.log(`[smoke]   loader: ${line}`);
  }

  const visited = new Set();
  let firstMissingDll = '';
  let firstMissingExport = '';
  function walk(file, depth) {
    const key = path.resolve(file).toLowerCase();
    if (visited.has(key) || visited.size >= 256) return;
    visited.add(key);
    const pe = inspectPe(file);
    console.log(`[smoke] closure node depth=${depth} file=${file} objdump=${pe.status}`);
    if (pe.status !== 0) return;
    for (const [name, symbols] of pe.imports) {
      const resolved = resolveWindowsDll(name);
      console.log(`[smoke] closure edge parent=${path.basename(file)} import=${name} resolved=${resolved || 'MISSING'}`);
      if (!resolved) {
        if (!firstMissingDll) firstMissingDll = `${path.basename(file)} -> ${name}`;
        continue;
      }
      const provider = inspectPe(resolved);
      if (symbols.length > 0 && provider.exports.size > 0) {
        const missing = symbols.filter((symbol) => !provider.exports.has(symbol));
        if (missing.length > 0) {
          console.log(`[smoke] closure missing-export consumer=${path.basename(file)} provider=${resolved} symbols=${missing.join(',')}`);
          const official = resolveOfficialWindowsDll(name);
          if (official) {
            const officialExports = inspectPe(official).exports;
            const restoredByOfficial = missing.filter((symbol) => officialExports.has(symbol));
            console.log(`[smoke] closure official-export-diff provider=${official} restored=${restoredByOfficial.join(',') || 'NONE'}`);
          }
          if (!firstMissingExport) firstMissingExport = `${path.basename(file)} -> ${name}!${missing[0]}`;
        }
      }
      if (!isWindowsSystemDll(resolved)) walk(resolved, depth + 1);
    }
  }
  walk(macroDll, 0);
  console.log(`[smoke] closure summary nodes=${visited.size} first-missing-dll=${firstMissingDll || 'NONE'} first-missing-export=${firstMissingExport || 'NONE'}`);
}

for (const [name, wanted] of expect) {
  const src = path.join(here, `${name}.cj`);
  const exe = path.join(work, `${name}${exeSuffix}`);
  const buildLog = path.join(work, `${name}.build.log`);
  const runLog = path.join(work, `${name}.run.log`);
  await Promise.all([fs.rm(exe, {force: true}), fs.rm(buildLog, {force: true}), fs.rm(runLog, {force: true})]);
  console.log(`[smoke] sample ${name}`);
  const built = await runCommand(cjcj, [src, '-o', exe]);
  await fs.writeFile(buildLog, `rc=${built.exitCode} signal=${built.signal ?? 'none'} ms=${built.ms}\n--- stdout ---\n${built.stdout}\n--- stderr ---\n${built.stderr}`);
  if (built.exitCode !== 0) {
    reportFailure('compile', name, built);
    fail++;
    continue;
  }
  const ran = await runCommand(exe, []);
  await fs.writeFile(runLog, `rc=${ran.exitCode} signal=${ran.signal ?? 'none'} ms=${ran.ms}\n--- stdout ---\n${ran.stdout}\n--- stderr ---\n${ran.stderr}`);
  // Normalize CRLF before comparing: Windows println emits \r\n, and the
  // expectations encode line structure, not the OS newline byte sequence.
  const got = ran.stdout.replace(/\r\n/g, '\n').replace(/\n$/, '');
  if (ran.exitCode !== 0) {
    reportFailure('run', name, ran);
    fail++;
  } else if (got === wanted) {
    console.log(`[smoke] passed: [${got}] ms_compile=${built.ms} ms_run=${ran.ms}`);
    pass++;
  } else {
    console.log(`[smoke] mismatch: expected [${wanted}] got [${got}] ms_compile=${built.ms} ms_run=${ran.ms}`);
    fail++;
  }
}

console.log('[smoke] sample 06_macro');
const macroBuild = path.join(work, 'macro_demo');
await fs.rm(macroBuild, {recursive: true, force: true});
await fs.cp(path.join(here, 'macro_demo'), macroBuild, {recursive: true});
let macroOk = true;
let got = '';
let result = await runCommand(cjcj, ['--compile-macro', 'def.cj'], path.join(macroBuild, 'mymacros'));
await fs.writeFile(path.join(work, 'macro.build.log'), `rc=${result.exitCode} signal=${result.signal ?? 'none'} ms=${result.ms}\n--- stdout ---\n${result.stdout}\n--- stderr ---\n${result.stderr}`);
if (result.exitCode !== 0) {
  reportFailure('compile', '06_macro/package', result);
  macroOk = false;
}
if (macroOk) {
  result = await runCommand(cjcj, ['main.cj', '--import-path', macroBuild, '-o', path.join(macroBuild, `app/app${exeSuffix}`)], path.join(macroBuild, 'app'));
  await fs.writeFile(path.join(work, 'macro.app.log'), `rc=${result.exitCode} signal=${result.signal ?? 'none'} ms=${result.ms}\n--- stdout ---\n${result.stdout}\n--- stderr ---\n${result.stderr}`);
  if (result.exitCode !== 0) {
    reportFailure('compile', '06_macro/app', result);
    if (process.platform === 'win32') {
      // Release R5: the freshly compiled macro DLL fails to dlopen with PATH
      // fully staged — name the unresolved dependency instead of guessing.
      const macroDll = path.join(macroBuild, 'mymacros', 'lib-macro_mymacros.dll');
      const present = await fs.stat(macroDll).then((s) => s.size, () => -1);
      console.log(`[smoke] macro dll size=${present}`);
      if (present > 0) {
        await diagnoseWindowsMacroLoad(macroDll);
      }
    }
    macroOk = false;
  }
}
if (macroOk) {
  result = await runCommand(path.join(macroBuild, `app/app${exeSuffix}`), []);
  await fs.writeFile(path.join(work, 'macro.run.log'), `rc=${result.exitCode} signal=${result.signal ?? 'none'} ms=${result.ms}\n--- stdout ---\n${result.stdout}\n--- stderr ---\n${result.stderr}`);
  got = result.stdout.replace(/\r\n/g, '\n').replace(/\n$/, '');
  if (result.exitCode !== 0) {
    reportFailure('run', '06_macro/app', result);
    macroOk = false;
  }
}
if (macroOk) {
  if (got === 'tick\ntick') {
    console.log(`[smoke] passed: [${got.replaceAll('\n', '\\n')}]`);
    pass++;
  } else {
    console.log(`[smoke] mismatch: expected [tick\\ntick] got [${got.replaceAll('\n', '\\n')}]`);
    fail++;
  }
} else {
  fail++;
}

console.log(`[smoke] summary: pass=${pass} fail=${fail} workdir=${work}`);
process.exitCode = fail === 0 ? 0 : 1;

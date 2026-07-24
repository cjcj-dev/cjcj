#!/usr/bin/env zx
// Smoke driver: compile and run each deployed self-host compiler sample, preserving the legacy transcript and exit status.

import fs from 'node:fs/promises';
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
  if (process.platform !== 'win32') {
    return $({cwd, nothrow: true, quiet: true})`${executable} ${args}`;
  }
  const line = [`"${executable}"`, ...args.map((arg) => `"${arg}"`)].join(' ');
  const result = spawnSync('cmd.exe', ['/d', '/s', '/c', `"${line}"`], {
    cwd,
    encoding: 'utf8',
    env: process.env,
    windowsVerbatimArguments: true,
    maxBuffer: 64 * 1024 * 1024,
  });
  return {exitCode: result.status ?? 1, stdout: result.stdout || '', stderr: result.stderr || String(result.error || '')};
}

const expect = new Map([
  ['01_hello', 'hello from cjcj'],
  ['02_generics', '42 hi 7'],
  ['03_closures', '30'],
  ['04_iface_enum', '12.560000 3'],
  ['05_ffi', '7'],
]);

async function printIndented(file) {
  const contents = await fs.readFile(file, 'utf8');
  process.stdout.write(contents.split('\n').filter((line, i, lines) => i < lines.length - 1 || line).map(line => `    ${line}\n`).join(''));
}

for (const [name, wanted] of expect) {
  const src = path.join(here, `${name}.cj`);
  const exe = path.join(work, `${name}${exeSuffix}`);
  const buildLog = path.join(work, `${name}.build.log`);
  const runLog = path.join(work, `${name}.run.log`);
  await Promise.all([fs.rm(exe, {force: true}), fs.rm(buildLog, {force: true}), fs.rm(runLog, {force: true})]);
  console.log(`[smoke] sample ${name}`);
  const built = await runCommand(cjcj, [src, '-o', exe]);
  await fs.writeFile(buildLog, built.stdout + built.stderr);
  if (built.exitCode !== 0) {
    console.log('[smoke] compile failed');
    await printIndented(buildLog);
    fail++;
    continue;
  }
  const ran = await runCommand(exe, []);
  await fs.writeFile(runLog, ran.stderr);
  const got = ran.stdout.replace(/\n$/, '');
  if (ran.exitCode !== 0) {
    console.log(`[smoke] run failed: exit ${ran.exitCode}`);
    await printIndented(runLog);
    fail++;
  } else if (got === wanted) {
    console.log(`[smoke] passed: [${got}]`);
    pass++;
  } else {
    console.log(`[smoke] mismatch: expected [${wanted}] got [${got}]`);
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
await fs.writeFile(path.join(work, 'macro.build.log'), result.stdout + result.stderr);
if (result.exitCode !== 0) {
  console.log('[smoke] macro package compile failed');
  await printIndented(path.join(work, 'macro.build.log'));
  macroOk = false;
}
if (macroOk) {
  result = await runCommand(cjcj, ['main.cj', '--import-path', path.join(macroBuild, 'mymacros'), '-o', path.join(macroBuild, `app/app${exeSuffix}`)], path.join(macroBuild, 'app'));
  await fs.writeFile(path.join(work, 'macro.app.log'), result.stdout + result.stderr);
  if (result.exitCode !== 0) {
    console.log('[smoke] macro app compile failed');
    await printIndented(path.join(work, 'macro.app.log'));
    macroOk = false;
  }
}
if (macroOk) {
  result = await runCommand(path.join(macroBuild, `app/app${exeSuffix}`), []);
  await fs.writeFile(path.join(work, 'macro.run.log'), result.stderr);
  got = result.stdout.replace(/\n$/, '');
  if (result.exitCode !== 0) {
    console.log(`[smoke] macro run failed: exit ${result.exitCode}`);
    await printIndented(path.join(work, 'macro.run.log'));
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

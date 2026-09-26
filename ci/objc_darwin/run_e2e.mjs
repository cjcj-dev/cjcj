#!/usr/bin/env node

import {spawnSync} from 'node:child_process';
import crypto from 'node:crypto';
import fsSync from 'node:fs';
import fs from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';
import {resolveProductBinary} from '../srcbuild/lib/product-binary.mjs';

export const TOKEN = 'OBJC_DARWIN_E2E_OK';
export const MARKERS = Object.freeze(['objc.lang', 'objc.internal', 'objCMsgSend']);

const repoRoot = path.resolve(import.meta.dirname, '../..');

export function officialHomeForPositiveCompile(scan) {
  return scan.toolchainRoot;
}

export function positiveCompileArgs(fixture, output) {
  return [fixture, '-o', output];
}

export function negativeCompileArgs(fixture, output, importPath) {
  return [fixture, '-o', output, '--import-path', importPath];
}

export function assertPositiveArgv(args) {
  if (args.includes('--import-path')) {
    throw new Error('positive arm must not pass --import-path');
  }
  if (args.some((arg) => String(arg).includes('objc_cpointer_fixtures'))) {
    throw new Error('positive arm must not use the declaration stub tree');
  }
  if (!args.some((arg) => String(arg).endsWith(`${path.sep}main.cj`) || String(arg).endsWith('/main.cj'))) {
    throw new Error('positive arm is missing the ObjC fixture');
  }
}

export function positiveTokenAccepted(status, stdout) {
  return status === 0 && String(stdout).includes(TOKEN);
}

export function negativeArmRejected(compileStatus, runStatus, stdout) {
  if (positiveTokenAccepted(runStatus, stdout)) {
    return {ok: false, reason: 'negative_accepted_stub'};
  }
  if (compileStatus === 0 && runStatus === 0) {
    return {ok: false, reason: 'negative_ran_without_token'};
  }
  return {ok: true, reason: 'negative_rejected'};
}

export function knownProductIssues(text) {
  const rules = [
    ['cjcj#185', /enableInteropCJMapping|targetInteropLanguage/],
    ['cjcj#206', /InsertStringConversions/],
    ['cjcj#205', /AST2CHIRNodeMap/],
    ['cjcj#167', /ObjCPointer|ObjCBlock|无显式实参/],
  ];
  return rules.filter(([, pattern]) => pattern.test(String(text))).map(([id]) => id);
}

function note(line) {
  console.log(line);
  const summary = process.env.GITHUB_STEP_SUMMARY;
  if (summary) fsSync.appendFileSync(summary, `${line}\n`);
}

function darwinModuleName(name) {
  return /^darwin_.+_cjnative$/.test(name);
}

async function walkCjo(directory) {
  const found = [];
  let entries;
  try {
    entries = await fs.readdir(directory, {withFileTypes: true});
  } catch (error) {
    if (error.code === 'ENOENT') return found;
    throw error;
  }
  for (const entry of entries) {
    const target = path.join(directory, entry.name);
    if (entry.isDirectory()) found.push(...await walkCjo(target));
    else if (entry.isFile() && entry.name.endsWith('.cjo')) found.push(target);
  }
  return found;
}

export async function scanObjcModules(toolchainRoot) {
  const modules = path.join(toolchainRoot, 'modules');
  const darwinDirs = [];
  const hits = {'objc.lang': [], 'objc.internal': [], objCMsgSend: []};
  let entries = [];
  try {
    entries = await fs.readdir(modules, {withFileTypes: true});
  } catch (error) {
    if (error.code !== 'ENOENT') throw error;
  }
  for (const entry of entries) {
    if (!entry.isDirectory() || !darwinModuleName(entry.name)) continue;
    const dir = path.join(modules, entry.name);
    darwinDirs.push(dir);
    for (const file of await walkCjo(dir)) {
      const buf = await fs.readFile(file);
      for (const marker of MARKERS) {
        if (buf.includes(Buffer.from(marker))) hits[marker].push(file);
      }
    }
  }
  const missing = MARKERS.filter((marker) => hits[marker].length === 0);
  return {ok: missing.length === 0, missing, hits, darwinDirs, toolchainRoot};
}

export async function prepareNegativeHome(officialRoot, destRoot) {
  await fs.rm(destRoot, {recursive: true, force: true});
  const scan = await scanObjcModules(officialRoot);
  for (const dir of scan.darwinDirs) {
    const rel = path.relative(officialRoot, dir);
    const target = path.join(destRoot, rel);
    await fs.cp(dir, target, {recursive: true});
    for (const file of await walkCjo(target)) {
      const buf = await fs.readFile(file);
      if (MARKERS.some((marker) => buf.includes(Buffer.from(marker)))) await fs.rm(file);
    }
  }
  const again = await scanObjcModules(destRoot);
  if (again.ok) throw new Error('negative home still exposes objc markers');
  return destRoot;
}

async function sha256(file) {
  return crypto.createHash('sha256').update(await fs.readFile(file)).digest('hex');
}

export async function prepareStubImport(repo, dest) {
  await fs.rm(dest, {recursive: true, force: true});
  await fs.mkdir(dest, {recursive: true});
  const srcDir = path.join(repo, 'scripts', 'objc_cpointer_fixtures');
  for (const name of ['lang.cj', 'internal.cj']) {
    const from = path.join(srcDir, name);
    const to = path.join(dest, name);
    await fs.copyFile(from, to);
    if (await sha256(from) !== await sha256(to)) throw new Error(`stub copy mismatch: ${name}`);
  }
  const names = (await fs.readdir(dest)).sort();
  if (names.join(',') !== 'internal.cj,lang.cj') {
    throw new Error(`stub dir is not declaration-only: ${names.join(',')}`);
  }
  return dest;
}

function ensureSdkRoot(env) {
  if (process.platform !== 'darwin' || env.SDKROOT) return env;
  const xcrun = spawnSync('xcrun', ['--sdk', 'macosx', '--show-sdk-path'], {encoding: 'utf8'});
  const sdk = (xcrun.stdout || '').trim();
  if (xcrun.status !== 0 || !sdk) throw new Error('xcrun did not return a macOS SDK path');
  note(`OBJC_E2E_ASSERT sdkroot=${sdk}`);
  return {...env, SDKROOT: sdk};
}

function withRuntimeLib(env, home) {
  if (process.platform !== 'darwin') return env;
  const dir = process.env.SDK_RUNTIME_DIR || 'darwin_aarch64_cjnative';
  const lib = path.join(home, 'runtime', 'lib', dir);
  const prev = env.DYLD_LIBRARY_PATH || '';
  return {...env, DYLD_LIBRARY_PATH: prev ? `${lib}:${prev}` : lib};
}

function run(cmd, args, env) {
  return spawnSync(cmd, args, {encoding: 'utf8', env, maxBuffer: 64 * 1024 * 1024});
}

async function resolveStage1() {
  const override = process.env.OBJC_E2E_STAGE1;
  if (override) {
    try {
      if (!(await fs.stat(override)).isFile()) throw new Error('not a file');
      return override;
    } catch {
      throw new Error(`OBJC_E2E_STAGE1 is not a file: ${override}`);
    }
  }
  return resolveProductBinary(path.join(repoRoot, 'target', 'release', 'bin'), 'objc-e2e');
}

async function runHarness(scan) {
  const fixture = path.join(repoRoot, 'ci', 'objc_darwin', 'fixture', 'main.cj');
  const stage1 = await resolveStage1();
  const work = process.env.OBJC_E2E_WORK || await fs.mkdtemp(path.join(os.tmpdir(), 'objc-e2e-'));
  const keep = process.env.OBJC_E2E_KEEP === '1' || Boolean(process.env.OBJC_E2E_WORK);
  try {
    const positiveOut = path.join(work, 'positive');
    const negativeOut = path.join(work, 'negative');
    const positiveArgs = positiveCompileArgs(fixture, positiveOut);
    assertPositiveArgv(positiveArgs);
    const positiveHome = officialHomeForPositiveCompile(scan);
    const base = ensureSdkRoot({...process.env});
    const positiveEnv = withRuntimeLib({...base, CANGJIE_HOME: positiveHome}, positiveHome);
    note(`OBJC_E2E_ASSERT positive_home=${positiveHome}`);
    note(`OBJC_E2E_ASSERT positive_argv=${JSON.stringify(positiveArgs)}`);
    const compiled = run(stage1, positiveArgs, positiveEnv);
    const compileRc = compiled.status === null ? 1 : compiled.status;
    note(`OBJC_E2E_ASSERT positive_compile_rc=${compileRc}`);
    let runStatus = 1;
    let runStdout = '';
    if (compileRc === 0) {
      const ran = run(positiveOut, [], positiveEnv);
      runStatus = ran.status === null ? 1 : ran.status;
      runStdout = ran.stdout || '';
    }
    const accepted = positiveTokenAccepted(runStatus, runStdout);
    note(`OBJC_E2E_ASSERT positive_token=${accepted}`);
    if (!accepted) {
      const issues = knownProductIssues(`${compiled.stdout || ''}\n${compiled.stderr || ''}`);
      note(`OBJC_E2E_ASSERT product_issues=${issues.join(',') || 'none'}`);
      if (compiled.stderr) process.stderr.write(compiled.stderr);
      return 1;
    }
    const negativeHome = path.join(work, 'negative-home');
    const stubDir = path.join(work, 'stub-import');
    await prepareNegativeHome(scan.toolchainRoot, negativeHome);
    await prepareStubImport(repoRoot, stubDir);
    const negativeArgs = negativeCompileArgs(fixture, negativeOut, stubDir);
    const negativeEnv = withRuntimeLib({...base, CANGJIE_HOME: negativeHome}, negativeHome);
    note(`OBJC_E2E_ASSERT negative_home=${negativeHome}`);
    note(`OBJC_E2E_ASSERT negative_argv=${JSON.stringify(negativeArgs)}`);
    const negCompiled = run(stage1, negativeArgs, negativeEnv);
    const negCompileRc = negCompiled.status === null ? 1 : negCompiled.status;
    note(`OBJC_E2E_ASSERT negative_compile_rc=${negCompileRc}`);
    let negRunStatus = 1;
    let negStdout = '';
    if (negCompileRc === 0) {
      const ran = run(negativeOut, [], negativeEnv);
      negRunStatus = ran.status === null ? 1 : ran.status;
      negStdout = ran.stdout || '';
    }
    const rejected = negativeArmRejected(negCompileRc, negRunStatus, negStdout);
    note(`OBJC_E2E_ASSERT negative_token=${positiveTokenAccepted(negRunStatus, negStdout)}`);
    note(`OBJC_E2E_ASSERT ${rejected.reason}`);
    if (!rejected.ok) return 1;
    note('OBJC_E2E_ASSERT pass');
    return 0;
  } finally {
    if (!keep) await fs.rm(work, {recursive: true, force: true});
  }
}

async function main() {
  const home = process.env.OBJC_E2E_CANGJIE_HOME || process.env.CANGJIE_HOME;
  if (!home) {
    note('OBJC_E2E_ASSERT scan_ok=false reason=CANGJIE_HOME');
    return 2;
  }
  const scan = await scanObjcModules(home);
  if (process.argv.includes('--scan-only')) {
    note(`OBJC_E2E_ASSERT scan_ok=${scan.ok} missing=${scan.missing.join(',') || 'none'}`);
    return scan.ok ? 0 : 2;
  }
  if (!scan.ok) {
    note(`OBJC_E2E_ASSERT scan_ok=false missing=${scan.missing.join(',') || 'none'}`);
    return 2;
  }
  note('OBJC_E2E_ASSERT scan_ok=true');
  return runHarness(scan);
}

const invoked = process.argv[1] && path.resolve(process.argv[1]) === path.resolve(import.meta.filename);
if (invoked) {
  main().then((code) => process.exit(code)).catch((error) => {
    console.error(error);
    process.exit(2);
  });
}

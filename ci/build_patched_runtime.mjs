#!/usr/bin/env zx
// Build the native runtime library from the pinned cjcj-dev/cangjie-runtime main commit.

import fs from 'node:fs/promises';
import crypto from 'node:crypto';
import os from 'node:os';
import path from 'node:path';
import {fileURLToPath} from 'node:url';
import {resolveRuntimeSource} from './runtime-pin.mjs';
import {fetchSource} from '../build/lib/git.mjs';

const log = (message) => console.log(`[runtime] ${message}`);
export const INITIAL_RUNTIME_FETCH_DEPTH = 200;

// This guard checks a weak source-shape floor in
// MutatorManager::TryAcquireMutatorManagementRLock. It deliberately avoids the
// introducing commit SHA: history rewrites may replace that SHA while retaining
// the current canonical spelling checked below.
export const GC_FIX_MAX_FETCH_DEPTH = 4096;
export const GC_FIX_SOURCE = 'runtime/src/Mutator/MutatorManager.h';

// Weak source-shape floor.
// Guarantees: under the current canonical spelling, the function body contains
// a mgmtWritersWaiting acquire-load and an UnlockRead token after TryLockRead.
// Does not guarantee: reachability, a shared branch, comparison or return value,
// local aliases, helper extraction, macros, or any equivalent rewrite.
// Do not expand this text matcher for newly found spellings; record such cases
// for a separate behavior-level check instead.
export function gcFixWeakSourceShapePresent(sourceText) {
  const start = sourceText.search(/bool\s+TryAcquireMutatorManagementRLock\s*\(\s*\)\s*\{/);
  if (start < 0) return false;
  const open = sourceText.indexOf('{', start);
  if (open < 0) return false;
  let depth = 0;
  let end = -1;
  for (let index = open; index < sourceText.length; index += 1) {
    const char = sourceText[index];
    if (char === '{') depth += 1;
    else if (char === '}') {
      depth -= 1;
      if (depth === 0) {
        end = index;
        break;
      }
    }
  }
  if (end < 0) return false;
  const body = sourceText.slice(open + 1, end);
  const lock = body.search(/mutatorManagementRWLock\s*\.\s*TryLockRead\s*\(\s*\)/);
  if (lock < 0) return false;
  const after = body.slice(lock);
  const recheck = after.search(/mgmtWritersWaiting\s*\.\s*load\s*\(\s*std::memory_order_acquire\s*\)/);
  if (recheck < 0) return false;
  return /mutatorManagementRWLock\s*\.\s*UnlockRead\s*\(\s*\)/.test(after.slice(recheck));
}

export async function gcFixCommit(env = process.env) {
  const pins = await resolveRuntimeSource(env);
  const floor = pins.LOADERLIFE_MIN_REF;
  if (!/^[0-9a-f]{40}$/.test(floor || '')) {
    throw new Error(`LOADERLIFE_MIN_REF must be a full 40-character commit SHA: ${floor}`);
  }
  return floor;
}

export async function verifyGcFixWeakSourceShape(work, runtimeRef = 'HEAD', env = process.env) {
  void runtimeRef;
  void env;
  const source = path.join(work, GC_FIX_SOURCE);
  let text;
  try {
    text = await fs.readFile(source, 'utf8');
  } catch (error) {
    log(`ERROR: cannot read ${GC_FIX_SOURCE}: ${error.code || error.message}`);
    throw new Error(`GC fix source missing: ${GC_FIX_SOURCE}`);
  }
  if (!gcFixWeakSourceShapePresent(text)) {
    log(`ERROR: ${GC_FIX_SOURCE} lacks the canonical weak source shape after TryLockRead`);
    throw new Error('pinned GC weak source-shape floor missing');
  }
  log(`verified: ${GC_FIX_SOURCE} matches the weak source-shape floor (not a behavior proof)`);
}

async function main() {
  $.stdio = 'inherit';

  const out = argv._[0];
  if (!out) throw new Error('usage: build_patched_runtime.mjs <out-dir>');
  const {runtimeRef, sourceUrl: srcUrl, pinRef, overrideRef} = await resolveRuntimeSource();
  const version = process.env.RUNTIME_VERSION || '1.2.0-alpha.20260619020029';
  const work = await fs.mkdtemp(path.join(os.tmpdir(), 'cjcj-runtime-'));
  const runtimeLibrary = process.platform === 'darwin' ? 'libcangjie-runtime.dylib' : 'libcangjie-runtime.so';

  try {
    log(`source ref=${runtimeRef} pin=${pinRef} override=${overrideRef || '<none>'}`);
    log(`shallow fetch fork commit ${runtimeRef}`);
    await $`git -C ${work} init -q`;
    await $`git -C ${work} remote add origin ${srcUrl}`;
    await fetchSource(srcUrl, runtimeRef, {
      cwd: work, depth: INITIAL_RUNTIME_FETCH_DEPTH, stage: 'runtime.source.fetch',
    });
    await $`git -C ${work} checkout -q FETCH_HEAD`;
    const actualRef = (await $({stdio: 'pipe'})`git -C ${work} rev-parse HEAD`).stdout.trim();
    if (actualRef !== runtimeRef) throw new Error(`runtime ref mismatch: expected ${runtimeRef}, got ${actualRef}`);

    // Source-shape guard: check the tree about to be built rather than SHA
    // ancestry of LOADERLIFE_MIN_REF.
    await verifyGcFixWeakSourceShape(work, runtimeRef);

    if (process.platform === 'darwin') {
      await $`xcodebuild -version`;
      await $`xcrun --sdk macosx --show-sdk-version`;
      const sdkRoot = (await $({stdio: 'pipe'})`xcrun --sdk macosx --show-sdk-path`).stdout.trim();
      if (!sdkRoot) throw new Error('xcrun returned an empty macOS SDK path');
      process.env.SDKROOT = sdkRoot;
      log(`SDKROOT=${sdkRoot}`);
    }

    log('build (native, release)');
    // build.py drives cmake with -S ., so retain the runtime source working directory.
    await $({cwd: `${work}/runtime`})`python3 build.py build --target native --build-type release -v ${version}`;
    const found = await $({stdio: 'pipe'})`find ${work}/runtime/output -path '*Release*' -name ${runtimeLibrary}`;
    const runtime = found.stdout.split('\n').find(Boolean);
    if (!runtime) throw new Error(`built ${runtimeLibrary} not found`);
    const runtimeStat = await fs.stat(runtime);
    if (!runtimeStat.isFile()) throw new Error(`built ${runtimeLibrary} not found`);

    await fs.mkdir(out, {recursive: true});
    const packagedRuntime = path.join(out, runtimeLibrary);
    await fs.copyFile(runtime, packagedRuntime);
    await fs.writeFile(`${out}/SOURCE_SHA`, `${runtimeRef}\n`);
    const digest = crypto.createHash('sha256').update(await fs.readFile(packagedRuntime)).digest('hex');
    await fs.writeFile(`${packagedRuntime}.sha256`, `${digest}  ${runtimeLibrary}\n`);
    log(`wrote ${packagedRuntime}`);
  } finally {
    await fs.rm(work, {recursive: true, force: true});
  }
}

const isEntryPoint = process.argv.slice(2)
  .some((argument) => !argument.startsWith('-') && path.resolve(argument) === fileURLToPath(import.meta.url));
if (isEntryPoint) {
  await main();
}

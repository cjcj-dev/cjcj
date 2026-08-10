#!/usr/bin/env zx
// Build the native runtime library from the pinned cjcj-dev/cangjie-runtime main commit.

import fs from 'node:fs/promises';
import crypto from 'node:crypto';
import os from 'node:os';
import path from 'node:path';
import {fileURLToPath} from 'node:url';
import {resolveRuntimeSource} from './runtime-pin.mjs';

const log = (message) => console.log(`[runtime] ${message}`);
export const INITIAL_RUNTIME_FETCH_DEPTH = 200;
export const GC_FIX_COMMIT = 'ff89d7a14f51de005281cdc071558837dedabe07';
// `git rev-list --count ${GC_FIX_COMMIT}..<RUNTIME_REF>` is 531 for the
// repository pin. rev-list excludes the fix itself, so the derived target
// depth includes one additional slot for the fix commit.
export const GC_FIX_DISTANCE_FROM_RUNTIME_PIN = 531;
export const GC_FIX_FETCH_DEPTH = GC_FIX_DISTANCE_FROM_RUNTIME_PIN + 1;
export const GC_FIX_DEEPEN_BY = GC_FIX_FETCH_DEPTH - INITIAL_RUNTIME_FETCH_DEPTH;

async function hasCommit(work, commit) {
  const result = await $({nothrow: true, quiet: true, stdio: 'pipe'})`
    git -C ${work} cat-file -e ${commit}^{commit}
  `;
  return result.exitCode === 0;
}

export async function verifyGcFixAncestry(work, runtimeRef = 'HEAD') {
  let fixAvailable = await hasCommit(work, GC_FIX_COMMIT);
  if (!fixAvailable) {
    log(`GC fix commit ${GC_FIX_COMMIT} is absent at fetch depth ${INITIAL_RUNTIME_FETCH_DEPTH}; `
      + `deepening by ${GC_FIX_DEEPEN_BY} to depth ${GC_FIX_FETCH_DEPTH}`);
    const deepen = await $({nothrow: true, quiet: true, stdio: 'pipe'})`
      git -C ${work} fetch --deepen ${GC_FIX_DEEPEN_BY} origin ${runtimeRef}
    `;
    if (deepen.exitCode !== 0) {
      const detail = deepen.stderr.trim().split(/\r?\n/).at(-1) || '<no git diagnostic>';
      log(`ERROR: runtime fetch apparatus failed while deepening history to depth ${GC_FIX_FETCH_DEPTH}; `
        + `git exit=${deepen.exitCode}: ${detail}`);
      throw new Error(`runtime fetch apparatus could not deepen history for GC fix ${GC_FIX_COMMIT}`);
    }
    fixAvailable = await hasCommit(work, GC_FIX_COMMIT);
  }

  if (!fixAvailable) {
    log(`ERROR: runtime fetch apparatus cannot obtain GC fix commit ${GC_FIX_COMMIT}; `
      + `history was deepened to depth ${GC_FIX_FETCH_DEPTH} but the commit is still unavailable`);
    throw new Error(`runtime fetch apparatus cannot obtain pinned GC fix commit after depth ${GC_FIX_FETCH_DEPTH}`);
  }

  const ancestry = await $({nothrow: true, quiet: true, stdio: 'pipe'})`
    git -C ${work} merge-base --is-ancestor ${GC_FIX_COMMIT} HEAD
  `;
  if (ancestry.exitCode > 1) {
    const detail = ancestry.stderr.trim().split(/\r?\n/).at(-1) || '<no git diagnostic>';
    log(`ERROR: runtime ancestry apparatus failed with git exit=${ancestry.exitCode}: ${detail}`);
    throw new Error('runtime ancestry apparatus could not evaluate the pinned GC fix');
  }
  if (ancestry.exitCode !== 0) {
    log(`ERROR: GC fix commit ${GC_FIX_COMMIT} is available, but runtime ${runtimeRef} `
      + 'does not descend from it; wrong fork commit');
    throw new Error('pinned GC fix ancestry missing');
  }
  log('verified: pinned GC fix commit is an ancestor of the selected runtime source');
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
    await $`git -C ${work} fetch --depth ${INITIAL_RUNTIME_FETCH_DEPTH} origin ${runtimeRef}`;
    await $`git -C ${work} checkout -q FETCH_HEAD`;
    const actualRef = (await $({stdio: 'pipe'})`git -C ${work} rev-parse HEAD`).stdout.trim();
    if (actualRef !== runtimeRef) throw new Error(`runtime ref mismatch: expected ${runtimeRef}, got ${actualRef}`);

    // Provenance guard: the pinned reader-admission GC fix must be an ancestor
    // of the commit about to be built. The former symbol probe
    // (LiveInfo::RecomputeBitmapLiveBytes) broke at pin 707a07a1 — it is a
    // header-inline function and newer code shapes inline its single call site,
    // so no standalone symbol survives to be found.
    // The fix commit was c2fc3745 on the pre-rebuild line; the integrate/0.0.2-gc
    // history carries the same patch (identical stable patch-id) as ff89d7a1.
    await verifyGcFixAncestry(work, runtimeRef);

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

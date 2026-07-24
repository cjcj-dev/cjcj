#!/usr/bin/env zx
// Build the native runtime library from the pinned cjcj-dev/cangjie-runtime main commit.

import fs from 'node:fs/promises';
import crypto from 'node:crypto';
import os from 'node:os';
import path from 'node:path';

$.stdio = 'inherit';

const out = argv._[0];
if (!out) throw new Error('usage: build_patched_runtime.mjs <out-dir>');
const here = import.meta.dirname;
const pinText = await fs.readFile(path.join(here, 'runtime_pin.env'), 'utf8');
const pins = Object.fromEntries(pinText.split(/\r?\n/).filter(Boolean).map((line) => {
  const separator = line.indexOf('=');
  if (separator < 1) throw new Error(`invalid runtime pin line: ${line}`);
  return [line.slice(0, separator), line.slice(separator + 1)];
}));
const runtimeRef = pins.RUNTIME_REF;
const requestedRuntimeRef = process.env.RUNTIME_REF || '';
if (requestedRuntimeRef && requestedRuntimeRef !== runtimeRef) {
  console.error(`[runtime] pin mismatch: ${requestedRuntimeRef} != ${runtimeRef}`);
  process.exit(2);
}
const version = process.env.RUNTIME_VERSION || '1.2.0-alpha.20260619020029';
const srcUrl = process.env.RUNTIME_SRC_URL || pins.RUNTIME_SRC_URL;
const log = (message) => console.log(`[runtime] ${message}`);
const work = await fs.mkdtemp(path.join(os.tmpdir(), 'cjcj-runtime-'));
const runtimeLibrary = process.platform === 'darwin' ? 'libcangjie-runtime.dylib' : 'libcangjie-runtime.so';

try {
  log(`shallow fetch fork commit ${runtimeRef}`);
  await $`git -C ${work} init -q`;
  await $`git -C ${work} remote add origin ${srcUrl}`;
  // Depth must reach the pinned GC-fix commit so the ancestry guard below can
  // resolve merge-base inside the shallow clone.
  await $`git -C ${work} fetch --depth 200 origin ${runtimeRef}`;
  await $`git -C ${work} checkout -q FETCH_HEAD`;
  const actualRef = (await $({stdio: 'pipe'})`git -C ${work} rev-parse HEAD`).stdout.trim();
  if (actualRef !== runtimeRef) throw new Error(`runtime ref mismatch: expected ${runtimeRef}, got ${actualRef}`);

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

  // Provenance guard: the pinned reader-admission GC fix must be an ancestor of
  // the commit we just built. The former symbol probe
  // (LiveInfo::RecomputeBitmapLiveBytes) broke at pin 707a07a1 — it is a
  // header-inline function and newer code shapes inline its single call site,
  // so no standalone symbol survives to be found.
  const GC_FIX_COMMIT = 'f851b846e275859aeccacd0edd42b81f28cb25bd';
  const ancestry = await $({nothrow: true})`git -C ${work} merge-base --is-ancestor ${GC_FIX_COMMIT} HEAD`;
  if (ancestry.exitCode !== 0) {
    log('ERROR: built runtime does not descend from the pinned GC fix commit; wrong fork commit');
    process.exitCode = 1;
    throw new Error('pinned GC fix ancestry missing');
  }
  log('verified: pinned GC fix commit is an ancestor of the built runtime');
} finally {
  await fs.rm(work, {recursive: true, force: true});
}

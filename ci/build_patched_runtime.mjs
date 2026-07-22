#!/usr/bin/env zx
// Build libcangjie-runtime.so from the pinned cjcj-dev/cangjie-runtime main commit.

import fs from 'node:fs/promises';
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
  console.error(`workflow/runtime pin mismatch: ${requestedRuntimeRef} != ${runtimeRef}`);
  process.exit(2);
}
const version = process.env.RUNTIME_VERSION || '1.2.0-alpha.20260619020029';
const srcUrl = process.env.RUNTIME_SRC_URL || pins.RUNTIME_SRC_URL;
const log = (message) => console.log(`[build_patched_runtime] ${message}`);
const work = await fs.mkdtemp(path.join(os.tmpdir(), 'cjcj-runtime-'));

try {
  log(`shallow fetch fork commit ${runtimeRef}`);
  await $`git -C ${work} init -q`;
  await $`git -C ${work} remote add origin ${srcUrl}`;
  await $`git -C ${work} fetch --depth 1 origin ${runtimeRef}`;
  await $`git -C ${work} checkout -q FETCH_HEAD`;
  const actualRef = (await $({stdio: 'pipe'})`git -C ${work} rev-parse HEAD`).stdout.trim();
  if (actualRef !== runtimeRef) throw new Error(`runtime ref mismatch: expected ${runtimeRef}, got ${actualRef}`);

  log('build (native, release)');
  // build.py drives cmake with -S ., so retain the runtime source working directory.
  await $({cwd: `${work}/runtime`})`python3 build.py build --target native --build-type release -v ${version}`;
  const found = await $({stdio: 'pipe'})`find ${work}/runtime/output -path '*Release*' -name libcangjie-runtime.so`;
  const so = found.stdout.split('\n').find(Boolean);
  if (!so) throw new Error('built libcangjie-runtime.so not found');
  const soStat = await fs.stat(so);
  if (!soStat.isFile()) throw new Error('built libcangjie-runtime.so not found');

  await fs.mkdir(out, {recursive: true});
  await $`cp ${so} ${out}/libcangjie-runtime.so`;
  await fs.writeFile(`${out}/SOURCE_SHA`, `${runtimeRef}\n`);
  await $({cwd: out})`sha256sum libcangjie-runtime.so > libcangjie-runtime.so.sha256`;
  log(`wrote ${out}/libcangjie-runtime.so`);

  // RecomputeBitmapLiveBytes is introduced by the pinned trace-insertion-closure
  // fix and remains a versioned dynamic symbol in native release builds. Unlike
  // .cjmetadata, this proves the required code is in libcangjie-runtime.so.
  const GC_FIX_SYMBOL = '_ZNK12MapleRuntime8LiveInfo24RecomputeBitmapLiveBytesEv@@CANGJIE';
  const symbols = await $({nothrow: true, stdio: 'pipe'})`readelf --dyn-syms --wide ${out}/libcangjie-runtime.so`;
  if (symbols.exitCode !== 0 || !symbols.stdout.includes(GC_FIX_SYMBOL)) {
    log('ERROR: built runtime lacks the pinned GC fix symbol; wrong fork commit');
    process.exitCode = 1;
    throw new Error('pinned GC fix symbol missing');
  }
  log('verified: pinned GC fix symbol present');
} finally {
  await fs.rm(work, {recursive: true, force: true});
}

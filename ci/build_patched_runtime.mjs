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

// The floor this guard enforces lives in ci/runtime_pin.env as LOADERLIFE_MIN_REF,
// which G13 also reads. It used to be duplicated here as a literal SHA together
// with a literal distance-from-the-pin, and that pair is what broke CI on
// 2026-08-15: the runtime history was rewritten on 08-12, the sha the literal
// named survives only on pre-rewrite branches, and no fetch depth can reach a
// commit that is not an ancestor. The failure read as "cannot obtain pinned GC
// fix commit after depth 532", which points at the depth and not at the sha.
//
// The content is still on main. `// Close the race between the pending-writer
// check above and TryLockRead().` sits at MutatorManager.h:130, introduced by
// 9975f4d2 — the same commit LOADERLIFE_MIN_REF already names. So there is one
// floor, and it now has one definition.
//
// Distance is measured rather than declared. A literal distance is wrong the
// moment the pin moves, and it fails in the confusing direction: the guard
// blames its own depth for a commit that was never reachable.
export const GC_FIX_MAX_FETCH_DEPTH = 4096;

export async function gcFixCommit(env = process.env) {
  const pins = await resolveRuntimeSource(env);
  const floor = pins.LOADERLIFE_MIN_REF;
  if (!/^[0-9a-f]{40}$/.test(floor || '')) {
    throw new Error(`LOADERLIFE_MIN_REF must be a full 40-character commit SHA: ${floor}`);
  }
  return floor;
}

async function hasCommit(work, commit) {
  const result = await $({nothrow: true, quiet: true, stdio: 'pipe'})`
    git -C ${work} cat-file -e ${commit}^{commit}
  `;
  return result.exitCode === 0;
}

export async function verifyGcFixAncestry(work, runtimeRef = 'HEAD', env = process.env) {
  const fixCommit = await gcFixCommit(env);
  let fixAvailable = await hasCommit(work, fixCommit);

  // Deepen in doubling rounds until the commit appears or the cap is reached.
  //
  // What is reported is how much history this function asked for, not "the depth
  // of the repository": the caller may have cloned at any depth, and claiming a
  // number we never checked is how the old message came to blame its own depth
  // for a commit that was never on the branch.
  let requested = 0;
  let step = INITIAL_RUNTIME_FETCH_DEPTH;
  while (!fixAvailable && requested < GC_FIX_MAX_FETCH_DEPTH) {
    const by = Math.min(step, GC_FIX_MAX_FETCH_DEPTH - requested);
    log(`GC fix commit ${fixCommit} not present; deepening by ${by} (asked for ${requested + by} so far)`);
    const deepen = await $({nothrow: true, quiet: true, stdio: 'pipe'})`
      git -C ${work} fetch --deepen ${by} origin ${runtimeRef}
    `;
    if (deepen.exitCode !== 0) {
      const detail = deepen.stderr.trim().split(/\r?\n/).at(-1) || '<no git diagnostic>';
      log(`ERROR: runtime fetch apparatus failed while deepening by ${by}; `
        + `git exit=${deepen.exitCode}: ${detail}`);
      throw new Error(`runtime fetch apparatus could not deepen history for GC fix ${fixCommit}`);
    }
    requested += by;
    step *= 2;
    fixAvailable = await hasCommit(work, fixCommit);
  }

  if (!fixAvailable) {
    log(`ERROR: GC fix commit ${fixCommit} is still absent after asking for ${requested} more commits. `
      + 'A commit no amount of deepening reaches is not on this branch at all — check whether the '
      + 'floor names a sha from a rewritten history (git branch -a --contains <sha>).');
    throw new Error(`pinned GC fix commit ${fixCommit} unreachable after deepening by ${requested}`);
  }

  const ancestry = await $({nothrow: true, quiet: true, stdio: 'pipe'})`
    git -C ${work} merge-base --is-ancestor ${fixCommit} HEAD
  `;
  if (ancestry.exitCode > 1) {
    const detail = ancestry.stderr.trim().split(/\r?\n/).at(-1) || '<no git diagnostic>';
    log(`ERROR: runtime ancestry apparatus failed with git exit=${ancestry.exitCode}: ${detail}`);
    throw new Error('runtime ancestry apparatus could not evaluate the pinned GC fix');
  }
  if (ancestry.exitCode !== 0) {
    log(`ERROR: GC fix commit ${fixCommit} is available, but runtime ${runtimeRef} `
      + 'does not descend from it; wrong fork commit');
    throw new Error('pinned GC fix ancestry missing');
  }
  log(`verified: pinned GC fix ${fixCommit} is an ancestor of the selected runtime source`
    + (requested > 0 ? ` (after deepening by ${requested})` : ' (already present)'));
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

    // Provenance guard: the reader-admission GC fix must be an ancestor of the
    // commit about to be built. An earlier version probed for a symbol
    // (LiveInfo::RecomputeBitmapLiveBytes), which broke at pin 707a07a1 because
    // it is header-inline and newer shapes inline its only call site.
    //
    // The fix has had several shas — c2fc3745 pre-rebuild, ff89d7a1 on
    // integrate/0.0.2-gc — and naming any of them here is what broke on
    // 2026-08-15, since the 08-12 rewrite left all of them off main. The floor
    // now comes from LOADERLIFE_MIN_REF, whose value is maintained with the pin.
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

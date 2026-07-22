#!/usr/bin/env zx
// Verify imported generic default parameters using reference-written metadata and both consumers.

import fs from 'node:fs/promises';
import path from 'node:path';
import {copy, ensureInputs, fail, fixture, invoke, makeWork, output, reference, run, selfhost} from './septest_lib.mjs';

const work = await makeWork('septest-gendefault-');
try {
  await ensureInputs('SEPTEST-GENDEFAULT', work);
  await copy('pkgGenDef/lib.cj', path.join(work, 'dep/lib.cj'));
  const dep = await invoke(reference, [path.join(work, 'dep/lib.cj'), '--output-type=staticlib', '-o', path.join(work, 'dep/libpkgGenDef.a'), '--set-runtime-rpath'], path.join(work, 'dep.stdout'), path.join(work, 'dep.stderr'));
  if (dep.exitCode !== 0) fail('SEPTEST-GENDEFAULT', `ref dep compile failed: ${dep.stderr.replaceAll('\n', ' ')}`);
  async function consumer(who, compiler) {
    const binary = path.join(work, `use_${who}`);
    const result = await invoke(compiler, [path.join(fixture, 'pkgGenDefUse/main.cj'), '--import-path', path.join(work, 'dep'), '-L', path.join(work, 'dep'), '-lpkgGenDef', '-o', binary, '--set-runtime-rpath'], path.join(work, `${who}.stdout`), path.join(work, `${who}.stderr`));
    if (result.exitCode !== 0) fail('SEPTEST-GENDEFAULT', `${who} consumer compile failed (imported generic-default-param mangle): ${result.stderr.replaceAll('\n', ' ')}`);
    const executed = await run(binary);
    if (executed.exitCode !== 0) fail('SEPTEST-GENDEFAULT', `${who} consumer run nonzero`);
    return output(executed);
  }
  const selfOut = await consumer('self', selfhost); const refOut = await consumer('ref', reference);
  if (selfOut !== refOut) fail('SEPTEST-GENDEFAULT', `selfhost '${selfOut}' != reference '${refOut}'`);
  if (selfOut !== '3') fail('SEPTEST-GENDEFAULT', `output '${selfOut}' != expected 3`);
  console.log(`SEPTEST-GENDEFAULT-PASS self=${selfOut} ref=${refOut}`);
} finally { await fs.rm(work, {recursive: true, force: true}); }

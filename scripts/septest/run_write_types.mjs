#!/usr/bin/env zx
// Verify self-host-written imported type metadata with both self-host and reference consumers.

import fs from 'node:fs/promises';
import path from 'node:path';
import {copy, ensureInputs, fail, invoke, makeWork, output, reference, run, selfhost} from './septest_lib.mjs';

const work = await makeWork('septest-write-types-');
try {
  await ensureInputs('SEPTEST-WRITE-TYPES', work); await copy('pkgA2/pkgA2.cj', path.join(work, 'pkgA2/pkgA2.cj')); await copy('pkgB2/use_types.cj', path.join(work, 'pkgB2/use_types.cj'));
  await Promise.all([fs.mkdir(path.join(work, 'self')), fs.mkdir(path.join(work, 'ref'))]);
  const dep = await invoke(selfhost, [path.join(work, 'pkgA2/pkgA2.cj'), '--output-type=staticlib', '-o', path.join(work, 'pkgA2/libpkgA2.a'), '--set-runtime-rpath']); if (dep.exitCode !== 0) fail('SEPTEST-WRITE-TYPES', `selfhost pkgA2 compile failed: ${dep.stderr.replaceAll('\n', ' ')}`);
  const cjo = await fs.readFile(path.join(work, 'pkgA2/pkgA2.cjo')); const magic = cjo.subarray(4, 8).toString(); if (magic !== 'CJOF') fail('SEPTEST-WRITE-TYPES', `selfhost pkgA2.cjo has wrong file identifier '${magic}'`);
  console.log('SEPTEST-WRITE-TYPES-PASS pkgA2 magic=CJOF');
  for (const [who, compiler] of [['self', selfhost], ['ref', reference]]) {
    const binary = path.join(work, who, 'use_types'); const built = await invoke(compiler, [path.join(work, 'pkgB2/use_types.cj'), '--import-path', path.join(work, 'pkgA2'), '-L', path.join(work, 'pkgA2'), '-lpkgA2', '-o', binary, '--set-runtime-rpath']); if (built.exitCode !== 0) fail('SEPTEST-WRITE-TYPES', `${who} pkgB2 compile failed: ${built.stderr.replaceAll('\n', ' ')}`);
    const executed = await run(binary); const value = output(executed); if (executed.exitCode !== 0) fail('SEPTEST-WRITE-TYPES', `${who} pkgB2 exited with ${executed.exitCode}`); if (value !== '61') fail('SEPTEST-WRITE-TYPES', `${who} pkgB2 output '${value}' did not match expected '61'`);
    console.log(`SEPTEST-WRITE-TYPES-PASS ${who}:use_types output=${value}`);
  }
  console.log('SEPTEST-WRITE-TYPES-PASS');
} finally { await fs.rm(work, {recursive: true, force: true}); }

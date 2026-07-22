#!/usr/bin/env zx
// Verify self-host-written struct metadata with both self-host and reference consumers.

import fs from 'node:fs/promises';
import path from 'node:path';
import {copy, ensureInputs, fail, invoke, makeWork, output, reference, run, selfhost} from './septest_lib.mjs';

const work = await makeWork('septest-write-struct-');
try {
  await ensureInputs('SEPTEST-WRITE-STRUCT', work); await copy('pkgA3/pkgA3.cj', path.join(work, 'pkgA3/pkgA3.cj')); await copy('pkgB3/use_struct.cj', path.join(work, 'pkgB3/use_struct.cj'));
  await Promise.all([fs.mkdir(path.join(work, 'self')), fs.mkdir(path.join(work, 'ref'))]);
  const dep = await invoke(selfhost, [path.join(work, 'pkgA3/pkgA3.cj'), '--output-type=staticlib', '-o', path.join(work, 'pkgA3/libpkgA3.a'), '--set-runtime-rpath'], path.join(work, 'pkgA3.self.stdout'), path.join(work, 'pkgA3.self.stderr'));
  if (dep.exitCode !== 0) fail('SEPTEST-WRITE-STRUCT', `selfhost pkgA3 compile failed: ${dep.stderr.replaceAll('\n', ' ')}`);
  const cjo = await fs.readFile(path.join(work, 'pkgA3/pkgA3.cjo')); const magic = cjo.subarray(4, 8).toString(); if (magic !== 'CJOF') fail('SEPTEST-WRITE-STRUCT', `selfhost pkgA3.cjo has wrong file identifier '${magic}'`);
  console.log('SEPTEST-WRITE-STRUCT-PASS pkgA3 magic=CJOF');
  for (const [who, compiler] of [['self', selfhost], ['ref', reference]]) {
    const binary = path.join(work, who, 'use_struct'); const built = await invoke(compiler, [path.join(work, 'pkgB3/use_struct.cj'), '--import-path', path.join(work, 'pkgA3'), '-L', path.join(work, 'pkgA3'), '-lpkgA3', '-o', binary, '--set-runtime-rpath']);
    if (built.exitCode !== 0) fail('SEPTEST-WRITE-STRUCT', `${who} pkgB3 compile failed: ${built.stderr.replaceAll('\n', ' ')}`);
    const executed = await run(binary); const value = output(executed); if (executed.exitCode !== 0) fail('SEPTEST-WRITE-STRUCT', `${who} pkgB3 exited with ${executed.exitCode}`); if (value !== '49') fail('SEPTEST-WRITE-STRUCT', `${who} pkgB3 output '${value}' did not match expected '49'`);
    console.log(`SEPTEST-WRITE-STRUCT-PASS ${who}:use_struct output=${value}`);
  }
  console.log('SEPTEST-WRITE-STRUCT-PASS');
} finally { await fs.rm(work, {recursive: true, force: true}); }

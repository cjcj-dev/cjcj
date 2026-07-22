#!/usr/bin/env zx
// Verify self-host-written package metadata for functions and values with self-host and reference consumers.

import fs from 'node:fs/promises';
import path from 'node:path';
import {copy, ensureInputs, fail, invoke, makeWork, output, reference, run, selfhost} from './septest_lib.mjs';

const work = await makeWork('septest-write-');
try {
  await ensureInputs('SEPTEST-WRITE', work);
  for (const file of ['function.cj', 'function_single.cj', 'greeting.cj']) await copy(`pkgB/${file}`, path.join(work, `pkgB/${file}`));
  await copy('pkgA/pkgA.cj', path.join(work, 'pkgA/pkgA.cj'));
  await Promise.all([fs.mkdir(path.join(work, 'ref')), fs.mkdir(path.join(work, 'self'))]);
  const dep = await invoke(selfhost, [path.join(work, 'pkgA/pkgA.cj'), '--output-type=staticlib', '-o', path.join(work, 'pkgA/libpkgA.a'), '--set-runtime-rpath'], path.join(work, 'pkgA.self.stdout'), path.join(work, 'pkgA.self.stderr'));
  if (dep.exitCode !== 0) fail('SEPTEST-WRITE', `selfhost pkgA compile failed: ${dep.stderr.replaceAll('\n', ' ')}`);
  for (const file of ['pkgA/pkgA.cjo', 'pkgA/libpkgA.a']) try { await fs.access(path.join(work, file)); } catch { fail('SEPTEST-WRITE', `selfhost pkgA did not produce ${path.basename(file)}`); }
  const cjo = await fs.readFile(path.join(work, 'pkgA/pkgA.cjo')); const magic = cjo.subarray(4, 8).toString();
  if (magic !== 'CJOF') fail('SEPTEST-WRITE', `selfhost pkgA.cjo has wrong file identifier '${magic}'`);
  console.log('SEPTEST-WRITE-PASS pkgA magic=CJOF');
  async function one(who, compiler, name, expected) {
    const binary = path.join(work, who, name);
    const built = await invoke(compiler, [path.join(work, `pkgB/${name}.cj`), '--import-path', path.join(work, 'pkgA'), '-L', path.join(work, 'pkgA'), '-lpkgA', '-o', binary, '--set-runtime-rpath'], path.join(work, `${who}.${name}.stdout`), path.join(work, `${who}.${name}.stderr`));
    if (built.exitCode !== 0) fail('SEPTEST-WRITE', `${who} pkgB ${name} compile failed: ${built.stderr.replaceAll('\n', ' ')}`);
    const executed = await run(binary, path.join(work, `${who}.${name}.run.stderr`)); const value = output(executed);
    if (executed.exitCode !== 0) fail('SEPTEST-WRITE', `${who} pkgB ${name} exited with ${executed.exitCode}`);
    if (value !== expected) fail('SEPTEST-WRITE', `${who} pkgB ${name} output '${value}' did not match expected '${expected}'`);
    console.log(`SEPTEST-WRITE-PASS ${who}:${name} output=${value}`);
  }
  await one('self', selfhost, 'function', '42'); await one('self', selfhost, 'function_single', '42'); await one('self', selfhost, 'greeting', 'hello from pkgA');
  await one('ref', reference, 'function', '42'); await one('ref', reference, 'greeting', 'hello from pkgA');
  console.log('SEPTEST-WRITE-PASS');
} finally { await fs.rm(work, {recursive: true, force: true}); }

#!/usr/bin/env zx
// Macro package expansion golden gate for frontend-to-macro integration.

import fs from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';
import {compareOrWrite, configureToolchain, executable, finishGolden, normalized, parseGoldenMode} from './zx_gate_lib.mjs';

const fixtureDir = path.join(import.meta.dirname, 'macro_fixtures');
const goldenDir = path.join(fixtureDir, 'golden');
const home = process.env.CANGJIE_HOME || '/root/cj_build/cangjie_compiler/output';
const reference = process.env.REF_CJC || `${home}/bin/cjc`;
configureToolchain(home, false);
const state = parseGoldenMode(reference);
if (state.mode === 'help') {
  console.log('Usage: macro_gate.mjs [--self <cjc>|--check]');
  process.exit(0);
}
if (!await executable(state.compiler)) {
  console.error(`FATAL: compiler not executable: ${state.compiler}`);
  process.exit(2);
}

await fs.mkdir(goldenDir, {recursive: true});
const fixtures = ['f1_decl_identity', 'f2_multi_decl', 'f3_nested', 'f4_attr_macro', 'f5_unused_import'];
const results = [];
let pass = 0;
let fail = 0;
for (const fixture of fixtures) {
  const source = path.join(fixtureDir, fixture);
  const work = await fs.mkdtemp(path.join(os.tmpdir(), 'macro-gate-'));
  const transcript = path.join(work, 'transcript.txt');
  try {
    for (const dir of ['mdef', 'use', 'control']) {
      try { await fs.cp(path.join(source, dir), path.join(work, dir), {recursive: true}); } catch (error) { if (error.code !== 'ENOENT') throw error; }
    }
    await fs.mkdir(path.join(work, 'out'));
    let contents = '';
    async function record(tag, args) {
      const result = await $({nothrow: true, quiet: true})`${state.compiler} ${args}`;
      contents += `[${tag}] rc=${result.exitCode}\n${normalized(result.stdout + result.stderr, [[work, '<BUILD>'], [home, '<HOME>']])}\n`;
      return result.exitCode;
    }
    const macroSources = (await fs.readdir(path.join(work, 'mdef'))).filter(file => file.endsWith('.cj')).sort().map(file => path.join(work, 'mdef', file));
    await record('macro-compile', ['--compile-macro', ...macroSources, '-Woff', 'unused', '-o', path.join(work, 'out')]);
    const useSources = (await fs.readdir(path.join(work, 'use'))).filter(file => file.endsWith('.cj')).sort().map(file => path.join(work, 'use', file));
    if (await record('user-compile', [...useSources, '--import-path', path.join(work, 'out'), '-o', path.join(work, 'use/app')]) === 0) {
      const run = await $({nothrow: true, quiet: true})`${path.join(work, 'use/app')}`;
      contents += `[run] exit=${run.exitCode}\n`;
    }
    try {
      const controlSources = (await fs.readdir(path.join(work, 'control'))).filter(file => file.endsWith('.cj')).sort().map(file => path.join(work, 'control', file));
      await record('control-compile', [...controlSources, '-o', path.join(work, 'control/app')]);
    } catch (error) {
      if (error.code !== 'ENOENT') throw error;
    }
    await fs.writeFile(transcript, contents);
    const ok = await compareOrWrite({mode: state.mode, label: state.label, fixture, transcript, golden: path.join(goldenDir, `${fixture}.golden`), work, results});
    if (ok) pass++; else fail++;
  } finally {
    await fs.rm(work, {recursive: true, force: true});
  }
}
await finishGolden({mode: state.mode, label: state.label, name: 'macro_gate', compiler: state.compiler, home, goldenDir, results, pass, fail, includeHome: true});

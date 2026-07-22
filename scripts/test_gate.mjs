#!/usr/bin/env zx
// --test and mock golden gate, including product execution and stable symbol counts.

import fs from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';
import {compareOrWrite, configureToolchain, executable, finishGolden, normalized, parseGoldenMode} from './zx_gate_lib.mjs';

const fixtureDir = path.join(import.meta.dirname, 'test_fixtures');
const goldenDir = path.join(fixtureDir, 'golden');
const home = process.env.CANGJIE_HOME || '/root/cj_build/cangjie_compiler/output';
const reference = process.env.REF_CJC || `${home}/bin/cjc`;
configureToolchain(home);
const state = parseGoldenMode(reference);
if (state.mode === 'help') { console.log('Usage: test_gate.mjs [--self <cjc>|--check]'); process.exit(0); }
if (!await executable(state.compiler)) { console.error(`FATAL: compiler not executable: ${state.compiler}`); process.exit(2); }
await fs.mkdir(goldenDir, {recursive: true});

const results = [];
let pass = 0;
let fail = 0;
for (const fixture of ['t1_test_basic', 't2_mock_member', 't3_test_vs_normal']) {
  const work = await fs.mkdtemp(path.join(os.tmpdir(), 'test-gate-'));
  const transcript = path.join(work, 'transcript.txt');
  let contents = '';
  try {
    for (const file of await fs.readdir(path.join(fixtureDir, fixture))) {
      if (file.endsWith('.cj')) await fs.copyFile(path.join(fixtureDir, fixture, file), path.join(work, file));
    }
    async function record(tag, args) {
      const result = await $({nothrow: true, quiet: true})`${state.compiler} ${args}`;
      contents += `[${tag}] rc=${result.exitCode}\n${normalized(result.stdout + result.stderr, [[work, '<BUILD>'], [home, '<HOME>']])}\n`;
    }
    async function recordRun(tag, binary, withOutput = false) {
      if (!await executable(binary)) { contents += `[${tag}] exit=<no-binary>\n`; return; }
      const result = await $({nothrow: true, quiet: true})`timeout 60 ${binary}`;
      contents += `[${tag}] exit=${result.exitCode}\n`;
      if (withOutput) contents += `${normalized(result.stdout, [[work, '<BUILD>'], [home, '<HOME>']])}\n`;
    }
    async function recordSymbols(tag, binary) {
      if (!await executable(binary)) { contents += `[${tag}] <no-binary>\n`; return; }
      const nm = await $({nothrow: true, quiet: true})`nm ${binary}`;
      const count = regex => nm.stdout.split('\n').filter(line => regex.test(line)).length;
      contents += `[${tag}]\n  TestPackage=${count(/TestPackage/)}\n  registerSuite=${count(/register[A-Za-z0-9_]*Suite/)}\n  testEntry=${count(/entry_main/)}\n  ToMock=${count(/ToMock/)}\n`;
    }
    if (fixture === 't1_test_basic') {
      const app = path.join(work, 't1.app');
      await record('compile-test', ['--test', path.join(work, 'basic_test.cj'), '-o', app]); await recordRun('run-test', app); await recordSymbols('symbols-test', app);
    } else if (fixture === 't2_mock_member') {
      const app = path.join(work, 't2.app');
      await record('compile-test-mock', ['--test', '--mock=on', path.join(work, 'mock_test.cj'), '-o', app]); await recordRun('run-test-mock', app); await recordSymbols('symbols-test-mock', app);
    } else {
      const normal = path.join(work, 't3_normal.app'); const test = path.join(work, 't3_test.app');
      await record('compile-normal', [path.join(work, 'dual.cj'), '-o', normal]); await recordRun('run-normal', normal, true); await recordSymbols('symbols-normal', normal);
      await record('compile-test', ['--test', path.join(work, 'dual.cj'), '-o', test]); await recordRun('run-test', test); await recordSymbols('symbols-test', test);
    }
    await fs.writeFile(transcript, contents);
    const ok = await compareOrWrite({mode: state.mode, label: state.label, fixture, transcript, golden: path.join(goldenDir, `${fixture}.golden`), work, results});
    if (ok) pass++; else fail++;
  } finally { await fs.rm(work, {recursive: true, force: true}); }
}
await finishGolden({mode: state.mode, label: state.label, name: 'test_gate', compiler: state.compiler, home, goldenDir, results, pass, fail, includeHome: true});

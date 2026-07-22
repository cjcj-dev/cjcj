#!/usr/bin/env zx
// Runtime-annotation gate: compare exact diagnostics and verify the NoStackGrow LLVM attribute.

import fs from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';
import {configureToolchain} from './zx_gate_lib.mjs';

const root = path.resolve(import.meta.dirname, '..');
const fixtures = path.join(root, 'scripts/w4annot_fixtures');
const cjc = argv._[0] || `${root}/target/release/bin/cjcj::cjc`;
const home = process.env.CANGJIE_HOME || '/root/.cjv/toolchains/nightly-1.2.0-alpha.20260619020029';
configureToolchain(home);
const work = await fs.mkdtemp(path.join(os.tmpdir(), 'w4annot-'));
let passCount = 0;
let failCount = 0;
const pass = message => { console.log(`PASS ${message}`); passCount++; };
const fail = message => { console.log(`FAIL ${message}`); failCount++; };

const cases = new Map([
  ['noheap_bad', ["error: '@NoHeapAlloc' not applicable to static call closure emitted heap allocation 'llvm.cj.malloc.object'", "note: @NoHeapAlloc root is 'allocateObject'", 'note: static call path: allocateObject']],
  ['noheap_array_bad', ["error: '@NoHeapAlloc' not applicable to static call closure emitted heap allocation 'llvm.cj.malloc.array'", "note: @NoHeapAlloc root is 'allocateArray'", 'note: static call path: allocateArray']],
  ['noheap_box_bad', ["error: '@NoHeapAlloc' not applicable to static call closure emitted heap allocation 'llvm.cj.malloc.object'", "note: @NoHeapAlloc root is 'noHeapBox'", 'note: static call path: noHeapBox -> boxInteger']],
  ['noheap_closure_bad', ["error: '@NoHeapAlloc' not applicable to static call closure emitted heap allocation 'llvm.cj.malloc.object'", "note: @NoHeapAlloc root is 'makeClosure'", 'note: static call path: makeClosure']],
  ['nowritebarrier_bad', ["error: '@NoWriteBarrier' not applicable to static call closure emitted write barrier while lowering 'StoreElementRef'", "note: @NoWriteBarrier root is 'barrier'", 'note: static call path: barrier']],
  ['nowritebarrierrec_bad', ["error: '@NoWriteBarrierRec' not applicable to static call closure emitted write barrier while lowering 'StoreElementRef'", "note: @NoWriteBarrierRec root is 'barrierRoot'", 'note: static call path: barrierRoot -> makeHolder -> init']],
  ['nowritebarrierrec_cycle_bad', ["error: '@NoWriteBarrierRec' not applicable to static call closure emitted write barrier while lowering 'StoreElementRef'", '  # note: recursive static-call cycle: cycleRoot -> cycleA -> cycleB -> cycleA', "note: @NoWriteBarrierRec root is 'cycleRoot'", 'note: static call path: cycleRoot -> cycleA -> init']],
  ['nowritebarrierrec_aggregate_bad', ["error: '@NoWriteBarrierRec' not applicable to static call closure emitted write barrier while lowering 'Apply'", "note: @NoWriteBarrierRec root is 'aggregateBarrier'", 'note: static call path: aggregateBarrier']],
  ['nowritebarrierrec_tuple_bad', ["error: '@NoWriteBarrierRec' not applicable to static call closure emitted write barrier while lowering 'Tuple'", "note: @NoWriteBarrierRec root is 'tupleBarrier'", 'note: static call path: tupleBarrier']],
  ['nowritebarrierrec_box_bad', ["error: '@NoWriteBarrierRec' not applicable to static call closure emitted write barrier while lowering 'Box'", "note: @NoWriteBarrierRec root is 'boxBarrier'", 'note: static call path: boxBarrier']],
  ['invalid_target', ["error: class cannot be modified with '@NoStackGrow'"]],
  ['systemstack_invalid_target', ["error: class cannot be modified with '@SystemStack'"]],
]);

async function firstLines(text, count) {
  const selected = text.split('\n').slice(0, count).join('\n');
  process.stdout.write(selected.endsWith('\n') ? selected : `${selected}\n`);
}

try {
  let result = await $({cwd: work, nothrow: true, quiet: true})`${cjc} ${fixtures}/legal.cj -o ${work}/legal`;
  await fs.writeFile(`${work}/legal.out`, result.stdout + result.stderr);
  if (result.exitCode === 0) {
    const run = await $({nothrow: true, quiet: true})`${work}/legal`;
    if (run.stdout.replace(/\n+$/, '') === '43') pass('legal annotations compile and run');
    else { fail('legal annotations'); await firstLines(result.stdout + result.stderr, 20); }
  } else { fail('legal annotations'); await firstLines(result.stdout + result.stderr, 20); }

  for (const [name, expected] of cases) {
    result = await $({cwd: work, nothrow: true, quiet: true})`${cjc} ${fixtures}/${name}.cj --diagnostic-format=noColor -o ${work}/${name}`;
    const output = result.stdout + result.stderr;
    await fs.writeFile(`${work}/${name}.out`, output);
    if (result.exitCode === 0) { fail(`${name} accepted`); continue; }
    const actual = output.split('\n').filter(line => /^(error|note):|^  # note:/.test(line));
    if (actual.length !== expected.length) { fail(`${name} diagnostic count expected=${expected.length} actual=${actual.length}`); await firstLines(output, 80); continue; }
    const mismatch = expected.findIndex((line, index) => actual[index] !== line);
    if (mismatch >= 0) {
      fail(`${name} diagnostic[${mismatch}] mismatch`); console.log(`EXPECTED: ${expected[mismatch]}`); console.log(`ACTUAL:   ${actual[mismatch]}`); continue;
    }
    const location = name === 'noheap_array_bad' ? 'noheap_array_bad.cj:3:' : name === 'noheap_closure_bad' ? 'noheap_closure_bad.cj:5:' : '';
    if (location && !output.includes(location)) { fail(`${name} missing allocation-site location ${location}`); await firstLines(output, 40); continue; }
    pass(`${name} rejected with exact diagnostics`);
  }

  result = await $({cwd: work, nothrow: true, quiet: true})`${cjc} ${fixtures}/nostackgrow.cj --output-type=staticlib -o ${work}/libnostackgrow.a`;
  await fs.writeFile(`${work}/nostackgrow.out`, result.stdout + result.stderr);
  let found = false;
  if (result.exitCode === 0) {
    let cached = [];
    try { cached = (await fs.readdir(`${work}/.cached`)).filter(file => file.endsWith('.bc')); } catch {}
    for (const file of cached) await $({nothrow: true, quiet: true})`${home}/third_party/llvm/bin/llvm-dis ${work}/.cached/${file} -o ${work}/.cached/${file}.ll`;
    for (const file of cached.map(file => `${file}.ll`)) {
      const ir = await fs.readFile(`${work}/.cached/${file}`, 'utf8');
      const definition = ir.match(/define .*noGrow.*#([0-9]+)/);
      if (definition && new RegExp(`attributes #${definition[1]} = .*"gc-leaf-function"`).test(ir)) { found = true; break; }
    }
  }
  if (found) pass('NoStackGrow emits gc-leaf-function');
  else { fail('NoStackGrow LLVM attribute'); await firstLines(result.stdout + result.stderr, 30); }

  console.log(`W4ANNOT: PASS=${passCount} FAIL=${failCount}`);
  process.exitCode = failCount === 0 ? 0 : 1;
} finally {
  await fs.rm(work, {recursive: true, force: true});
}

#!/usr/bin/env zx
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { join } from 'node:path';

// Consume the real cjc --save-temps disassembly and SDK Node --trace-wasm output.
// The same assertions run against the earlier and current compiler artifacts.
const [out] = globalThis.argv?._ ?? process.argv.slice(2);
assert.ok(out, 'pass the directory with cfg.ll and node.log');
const ir = await readFile(join(out, 'cfg.ll'), 'utf8');
const trace = await readFile(join(out, 'node.log'), 'utf8');
const rc = async name => (await readFile(join(out, name + '.rc'), 'utf8')).trim();
for (const name of ['cjc', 'dis', 'node']) assert.equal(await rc(name), '0', name);

const pushes = trace.split('"cjw_root_frame_push" {').length - 1;
const pops = trace.split('"cjw_root_frame_pop" {').length - 1;
assert.match(trace, /wasm CFG roots canaries reached/);
assert.match(trace, /precise=0/);
assert.ok(pushes > 0);
assert.equal(pushes, pops);
console.log('Node reached business assertions; C6 frames ' + pushes + '/' + pops);

function body(name) {
  const lines = ir.split('\n');
  const start = lines.findIndex(line => line.startsWith('define ') && line.includes(name + 'H'));
  assert.ok(start >= 0, name + ' definition');
  const end = lines.indexOf('}', start);
  assert.ok(end > start, name + ' end');
  const blocks = [];
  for (const line of lines.slice(start + 1, end)) {
    if (/^[-.\w]+:/.test(line)) blocks.push([]);
    if (blocks.length) blocks.at(-1).push(line);
  }
  return blocks;
}

function atNoise(blocks, seed) {
  const sites = blocks.flatMap(block => block.flatMap((line, i) =>
    line.includes('allocateNoiseH') && line.includes('(i64 ' + seed + ')') ? [[block, i]] : []));
  assert.equal(sites.length, 1, 'named allocation at ' + seed);
  return sites[0];
}

const isCall = line => line.includes(' call ') && !line.includes('@llvm.dbg.');
const spill = /%(wasm\.root\.spill\d*)/;
function checkFrame(blocks, seed, crossBlock) {
  const [block, site] = atNoise(blocks, seed);
  const push = block.findLastIndex((line, i) => i < site && isCall(line));
  const pop = block.findIndex((line, i) => i > site && isCall(line));
  const reload = block.findIndex((line, i) => site < i && i < pop && /%wasm\.root\.reload\d* = load volatile /.test(line));
  console.log('named allocation ' + seed + ' reached; push=' + push + ' reload=' + reload + ' pop=' + pop);
  assert.ok(push >= 0 && /^ *call void @cjw_root_frame_push\(/.test(block[push]), seed + ' C6 push');
  assert.ok(site < reload && reload < pop, seed + ' C6 volatile reload');
  const frame = block[push].match(/push\(([^)]*)\)/)?.[1];
  assert.ok(frame && frame === block[pop].match(/pop\(([^)]*)\)/)?.[1], seed + ' same C6 frame');
  const value = block[reload].trim().split(' ', 1)[0];
  const pushed = block.slice(0, push).findLast(line => /%wasm\.root\.current\d* = load .*%wasm\.root\.spill/.test(line));
  if (crossBlock || pushed) {
    assert.ok(pushed, seed + ' publishes the current value from the cross-block slot');
    const address = pushed.match(spill)[0];
    const pushedValue = pushed.trim().split(' ', 1)[0];
    assert.ok(block.slice(0, push).some(line => line.includes('store volatile') && line.includes(pushedValue + ',')),
      seed + ' writes current base to the frame');
    assert.ok(block.slice(reload + 1, pop).some(line => line.includes('store ') &&
      line.includes(value + ',') && line.match(spill)?.[0] === address), seed + ' writes reload back to its slot');
    return address;
  }
  assert.ok(block.slice(pop + 1).some(line => line.includes('serialOfH') && line.includes(value)),
    seed + ' consumes the local reload');
}

const cross = body('keepAcrossBlocks');
const control = body('deadOnOneEdge');
checkFrame(control, 30, false);
const [dead, deadSite] = atNoise(control, 40);
console.log('dead edge allocation 40 reached at instruction ' + deadSite);
assert.ok(!dead.some(line => line.includes('@cjw_root_frame_')), 'dead edge leaves the base outside the frame');

const errors = [];
const slots = [];
for (const seed of [1, 10, 20]) {
  try {
    slots.push(checkFrame(cross, seed, true));
  } catch (error) {
    errors.push(error);
  }
}
if (errors.length) throw new AggregateError(errors, 'live branch allocations lack their C6 root');
assert.equal(new Set(slots).size, 1, 'both branches and their entry share the same root slot');
const label = block => block[0].split(':', 1)[0];
const predecessors = block => [...(block[0].split('preds = ')[1] ?? '').matchAll(/%([-.\w]+)/g)].map(m => m[1]);
const joinUse = cross.find(block => block.some(line => line.includes('serialOfH')) &&
  !block.some(line => line.includes('allocateNoiseH')));
assert.ok(joinUse, 'joined use of the live base');
const blocks = new Map(cross.map(block => [label(block), block]));
let merge = joinUse;
while (predecessors(merge).length === 1) merge = blocks.get(predecessors(merge)[0]);
assert.ok(predecessors(merge).length > 1, 'consumer follows a control flow merge');
const reads = joinUse.filter(line => /%wasm\.root\.current\d* = load /.test(line) &&
  line.match(spill)?.[0] === slots[0]).map(line => line.trim().split(' ', 1)[0]);
assert.ok(joinUse.some(line => line.includes('serialOfH') && reads.some(value => line.includes(value + ')'))),
  'joined consumer receives the reloaded base');
console.log('WASM_CFG_ROOT_ASSERTIONS_REACHED');

import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import test from 'node:test';
import crypto from 'node:crypto';
import {spawn} from 'node:child_process';
import {makePlan, validatePlan, aggregate, executeNode, totals} from './contract-shards.mjs';
const source = {head: 'a'.repeat(40), tree: 'b'.repeat(40)};
const files = Array.from({length: 9}, (_, i) => `case-${i}.test.mjs`);
const plan = makePlan(files, source);
const digest = crypto.createHash('sha256').update(JSON.stringify(plan)).digest('hex');
const rows = () => plan.groups.map(group => ({id: group.id, files: group.files, source,
  planHash: digest, inputs: {node: {version: process.version, sha256: 'c'.repeat(64)}, zx: {version:'8.8.5',cliSha256:'d'.repeat(64),packageSha256:'e'.repeat(64)},runtime:{head:'f'.repeat(40),tree:'a'.repeat(40)},historyBlob:'b'.repeat(40),host:{version:'fixed',cjcSha256:'c'.repeat(64),coreSha256:'d'.repeat(64)}},
  node: {argv: [process.execPath, '--test', '--test-reporter=tap', '--test-timeout=300000', ...group.files], code: 0, signal: null, cancellationRequested: null,
    totals: {tests: 2, suites: 0, pass: 1, fail: 0, cancelled: 0, skipped: 1, todo: 0}}}));

test('deterministic whole-file plan rejects omission, duplication and empty groups', () => {
  assert.deepEqual(validatePlan(plan, files), plan);
  for (const mutate of [p => p.files.pop(), p => p.groups.pop(), p => p.groups[0].files.pop(),
    p => p.groups[1].files.push(p.groups[0].files[0]), p => p.groups[2].files = []]) {
    const broken = structuredClone(plan); mutate(broken);
    assert.throws(() => validatePlan(broken, files), /CONTRACT_SHARDS/);
  }
  assert.deepEqual(aggregate(plan, rows(), files).totals, {tests:8,pass:4,fail:0,cancelled:0,skipped:4,todo:0});
});

test('summary rejects missing duplicate empty cancelled and incomplete results exactly', () => {
  for (const mutate of [r => r.pop(), r => r[1] = r[0], r => r[0].files = [],
    r => r[0].node.code = 1, r => { r[0].node.code = null; r[0].node.signal = 'SIGTERM'; },
    r => r[0].node.totals = null, r => r[0].node.totals.cancelled = 1,
    r => r[0].node.argv.pop(), r => r[0].source = {...source,head:'f'.repeat(40)},
    r => r[1].inputs.node.version = 'different']) {
    const broken = rows(); mutate(broken);
    assert.throws(() => aggregate(plan, broken, files), /CONTRACT_SHARDS/);
    assert.equal(aggregate(plan, rows(), files).status, 'PASS');
  }
});

test('real Node failure and success preserve actual argv and terminal TAP', async t => {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), 'contract-child-'));
  t.after(() => fs.rmSync(root, {recursive:true,force:true}));
  const file = path.join(root, 'probe.mjs');
  fs.writeFileSync(file, 'import test from "node:test"; import assert from "node:assert/strict"; test("target",()=>assert.equal(1,2));\n');
  const env = {...process.env}; delete env.NODE_TEST_CONTEXT;
  const red = await executeNode([file], path.join(root, 'red'), {env});
  assert.equal(red.code, 1); assert.equal(red.signal, null); assert.equal(red.totals.fail, 1);
  assert.deepEqual(red.argv.slice(-1), [file]);
  assert.match(fs.readFileSync(path.join(root,'red/stdout.tap'),'utf8'), /1 !== 2/);
  fs.writeFileSync(file, 'import test from "node:test"; test("target",()=>{});\n');
  const green = await executeNode([file], path.join(root, 'green'), {env});
  assert.equal(green.code, 0); assert.equal(green.totals.pass, 1);
  assert.equal(totals('TAP version 13\n'), null);
});

test('controlled cancellation preserves signal and refuses missing terminal totals', async t => {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), 'contract-cancel-'));
  t.after(() => fs.rmSync(root, {recursive:true,force:true}));
  const target = path.join(root,'wait.mjs'), marker=path.join(root,'ready');
  fs.writeFileSync(target, `import fs from 'node:fs'; fs.writeFileSync(${JSON.stringify(marker)},'ready'); setInterval(()=>{},1000);`);
  const driver = path.join(root,'driver.mjs');
  fs.writeFileSync(driver, `import {executeNode} from ${JSON.stringify(new URL('./contract-shards.mjs',import.meta.url).href)}; await executeNode([${JSON.stringify(target)}],${JSON.stringify(path.join(root,'out'))});`);
  const env={...process.env}; delete env.NODE_TEST_CONTEXT;
  const child=spawn(process.execPath,[driver],{stdio:'ignore',env});
  t.after(() => { if (child.exitCode === null) child.kill('SIGKILL'); });
  const closed=new Promise(resolve=>child.on('close',(code,signal)=>resolve({code,signal})));
  const deadline=Date.now()+10000;
  while(!fs.existsSync(marker) && Date.now()<deadline) await new Promise(resolve=>setTimeout(resolve,20));
  assert.ok(fs.existsSync(marker),'actual test child reached ready');
  child.kill('SIGTERM'); await closed;
  const result=JSON.parse(fs.readFileSync(path.join(root,'out/node-result.json')));
  assert.equal(result.cancellationRequested.signal,'SIGTERM');
  assert.ok(result.code !== 0 || result.signal !== null, JSON.stringify(result));
  const broken=rows();broken[0].node={...broken[0].node,code:result.code,signal:result.signal,totals:result.totals,cancellationRequested:result.cancellationRequested};
  assert.throws(()=>aggregate(plan,broken,files),/Node failed or cancelled/);
  const cancelledSuccess=rows();cancelledSuccess[0].node.cancellationRequested=result.cancellationRequested;
  assert.throws(()=>aggregate(plan,cancelledSuccess,files),/Node failed or cancelled/);
  console.log(`CANCELLATION_OBSERVED ${JSON.stringify({code:result.code,signal:result.signal,request:result.cancellationRequested})}`);
});

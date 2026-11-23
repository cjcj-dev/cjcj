import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import {STAGES, layout, chainPlan, assertSameSourceChain, stdFreeView} from '../bootstrap.mjs';

const L = layout('/w');
const tmp = () => fs.mkdtempSync(path.join(os.tmpdir(), 'sdk-chain-'));
const TUPLE = 'linux_x86_64_cjnative';

test('chain: runBootstrap executes H1 order std-bootstrap -> stage1-initial -> stage1-std -> stage2 -> final-std -> stage3', () => {
  const plan = chainPlan(L);
  assert.deepEqual(plan.map(step => step.stage), STAGES.slice(3, -1));
  const order = ['std-bootstrap', 'stage1-initial', 'stage1-std', 'stage2', 'final-std', 'stage3'].map(stage => plan.findIndex(s => s.stage === stage));
  assert.deepEqual([...order].sort((a, b) => a - b), order);
  assert.equal(assertSameSourceChain(plan), plan);
});

test('chain: the seed std is consumed only by the Stage1 compile and its generator; no std is built inside a seed-std SDK', () => {
  const plan = chainPlan(L);
  assert.deepEqual(plan.filter(step => step.std === 'seed' || step.stdInput === 'seed').map(step => step.id), ['05b-stage1', '05c-stage1-generator']);
  const stds = plan.filter(step => step.kind === 'std');
  assert.deepEqual(stds.map(step => step.sdk), [L.stdView, L.s1Init, L.c2Sdk]);
  assert.deepEqual(plan.filter(step => step.kind === 'compiler' && step.stdInput !== 'seed').map(step => step.stdInput), [L.std1, L.std]);
});

test('chain control arm: the Stage A shortcut (final std from a generator holding the seed std) is refused', () => {
  const shortcut = chainPlan(L).map(step => step.id === '06-stdlib' ? {...step, sdk: L.c1Sdk} : step);
  assert.throws(() => assertSameSourceChain(shortcut), /^Error: CHAIN_SEED_STD 06-stdlib$/);
  const noView = chainPlan(L).map(step => step.id === '06a-std-bootstrap' ? {...step, sdk: L.c1Sdk} : step);
  assert.throws(() => assertSameSourceChain(noView), /^Error: CHAIN_SEED_STD 06a-std-bootstrap$/);
  const stage2OnSeed = chainPlan(L).map(step => step.id === '06e-stage2' ? {...step, stdInput: 'seed', sdk: L.seed0} : step);
  assert.throws(() => assertSameSourceChain(stage2OnSeed), /^Error: CHAIN_COMPILER_STD 06e-stage2$/);
});

function generator(root) {
  for (const [file, body] of [[`modules/${TUPLE}/std/core.cjo`, 'seed'], [`modules/${TUPLE}/std.core.cjo`, 'seed'], [`modules/${TUPLE}/flatbuffers.cjo`, 'fb'],
    [`lib/${TUPLE}/libcangjie-std-core.a`, 'seed'], [`lib/${TUPLE}/libcangjie-std-core.so`, 'seed'], [`lib/${TUPLE}/libcangjie-runtime.so`, 'rt'],
    [`.compiler-exec/lib/${TUPLE}/libcangjie-std-core.so`, 'exec'], ['libexec/compiler/cjcj-stage1', 'c1'], ['STAGE-INPUTS.json', '{}']]) {
    fs.mkdirSync(path.dirname(path.join(root, file)), {recursive: true});
    fs.writeFileSync(path.join(root, file), body);
  }
  return root;
}

test('std-free view: target std modules/libraries are absent, compiler execution std and everything else kept, source untouched', () => {
  const base = tmp(), from = generator(path.join(base, 'gen')), to = path.join(base, 'view');
  const facts = stdFreeView(from, to, TUPLE);
  assert.deepEqual(facts.removed, [`modules/${TUPLE}/std`, `modules/${TUPLE}/std.core.cjo`, `lib/${TUPLE}/libcangjie-std-core.a`, `lib/${TUPLE}/libcangjie-std-core.so`]);
  for (const gone of [`modules/${TUPLE}/std`, `lib/${TUPLE}/libcangjie-std-core.a`]) assert.equal(fs.existsSync(path.join(to, gone)), false, gone);
  for (const kept of [`modules/${TUPLE}/flatbuffers.cjo`, `lib/${TUPLE}/libcangjie-runtime.so`, `.compiler-exec/lib/${TUPLE}/libcangjie-std-core.so`, 'libexec/compiler/cjcj-stage1'])
    assert.ok(fs.existsSync(path.join(to, kept)), kept);
  assert.ok(fs.existsSync(path.join(from, `modules/${TUPLE}/std/core.cjo`)) && fs.existsSync(path.join(from, `lib/${TUPLE}/libcangjie-std-core.a`)));
  assert.equal(fs.existsSync(`${to}.partial`), false);
  assert.deepEqual(stdFreeView(from, to, TUPLE), facts);
});

test('std-free view control arm: a generator without a target std is refused and leaves nothing behind', () => {
  const base = tmp(), from = generator(path.join(base, 'gen')), to = path.join(base, 'view');
  fs.rmSync(path.join(from, `modules/${TUPLE}/std`), {recursive: true}); fs.rmSync(path.join(from, `modules/${TUPLE}/std.core.cjo`));
  assert.throws(() => stdFreeView(from, to, TUPLE), /^Error: STD_VIEW_NOTHING_REMOVED /);
  assert.equal(fs.existsSync(to) || fs.existsSync(`${to}.partial`), false);
});

test('fresh std build tree: only the git-ignored stdlib/build output is removed; an unignored tree is refused', async () => {
  const {spawnSync} = await import('node:child_process');
  const {freshStdBuildTree} = await import('../bootstrap.mjs');
  const repo = tmp(), git = (...a) => spawnSync('git', ['-C', repo, ...a], {encoding: 'utf8'});
  git('init', '-q');
  fs.mkdirSync(path.join(repo, 'stdlib/build/build'), {recursive: true});
  fs.writeFileSync(path.join(repo, 'stdlib/build/build/stale.o'), 'c1');
  fs.writeFileSync(path.join(repo, 'stdlib/keep.cj'), 'src');
  assert.throws(() => freshStdBuildTree(repo), /^Error: STD_BUILD_TREE_NOT_IGNORED /);
  assert.ok(fs.existsSync(path.join(repo, 'stdlib/build/build/stale.o')));
  fs.writeFileSync(path.join(repo, 'stdlib/.gitignore'), 'build\n');
  freshStdBuildTree(repo);
  assert.equal(fs.existsSync(path.join(repo, 'stdlib/build')), false);
  assert.ok(fs.existsSync(path.join(repo, 'stdlib/keep.cj')));
});

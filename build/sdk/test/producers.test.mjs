// Production entry wiring of all 15 release assets onto build/sdk/producers, with control arms that cut
// one link at a time (each must turn the check red with its own code) and the current plan readiness.
import assert from 'node:assert/strict';
import test from 'node:test';
import {ASSETS} from '../targets.mjs';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import {fileURLToPath} from 'node:url';
import {ACTION_DIRS, CROSS_PRODUCERS, PRODUCERS_DIR, WORKFLOW_FILES, checkProductionWiring, loadWorkflows, planOutputs}
  from '../producers.mjs';

const plans = new Map(), plan = host => { if (!plans.has(host)) plans.set(host, planOutputs(host)); return plans.get(host); };
const real = loadWorkflows();
const check = (mutate = () => {}, exists) => {
  const workflows = structuredClone(real); mutate(workflows);
  return checkProductionWiring({workflows, plan, ...(exists ? {exists} : {})});
};

test('all 15 release package jobs are wired to real producers in build/sdk/producers', () => {
  const wiring = check();
  assert.deepEqual(wiring.map(w => w.asset).sort(), ASSETS.map(a => a.key).sort());
  const cross = wiring.flatMap(w => w.producers);
  assert.equal(cross.length, ASSETS.reduce((n, a) => n + a.crossTuples.length, 0));
  for (const p of cross) for (const step of p.steps) assert.ok(step.startsWith(`${PRODUCERS_DIR}/`), step);
  assert.deepEqual([...new Set(cross.map(p => p.job))].sort(),
    ['source-android', 'source-ios', 'source-ohos', 'source-stage3', 'source-wasm', 'source-windows']);
  assert.equal(Object.keys(CROSS_PRODUCERS).length, 9);
});

test('plan readiness of the 15 assets is reported, not hidden', () => {
  const status = Object.fromEntries(check().map(w => [w.asset, w.readiness]));
  const by = s => Object.keys(status).filter(k => status[k].status === s).sort();
  assert.deepEqual(by('runnable'), ['linux-x64', 'linux-x64-android', 'linux-x64-ohos', 'linux-x64-wasm']);
  assert.deepEqual(by('blocked'), ['darwin-arm64', 'darwin-arm64-android', 'darwin-arm64-ios', 'darwin-arm64-ohos',
    'darwin-arm64-wasm', 'darwin-x64', 'linux-arm64']);
  assert.deepEqual(by('unplanned'), ['win32-x64', 'win32-x64-android', 'win32-x64-ohos', 'win32-x64-wasm']);
  assert.match(status['linux-arm64'].reasons.join(), /linux_aarch64\.env is missing/);
  for (const k of by('blocked').filter(k => k.startsWith('darwin'))) assert.match(status[k].reasons.join(), /issues\/473/);
  for (const k of by('unplanned')) assert.match(status[k].reasons.join(), /unknown source target\(s\): windows-x64/);
});

const CONTROLS = [
  ['a release package job is removed', /WIRING_PACKAGE_MISSING darwin-arm64-ios/, w => { delete w.release.jobs['package-darwin-arm64-ios']; }],
  ['a package ships a tuple set different from targets.mjs', /WIRING_CROSS_TUPLES win32-x64-ohos/, w => {
    const j = w.release.jobs['package-win32-x64-ohos'].with;
    j.cross_std_artifacts = JSON.stringify(JSON.parse(j.cross_std_artifacts).slice(0, 1)); }],
  ['the producer job uploads a different artifact', /WIRING_ARTIFACT_UNPRODUCED source-wasm final-std-wasm32-wasi/, w => {
    for (const s of w.source.jobs['source-wasm'].steps) if (String(s.uses).startsWith('actions/upload-artifact')) s.with.name = 'final-std-wasm-renamed'; }],
  ['the producer job no longer runs its step', /WIRING_STEP_NOT_RUN source-ios build\/sdk\/producers\/srcbuild\/steps\/build-ios-final-std\.mjs/, w => {
    w.source.jobs['source-ios'].steps = w.source.jobs['source-ios'].steps.filter(s => !String(s.run ?? '').includes('build-ios-final-std')); }],
  ['a workflow runs a script from a retired ci/ tree', /WIRING_RETIRED_TREE source ci\/srcbuild\/target-matrix\.mjs/, w => {
    for (const s of w.source.jobs.plan.steps) if (s.run) s.run = s.run.replace('build/sdk/producers/srcbuild/', 'ci/srcbuild/'); }],
  ['publish stops waiting for a package', /WIRING_PUBLISH_NEEDS package-win32-x64-wasm/, w => {
    w.release.jobs.publish.needs = w.release.jobs.publish.needs.filter(n => n !== 'package-win32-x64-wasm'); }],
  ['a package no longer orders after its producer', /WIRING_PRODUCER_NEEDS package-linux-x64-android/, w => {
    w.release.jobs['package-linux-x64-android'].needs = []; }],
  ['a package call loses its package mode', /WIRING_PACKAGE_MISSING linux-x64-wasm/, w => {
    delete w.release.jobs['package-linux-x64-wasm'].with.mode; }],
  ['a host source call leaves build mode', /WIRING_HOST_SOURCE darwin-x64 source-p5-darwin-x64/, w => {
    w.release.jobs['source-p5-darwin-x64'].with.mode = 'llvm-tools'; }],
  ['sdk-build.yml stops gating its package job on package mode', /WIRING_PACKAGE_JOB/, w => {
    delete w.package.jobs.package.if; }],
  ['sdk-build.yml fans out to a different target workflow', /WIRING_SOURCE_CALL/, w => {
    w.package.jobs.srcbuild.uses = './.github/workflows/srcbuild-target.yml'; }],
];
for (const [name, code, mutate] of CONTROLS) test(`control arm: ${name}`, () => {
  assert.throws(() => check(mutate), code);
  assert.equal(check().length, 15);
});

test('control arm: a producer step file is missing', () => {
  const gone = `${PRODUCERS_DIR}/srcbuild/steps/build-android-final-std.mjs`;
  assert.throws(() => check(() => {}, f => f !== gone), /WIRING_STEP_MISSING build\/sdk\/producers\/srcbuild\/steps\/build-android-final-std\.mjs/);
});

// The collapse to four workflows and three composite actions is itself the contract: a probe workflow or a
// second report action coming back must turn this red, and every local `uses:` must resolve in the tree.
const REPO = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../../..');
const surface = (root = REPO) => ({
  workflows: fs.readdirSync(path.join(root, '.github/workflows')).sort(),
  actions: fs.readdirSync(path.join(root, '.github/actions')).sort(),
});
const localUses = (root = REPO) => {
  const out = [];
  for (const f of surface(root).workflows) for (const m of fs.readFileSync(path.join(root, '.github/workflows', f), 'utf8')
    .matchAll(/uses:\s*(\.\/\.github\/[^\s#]+)/g)) out.push([f, m[1]]);
  for (const a of surface(root).actions) for (const m of fs.readFileSync(path.join(root, '.github/actions', a, 'action.yml'), 'utf8')
    .matchAll(/uses:\s*(\.\/\.github\/[^\s#]+)/g)) out.push([a, m[1]]);
  return out;
};
const checkSurface = (root = REPO) => {
  const {workflows, actions} = surface(root);
  if (JSON.stringify(workflows) !== JSON.stringify([...WORKFLOW_FILES].sort())) throw new Error(`SURFACE_WORKFLOWS ${workflows}`);
  if (JSON.stringify(actions) !== JSON.stringify([...ACTION_DIRS].sort())) throw new Error(`SURFACE_ACTIONS ${actions}`);
  for (const [from, use] of localUses(root)) {
    const target = path.join(root, use.replace(/^\.\//, ''));
    if (!fs.existsSync(use.endsWith('.yml') ? target : path.join(target, 'action.yml'))) throw new Error(`SURFACE_USES ${from} ${use}`);
  }
  return {workflows, actions, uses: localUses(root).length};
};

test('the workflow surface is exactly ci, release, sdk-build and sdk-build-target with three actions', () => {
  const s = checkSurface();
  assert.deepEqual(s.workflows, ['ci.yml', 'release.yml', 'sdk-build-target.yml', 'sdk-build.yml']);
  assert.deepEqual(s.actions, ['native-windows-tools', 'sccache', 'setup-release-sdk']);
  assert.ok(s.uses >= 20, `only ${s.uses} local uses`);
});

const scratch = mutate => {
  const dir = fs.mkdtempSync(path.join(fs.realpathSync(os.tmpdir()), 'surface-'));
  fs.cpSync(path.join(REPO, '.github'), path.join(dir, '.github'), {recursive: true});
  try { mutate(dir); return checkSurface(dir); } finally { fs.rmSync(dir, {recursive: true, force: true}); }
};
test('control arm: a probe workflow comes back', () => {
  assert.throws(() => scratch(d => fs.writeFileSync(path.join(d, '.github/workflows/arm-soak.yml'), 'on: workflow_dispatch\n')),
    /SURFACE_WORKFLOWS .*arm-soak\.yml/);
});
test('control arm: the separate sccache-report action comes back', () => {
  assert.throws(() => scratch(d => { fs.mkdirSync(path.join(d, '.github/actions/sccache-report'));
    fs.writeFileSync(path.join(d, '.github/actions/sccache-report/action.yml'), 'name: x\n'); }), /SURFACE_ACTIONS .*sccache-report/);
});
test('control arm: a local uses points at a deleted workflow', () => {
  assert.throws(() => scratch(d => { const f = path.join(d, '.github/workflows/ci.yml');
    fs.writeFileSync(f, fs.readFileSync(f, 'utf8').replace('./.github/workflows/sdk-build-target.yml', './.github/workflows/build-llvm-tools.yml')); }),
    /SURFACE_USES ci\.yml \.\/\.github\/workflows\/build-llvm-tools\.yml/);
});

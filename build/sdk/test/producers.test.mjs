// Production entry wiring of all 15 release assets onto build/sdk/producers, with control arms that cut
// one link at a time (each must turn the check red with its own code) and the current plan readiness.
import assert from 'node:assert/strict';
import test from 'node:test';
import {ASSETS} from '../targets.mjs';
import {CROSS_PRODUCERS, PRODUCERS_DIR, checkProductionWiring, loadWorkflows, planOutputs} from '../producers.mjs';

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
];
for (const [name, code, mutate] of CONTROLS) test(`control arm: ${name}`, () => {
  assert.throws(() => check(mutate), code);
  assert.equal(check().length, 15);
});

test('control arm: a producer step file is missing', () => {
  const gone = `${PRODUCERS_DIR}/srcbuild/steps/build-android-final-std.mjs`;
  assert.throws(() => check(() => {}, f => f !== gone), /WIRING_STEP_MISSING build\/sdk\/producers\/srcbuild\/steps\/build-android-final-std\.mjs/);
});

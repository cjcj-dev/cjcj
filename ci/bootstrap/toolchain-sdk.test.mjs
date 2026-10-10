import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs/promises';
import path from 'node:path';
import os from 'node:os';
import {fileURLToPath} from 'node:url';
import {spawn} from 'node:child_process';
import {BOOTSTRAP_PHASES} from './freeze-bootstrap-plans.mjs';
import {PLAN_SCHEMA, validatePlan, buildIdentities, objectId, readJson, atomicJson, fileDigest,
  execute, ROLES, sourceIdentity, registeredSourceIdentity} from './sdk-manifest.mjs';

const here = path.dirname(fileURLToPath(import.meta.url));
const product = process.env.SDK_MANIFEST_PRODUCT || path.join(here, 'toolchain-sdk.mjs');
const engine = process.env.SDK_SHAREDBUILD_ENGINE;
const testRoot = process.env.SDK_MANIFEST_TEST_ROOT;
const tuple = 'linux_x86_64_cjnative';
import {fixture, command} from './fixtures/sdk-plan-fixture.mjs';
const clone = value => structuredClone(value);
async function invoke(f, args = []) { await atomicJson(f.planFile, f.plan); return command([process.execPath, product, '--plan', f.planFile, '--out', f.out, ...args]); }
function observed(result, label) { console.log(`TARGET_ASSERTION_EXECUTED ${label} rc=${result.rc}`); }

test('actual CLI dry-run resolves complete full-SHA/config/dependency directories without building', async () => {
  const f = await fixture(); const result = await invoke(f, ['--dry-run']); observed(result, 'dry-run');
  assert.equal(result.rc, 0, result.stderr); const data = JSON.parse(result.stdout.trim());
  assert.ok(data.components.every(value => value.directory.includes(f.plan.components.find(component => component.id === value.component).source.commit || f.plan.components[0].source.lockSha256)));
  await assert.rejects(fs.access(f.plan.buildRoot)); await assert.rejects(fs.access(f.out));
  const changed = clone(f.plan); changed.components[1].config.options.parameters.extra = 'different';
  assert.notEqual(buildIdentities(changed).get('runtime').directory, f.identities.get('runtime').directory);
  const relocated = clone(f.plan); relocated.buildRoot = path.join(f.root, 'other-build-root');
  assert.notEqual(buildIdentities(relocated).get('runtime').recipeId, f.identities.get('runtime').recipeId);
});
test('actual SDK entry builds missing producers, accepts different repository SHAs and reuses successful receipts', async () => {
  const f = await fixture(); const result = await invoke(f); observed(result, 'full-entry');
  assert.equal(result.rc, 0, result.stderr); assert.match(result.stdout, /SDK-BUILD-OK/);
  assert.notEqual(f.sources.runtime.commit, f.sources.compiler.commit);
  const manifest = await readJson(path.join(f.out, 'SDK.manifest.json'));
  assert.equal(manifest.components.runtime.source.commit, f.sources.runtime.commit);
  assert.equal(manifest.components['llvm-dylib'].source.commit, f.sources.llvm.commit);
  const runtime = await readJson(path.join(f.identities.get('runtime').directory, 'output.json'));
  assert.equal(runtime.execution.rc, 0); assert.match(await fs.readFile(path.join(f.identities.get('runtime').directory, 'sharedbuild-output/build.log'), 'utf8'), /FIXTURE_PRODUCER_EXECUTED mode=runtime/);
  const before = await fs.stat(path.join(f.identities.get('runtime').directory, 'output.json'));
  f.out = path.join(f.root, 'sdk-second'); const repeat = await invoke(f); observed(repeat, 'cache'); assert.equal(repeat.rc, 0, repeat.stderr);
  assert.equal((await fs.stat(path.join(f.identities.get('runtime').directory, 'output.json'))).mtimeMs, before.mtimeMs);
});
test('new opt plus old libLLVM is rejected by the real installed-source assertion', async () => {
  const f = await fixture(); const good = await invoke(f); assert.equal(good.rc, 0, good.stderr);
  const component = f.plan.components.find(value => value.id === 'llvm-dylib');
  const root = f.identities.get(component.id).directory;
  const library = path.join(root, 'artifacts/libLLVM-15.so'); const original = await fs.readFile(library);
  // An internally sealed but semantically wrong output reaches LLVM_TUPLE,
  // independently of the ordinary payload corruption guard.
  const bytes = Buffer.from(original); const token = Buffer.from(f.sources.llvm.commit); const at = bytes.indexOf(token); assert.ok(at >= 0);
  bytes.set(Buffer.from('e'.repeat(40)), at); await fs.writeFile(library, bytes);
  const output = await readJson(path.join(root, 'output.json')); output.files['libLLVM-15.so'].sha256 = await fileDigest(library);
  await atomicJson(path.join(root, 'output.json'), output); await fs.writeFile(path.join(root, 'DONE'), `${await fileDigest(path.join(root, 'output.json'))}\n`);
  f.out = path.join(f.root, 'mixed-sdk'); const mixed = await invoke(f); observed(mixed, 'llvm-mixed-stamp');
  assert.notEqual(mixed.rc, 0); assert.match(mixed.stderr, /rule=LLVM_TUPLE.*libLLVM-15.so/); await assert.rejects(fs.access(f.out));
  await fs.writeFile(library, original); output.files['libLLVM-15.so'].sha256 = await fileDigest(library);
  await atomicJson(path.join(root, 'output.json'), output); await fs.writeFile(path.join(root, 'DONE'), `${await fileDigest(path.join(root, 'output.json'))}\n`);
  const restored = await invoke(f); observed(restored, 'llvm-restored'); assert.equal(restored.rc, 0, restored.stderr);
});
test('ordinary payload replacement cannot be blessed by rewriting the installation lock', async () => {
  const f = await fixture(); assert.equal((await invoke(f)).rc, 0);
  const root = f.identities.get('std').directory, module = path.join(root, 'artifacts', `modules/${tuple}/std/core/core.Int64.ti`);
  const original = await fs.readFile(module), replacement = Buffer.from(original);
  replacement[0] ^= 1; await fs.writeFile(module, replacement);
  f.out = path.join(f.root, 'changed-sdk'); const changed = await invoke(f); observed(changed, 'ordinary-digest');
  assert.notEqual(changed.rc, 0); assert.match(changed.stderr, /rule=PAYLOAD_(DIGEST|TYPE).*core.Int64.ti/); await assert.rejects(fs.access(f.out));
  await fs.writeFile(module, original); const restored = await invoke(f); observed(restored, 'ordinary-restored'); assert.equal(restored.rc, 0, restored.stderr);
});
test('same-source stamped but uncoloured runtime archive cannot accompany the coloured shared runtime', async () => {
  const f = await fixture(); const good = await invoke(f); assert.equal(good.rc, 0, good.stderr);
  const root = f.identities.get('runtime').directory, archive = path.join(root, 'artifacts/install/lib', tuple, 'libcangjie-runtime.a');
  const archiveBytes = await fs.readFile(archive), receiptPath = path.join(root, 'output.json'), donePath = path.join(root, 'DONE');
  const receiptBytes = await fs.readFile(receiptPath), doneBytes = await fs.readFile(donePath);
  const object = path.join(f.root, 'uncoloured-runtime.o');
  assert.equal((await command(['cc', '-c', '-fPIC', `-DCJRT_SHA="${f.sources.runtime.commit}"`,
    path.join(f.sources.runtime.repo, 'runtime.c'), '-o', object])).rc, 0);
  await fs.unlink(archive); assert.equal((await command(['ar', 'rcs', archive, object])).rc, 0);
  const receipt = JSON.parse(receiptBytes), row = receipt.files[`install/lib/${tuple}/libcangjie-runtime.a`];
  row.sha256 = await fileDigest(archive); row.size = (await fs.stat(archive)).size;
  await atomicJson(receiptPath, receipt); await fs.writeFile(donePath, `${await fileDigest(receiptPath)}\n`);
  f.out = path.join(f.root, 'wrong-runtime-pair'); const rejected = await invoke(f); observed(rejected, 'runtime-static-colour');
  assert.notEqual(rejected.rc, 0); assert.match(rejected.stderr, /BOOTSTRAP_SDK_RUNTIME_COLOUR_PAIR_MISMATCH: shared_masks=1 archive_masks=0/);
  await assert.rejects(fs.access(f.out));
  await fs.writeFile(archive, archiveBytes); await fs.writeFile(receiptPath, receiptBytes); await fs.writeFile(donePath, doneBytes);
  const restored = await invoke(f); observed(restored, 'runtime-static-colour-restored'); assert.equal(restored.rc, 0, restored.stderr);
});
test('mixed frozen LLVM sources, cycles and incomplete plans reject before producing', async () => {
  const f = await fixture();
  for (const [name, mutate, rule] of [
    ['LLVM declaration', plan => { plan.components.find(value => value.id === 'llvm-dylib').source = clone(f.sources.compiler); }, /rule=LLVM_SOURCE/],
    ['cycle', plan => { plan.components.find(value => value.id === 'compiler').dependencies.push('std'); }, /rule=DEPENDENCY_CYCLE/],
    ['missing std', plan => { plan.components = plan.components.filter(value => value.id !== 'std'); }, /rule=MISSING_COMPONENT/],
    ['unknown adapter', plan => { plan.components[1].producer.adapter = 'shell-command'; }, /rule=ADAPTER/],
    ['path escape', plan => { plan.components[1].install[0].to = '../escape'; }, /rule=PATH/],
    ['unpaired boundscheck', plan => {
      const runtime = plan.components.find(value => value.id === 'runtime');
      runtime.roles = ['runtime']; const other = clone(runtime); other.id = 'bounds-only'; other.roles = ['boundscheck']; plan.components.push(other);
    }, /rule=RUNTIME_PAIR/],
  ]) {
    const bad = clone(f.plan); mutate(bad); await atomicJson(f.planFile, bad);
    const result = await command([process.execPath, product, '--plan', f.planFile, '--out', f.out]); observed(result, name);
    assert.notEqual(result.rc, 0); assert.match(result.stderr, rule); await assert.rejects(fs.access(f.plan.buildRoot));
  }
});
test('same-key parallel SDK requests serialize the producer and publish separate complete SDKs', async () => {
  const f = await fixture();
  const run = out => command([process.execPath, product, '--plan', f.planFile, '--out', out]);
  const [first, second] = await Promise.all([run(f.out), run(path.join(f.root, 'sdk-other'))]); observed(first, 'concurrent-first'); observed(second, 'concurrent-second');
  assert.equal(first.rc, 0, first.stderr); assert.equal(second.rc, 0, second.stderr);
  assert.equal(await fileDigest(path.join(f.out, 'SDK.manifest.json')), await fileDigest(path.join(f.root, 'sdk-other/SDK.manifest.json')));
  for (const component of f.plan.components.slice(1)) {
    const log = await fs.readFile(path.join(f.identities.get(component.id).directory, 'sharedbuild-output/build.log'), 'utf8');
    assert.equal((log.match(/FIXTURE_PRODUCER_EXECUTED/g) || []).length, 1, component.id);
  }
});
test('failed producer preserves actual rc and never publishes or starts dependents', async () => {
  const f = await fixture(); const runtime = f.plan.components.find(value => value.id === 'runtime');
  runtime.config.options.parameters.mode = 'fail'; const identities = buildIdentities(f.plan);
  const result = await invoke(f); observed(result, 'producer-failure'); assert.notEqual(result.rc, 0); assert.match(result.stderr, /BUILD_FAILED rc=17/);
  const state = await readJson(path.join(identities.get('runtime').directory, 'state.json')); assert.equal(state.status, 'failed');
  assert.equal(state.rc, 17);
  await assert.rejects(fs.access(path.join(identities.get('runtime').directory, 'DONE'))); await assert.rejects(fs.access(path.join(identities.get('std').directory, 'state.json')));
  await assert.rejects(fs.access(f.out));
});

test('explicit same-input incremental recovery preserves failure evidence and publishes only after success', async () => {
  const f = await fixture(); f.plan.components.find(component => component.id === 'runtime').config.options.parameters.mode = 'runtime-fail-once';
  const identity = buildIdentities(f.plan).get('runtime'), planSha = objectId(f.plan);
  const failed = await invoke(f); observed(failed, 'same-input-failure'); assert.notEqual(failed.rc, 0); assert.match(failed.stderr, /BUILD_FAILED rc=17/);
  const statePath = path.join(identity.directory, 'state.json'), failedState = await fs.readFile(statePath);
  assert.equal(JSON.parse(failedState).rc, 17); await assert.rejects(fs.access(f.out));
  await assert.rejects(fs.access(path.join(identity.directory, 'DONE')));
  const denied = await invoke(f); observed(denied, 'implicit-retry-refused'); assert.notEqual(denied.rc, 0);
  assert.match(denied.stderr, /rule=PRODUCER_PREVIOUS_FAILURE component=runtime/);
  assert.deepEqual(await fs.readFile(statePath), failedState);
  const restored = await invoke(f, ['--resume-failed']); observed(restored, 'same-input-recovery'); assert.equal(restored.rc, 0, restored.stderr);
  assert.equal(objectId(f.plan), planSha); assert.equal((await readJson(statePath)).buildId, identity.buildId);
  assert.equal((await readJson(statePath)).status, 'complete');
  const recovery = (await fs.readdir(path.join(identity.directory, 'logs'))).find(name => name.startsWith('recovery-'));
  assert.ok(recovery); assert.deepEqual(await fs.readFile(path.join(identity.directory, 'logs', recovery, 'state.json')), failedState);
  const receipt = await readJson(path.join(identity.directory, 'output.json'));
  const events = await fs.readdir(path.join(receipt.execution.actualWork, 'logs'));
  assert.ok(events.some(name => name.startsWith('failed-')), 'native original failure directory must survive explicit recovery');
  assert.equal(receipt.rc, 0); assert.equal(receipt.execution.rc, 0);
});

async function resealFixtureRecord(directory, record) {
  await atomicJson(path.join(directory, 'output.json'), record);
  await fs.writeFile(path.join(directory, 'DONE'), `${await fileDigest(path.join(directory, 'output.json'))}\n`);
}
test('wrong compiler std reaches the existing installed compiler lineage guard and recovers', async () => {
  const f = await fixture(); const good = await invoke(f); assert.equal(good.rc, 0, good.stderr);
  const directory = f.identities.get('std').directory;
  const file = path.join(directory, 'artifacts/std-producer.json'), bytes = await fs.readFile(file);
  const record = await readJson(path.join(directory, 'output.json'));
  await atomicJson(file, {compiler_sha256: 'e'.repeat(64)});
  record.files['std-producer.json'].sha256 = await fileDigest(file);
  record.files['std-producer.json'].size = (await fs.stat(file)).size;
  await resealFixtureRecord(directory, record);
  f.out = path.join(f.root, 'wrong-std'); const wrong = await invoke(f); observed(wrong, 'std-wrong-compiler');
  assert.notEqual(wrong.rc, 0); assert.match(wrong.stderr, /rule=STD_CJC.*on-disk cjc/);
  await assert.rejects(fs.access(f.out));
  await fs.writeFile(file, bytes); record.files['std-producer.json'].sha256 = await fileDigest(file);
  record.files['std-producer.json'].size = bytes.length; await resealFixtureRecord(directory, record);
  const restored = await invoke(f); observed(restored, 'std-compiler-restored'); assert.equal(restored.rc, 0, restored.stderr);
});
test('forged actual source completion rejects before consuming artifacts', async () => {
  const f = await fixture(); assert.equal((await invoke(f)).rc, 0);
  const directory = f.identities.get('runtime').directory, record = await readJson(path.join(directory, 'output.json'));
  const original = clone(record); record.execution.source.commit = f.sources.compiler.commit;
  await resealFixtureRecord(directory, record);
  f.out = path.join(f.root, 'forged-source'); const wrong = await invoke(f); observed(wrong, 'forged-actual-source');
  assert.notEqual(wrong.rc, 0); assert.match(wrong.stderr, /rule=SOURCE_COMPLETION component=runtime/);
  await assert.rejects(fs.access(f.out));
  await resealFixtureRecord(directory, original); const restored = await invoke(f); observed(restored, 'source-restored'); assert.equal(restored.rc, 0, restored.stderr);
});
test('duplicate destinations and a source directory symlink never publish an SDK', async () => {
  const f = await fixture(); assert.equal((await invoke(f)).rc, 0);
  const original = clone(f.plan); f.out = path.join(f.root, 'duplicate-sdk');
  f.plan.components.find(value => value.id === 'compiler').install.push({from: 'cjcj-stage1', to: 'bin/cjcj-stage1'});
  const duplicate = await invoke(f); observed(duplicate, 'duplicate-install');
  assert.notEqual(duplicate.rc, 0); assert.match(duplicate.stderr, /rule=DUPLICATE_INSTALL component=compiler/);
  await assert.rejects(fs.access(f.out));
  f.plan = original;
  const artifacts = path.join(f.identities.get('runtime').directory, 'artifacts'), saved = `${artifacts}-saved`;
  await fs.rename(artifacts, saved); await fs.symlink(saved, artifacts);
  f.out = path.join(f.root, 'symlink-sdk'); const escaped = await invoke(f); observed(escaped, 'source-root-link');
  assert.notEqual(escaped.rc, 0); assert.match(escaped.stderr, /rule=LINK_ESCAPE component=runtime/);
  await assert.rejects(fs.access(f.out));
  await fs.unlink(artifacts); await fs.rename(saved, artifacts);
  const restored = await invoke(f); observed(restored, 'source-link-restored'); assert.equal(restored.rc, 0, restored.stderr);
});
test('different frozen configurations sharing a request hint cannot overwrite producer requests', async () => {
  const f = await fixture(), other = clone(f.plan);
  other.components.find(value => value.id === 'runtime').config.options.parameters.mode = 'fail';
  const secondPlan = path.join(f.root, 'other-plan.json'); await atomicJson(secondPlan, other);
  const [normal, failed] = await Promise.all([invoke(f), command([process.execPath, product, '--plan', secondPlan, '--out', path.join(f.root, 'sdk-failed')])]);
  observed(normal, 'different-config-normal'); observed(failed, 'different-config-failure');
  assert.equal(normal.rc, 0, normal.stderr); assert.notEqual(failed.rc, 0); assert.match(failed.stderr, /BUILD_FAILED rc=17/);
  const second = buildIdentities(other).get('runtime').directory;
  assert.notEqual(second, f.identities.get('runtime').directory);
  assert.equal((await readJson(path.join(second, 'sharedbuild-request.json'))).parameters.mode, 'fail');
  assert.equal((await readJson(path.join(f.identities.get('runtime').directory, 'sharedbuild-request.json'))).parameters.mode, 'runtime');
});
test('a collected success cache restores the same completed work without rerunning its producer', async () => {
  const f = await fixture(); assert.equal((await invoke(f)).rc, 0);
  const directory = f.identities.get('runtime').directory, record = await readJson(path.join(directory, 'output.json'));
  const work = record.execution.actualWork, logBefore = await fs.readdir(path.join(work, 'logs'));
  await fs.rename(directory, `${directory}-collected`);
  await fs.rename(path.join(f.plan.buildRoot, 'shared-cache', record.execution.producerBuildId), path.join(f.root, 'collected-shared-cache'));
  f.out = path.join(f.root, 'sdk-restored-cache'); const restored = await invoke(f); observed(restored, 'completed-work-recovery');
  assert.equal(restored.rc, 0, restored.stderr);
  assert.deepEqual(await fs.readdir(path.join(work, 'logs')), logBefore);
  assert.equal((await readJson(path.join(directory, 'output.json'))).execution.actualWork, work);
});

test('transported receipts retain original build origin and frozen digest without source copies or producers', async () => {
  const f = await fixture(); const initial = await invoke(f); assert.equal(initial.rc, 0, initial.stderr);
  const originalRoot = f.plan.buildRoot, records = {};
  for (const component of f.plan.components) {
    const original = f.identities.get(component.id).directory, destination = path.join(f.root, 'received', component.id);
    await fs.mkdir(destination, {recursive: true});
    await fs.cp(path.join(original, 'artifacts'), path.join(destination, 'artifacts'),
      {recursive: true, dereference: false, verbatimSymlinks: true});
    for (const name of ['output.json', 'DONE']) await fs.copyFile(path.join(original, name), path.join(destination, name));
    records[component.id] = await fs.readFile(path.join(destination, 'output.json'));
    Object.assign(component.producer, {receipt: destination, originBuildRoot: originalRoot,
      receiptSha256: await fileDigest(path.join(destination, 'output.json'))});
  }
  f.plan.buildRoot = path.join(f.root, 'consumer-build-root'); f.out = path.join(f.root, 'sdk-transported');
  const transported = await invoke(f); observed(transported, 'transported-receipts'); assert.equal(transported.rc, 0, transported.stderr);
  const manifest = await readJson(path.join(f.out, 'SDK.manifest.json'));
  for (const component of f.plan.components) {
    assert.equal(manifest.components[component.id].originDirectory, f.identities.get(component.id).directory);
    assert.equal(manifest.components[component.id].buildId, f.identities.get(component.id).buildId);
    assert.deepEqual(await fs.readFile(path.join(component.producer.receipt, 'output.json')), records[component.id]);
    await assert.rejects(fs.access(buildIdentities(f.plan).get(component.id).directory));
  }
  // Top-level hashes and payload rows can agree while a non-runtime producer
  // receipt differs from the one frozen before assembly. Reuse must compare
  // the actual source closure, not just internally consistent installation.
  const plans = path.join(f.root, 'transported-phases.json');
  const phases = Object.fromEntries(BOOTSTRAP_PHASES
    .map(phase => [phase, {...clone(f.plan),
      role: ['stage0', 'stage0-run', 'std-bootstrap'].includes(phase) ? 'host' : 'target',
      stage: phase === 'stage3' ? 'final' : ['stage2', 'stage3-std'].includes(phase) ? 'stage2' : f.plan.stage}]));
  await atomicJson(plans, {schema: 'bootstrap-sdk-plans-v1', phases});
  const manifestPath = path.join(f.out, 'SDK.manifest.json'), lockPath = path.join(f.out, 'SDK.lock.json');
  const manifestBytes = await fs.readFile(manifestPath), lockBytes = await fs.readFile(lockPath);
  const changedManifest = JSON.parse(manifestBytes), changedLock = JSON.parse(lockBytes);
  changedManifest.components.compiler.receiptSha256 = 'e'.repeat(64);
  for (const [rel, file] of Object.entries(changedManifest.files)) if (file.component === 'compiler') {
    file.receiptSha256 = 'e'.repeat(64); changedLock.files[rel].producer.receipt_sha256 = file.receiptSha256;
  }
  await atomicJson(manifestPath, changedManifest);
  changedLock.manifest_sha256 = objectId(changedManifest);
  changedLock.files['SDK.manifest.json'].sha256 = await fileDigest(manifestPath);
  await atomicJson(lockPath, changedLock);
  const reuseArgs = [process.execPath, path.join(here, 'bootstrap-sdk.mjs'), '--plans', plans,
    '--phase', 'stage1-initial', '--out', f.out];
  const wrongOrigin = await command(reuseArgs); observed(wrongOrigin, 'phase-frozen-receipt');
  assert.notEqual(wrongOrigin.rc, 0); assert.match(wrongOrigin.stderr, /rule=RESOLVED_IDENTITY component=compiler/);
  await fs.writeFile(manifestPath, manifestBytes); await fs.writeFile(lockPath, lockBytes);
  const recovered = await command(reuseArgs); observed(recovered, 'phase-receipt-restored'); assert.equal(recovered.rc, 0, recovered.stderr);
  const moduleRel = `modules/${tuple}/std/core/core.Int64.ti`, modulePath = path.join(f.out, moduleRel);
  const originalModule = await fs.readFile(modulePath), substitutedModule = Buffer.from(originalModule);
  substitutedModule[0] ^= 1; await fs.writeFile(modulePath, substitutedModule);
  const rewrittenManifest = JSON.parse(manifestBytes), rewrittenLock = JSON.parse(lockBytes);
  rewrittenManifest.files[moduleRel].sha256 = await fileDigest(modulePath);
  rewrittenLock.files[moduleRel].sha256 = rewrittenManifest.files[moduleRel].sha256;
  await atomicJson(manifestPath, rewrittenManifest);
  rewrittenLock.manifest_sha256 = objectId(rewrittenManifest);
  rewrittenLock.files['SDK.manifest.json'].sha256 = await fileDigest(manifestPath);
  await atomicJson(lockPath, rewrittenLock);
  const rewrittenInventory = await command(reuseArgs); observed(rewrittenInventory, 'phase-original-inventory');
  assert.notEqual(rewrittenInventory.rc, 0); assert.match(rewrittenInventory.stderr, /rule=RESOLVED_PAYLOAD component=std.*core.Int64.ti/);
  await fs.writeFile(modulePath, originalModule); await fs.writeFile(manifestPath, manifestBytes); await fs.writeFile(lockPath, lockBytes);
  const inventoryRestored = await command(reuseArgs); observed(inventoryRestored, 'phase-inventory-restored'); assert.equal(inventoryRestored.rc, 0, inventoryRestored.stderr);
  f.plan.components.find(value => value.id === 'runtime').producer.receiptSha256 = 'e'.repeat(64);
  f.out = path.join(f.root, 'wrong-receipt-sdk'); const changed = await invoke(f); observed(changed, 'receipt-digest');
  assert.notEqual(changed.rc, 0); assert.match(changed.stderr, /rule=COMPLETION component=runtime/);
});

test('bootstrap phase reuse binds installed plan and manifest before returning an existing SDK', async () => {
  const f = await fixture(); const initial = await invoke(f); assert.equal(initial.rc, 0, initial.stderr);
  const plans = path.join(f.root, 'phases.json');
  const phases = Object.fromEntries(BOOTSTRAP_PHASES
    .map(phase => [phase, {...clone(f.plan),
      role: ['stage0', 'stage0-run', 'std-bootstrap'].includes(phase) ? 'host' : 'target',
      stage: phase === 'stage3' ? 'final' : ['stage2', 'stage3-std'].includes(phase) ? 'stage2' : f.plan.stage}]));
  await atomicJson(plans, {schema: 'bootstrap-sdk-plans-v1', phases});
  const argv = [process.execPath, path.join(here, 'bootstrap-sdk.mjs'), '--plans', plans,
    '--phase', 'stage1-initial', '--out', f.out];
  const completeBundle = await fs.readFile(plans);
  await atomicJson(plans, {schema: 'bootstrap-sdk-plans-v1', phases: {'stage1-initial': f.plan}});
  const incomplete = await command(argv); observed(incomplete, 'phase-complete-bundle');
  assert.notEqual(incomplete.rc, 0); assert.match(incomplete.stderr, /rule=BOOTSTRAP_PHASES component=bundle/);
  await fs.writeFile(plans, completeBundle);
  phases.stage3.stage = 'stage1';
  await atomicJson(plans, {schema: 'bootstrap-sdk-plans-v1', phases});
  const wrongStage = await command(argv); observed(wrongStage, 'phase-final-qualification');
  assert.notEqual(wrongStage.rc, 0); assert.match(wrongStage.stderr, /rule=BOOTSTRAP_PHASES component=stage3/);
  await fs.writeFile(plans, completeBundle);
  const normal = await command(argv); observed(normal, 'phase-reuse'); assert.equal(normal.rc, 0, normal.stderr);
  assert.equal(JSON.parse(normal.stdout.trim().split('\n').at(-1)).reused, true);
  const phaseDirectory = path.join(f.root, 'phase-directory'); await fs.mkdir(phaseDirectory);
  const directoryArgv = [...argv]; directoryArgv[directoryArgv.indexOf('--plans') + 1] = phaseDirectory;
  for (const [name, frozen] of Object.entries(JSON.parse(completeBundle).phases)) await atomicJson(path.join(phaseDirectory, `${name}.json`), frozen);
  await fs.rm(path.join(phaseDirectory, 'stage3.json'));
  const missingFile = await command(directoryArgv); observed(missingFile, 'phase-directory-completeness');
  assert.notEqual(missingFile.rc, 0); assert.match(missingFile.stderr, /rule=BOOTSTRAP_PHASES component=stage3/);
  await atomicJson(path.join(phaseDirectory, 'stage3.json'), JSON.parse(completeBundle).phases.stage3);
  const directoryRestored = await command(directoryArgv); observed(directoryRestored, 'phase-directory-restored');
  assert.equal(directoryRestored.rc, 0, directoryRestored.stderr);
  const installedPlan = path.join(f.out, 'SDK.plan.json'), original = await fs.readFile(installedPlan);
  const changed = JSON.parse(original); changed.lane = 'another-owner'; await atomicJson(installedPlan, changed);
  const rejected = await command(argv); observed(rejected, 'phase-plan-binding');
  assert.notEqual(rejected.rc, 0); assert.match(rejected.stderr, /rule=INSTALL_BINDING component=sdk/);
  await fs.writeFile(installedPlan, original);
  const restored = await command(argv); observed(restored, 'phase-plan-restored'); assert.equal(restored.rc, 0, restored.stderr);
  const module = path.join(f.out, `modules/${tuple}/std/core/core.Int64.ti`);
  const moduleBytes = await fs.readFile(module), lockPath = path.join(f.out, 'SDK.lock.json');
  const lockBytes = await fs.readFile(lockPath), lock = JSON.parse(lockBytes);
  const changedModule = Buffer.from(moduleBytes); changedModule[0] ^= 1; await fs.writeFile(module, changedModule);
  lock.files[`modules/${tuple}/std/core/core.Int64.ti`].sha256 = await fileDigest(module);
  await atomicJson(lockPath, lock);
  const rewritten = await command(argv); observed(rewritten, 'phase-lock-rewrite');
  assert.notEqual(rewritten.rc, 0); assert.match(rewritten.stderr, /rule=MANIFEST_BINDING/);
  await fs.writeFile(module, moduleBytes); await fs.writeFile(lockPath, lockBytes);
  const recovered = await command(argv); observed(recovered, 'phase-lock-restored'); assert.equal(recovered.rc, 0, recovered.stderr);
});

test('registered source transformation accepts only the precomputed bytes and exact tracked change', async () => {
  const root = await fs.mkdtemp(path.join(testRoot, 'source-transform-'));
  const expected = await sourceRepository(root, 'source'), rel = 'identity.txt', file = path.join(expected.repo, rel);
  const original = await fs.readFile(file), transformed = Buffer.from('registered package mapping\n');
  const changes = {[rel]: {sha256: objectId('unused'), mode: (await fs.stat(file)).mode & 0o777}};
  await fs.writeFile(file, transformed); changes[rel].sha256 = await fileDigest(file);
  await assert.rejects(sourceIdentity(expected.repo, expected, 'ast-flatbuffers'), /rule=SOURCE_CHECKOUT/);
  const actual = await registeredSourceIdentity(expected.repo, expected, 'ast-flatbuffers', changes);
  console.log(`TARGET_ASSERTION_EXECUTED source-registered status=${JSON.stringify(actual.status)}`);
  assert.equal(actual.registeredChanges[rel].sha256, changes[rel].sha256);
  await fs.appendFile(file, 'undeclared modification\n');
  await assert.rejects(registeredSourceIdentity(expected.repo, expected, 'ast-flatbuffers', changes), /rule=SOURCE_TRANSFORM component=ast-flatbuffers.*registered result differs/);
  console.log('TARGET_ASSERTION_EXECUTED source-transform-bytes rejected');
  await fs.writeFile(file, transformed); await fs.writeFile(path.join(expected.repo, 'undeclared.txt'), 'extra');
  await assert.rejects(registeredSourceIdentity(expected.repo, expected, 'ast-flatbuffers', changes), /rule=SOURCE_TRANSFORM component=ast-flatbuffers.*unexpected source changes/);
  console.log('TARGET_ASSERTION_EXECUTED source-transform-extra rejected');
  await fs.rm(path.join(expected.repo, 'undeclared.txt'));
  const restored = await registeredSourceIdentity(expected.repo, expected, 'ast-flatbuffers', changes);
  assert.equal(restored.tree, expected.tree); console.log('TARGET_ASSERTION_EXECUTED source-transform-restored accepted');
  await fs.writeFile(file, original); await sourceIdentity(expected.repo, expected, 'ast-flatbuffers');
});

test('complete bootstrap intent freezer binds all eight phases and rejects an omitted phase before production', async () => {
  const f = await fixture();
  const phases = Object.fromEntries(BOOTSTRAP_PHASES
    .map(phase => [phase, {...clone(f.plan), schema: 'toolchain-sdk-intent-v1',
      role: ['stage0', 'stage0-run', 'std-bootstrap'].includes(phase) ? 'host' : 'target',
      stage: phase === 'stage3' ? 'final' : ['stage2', 'stage3-std'].includes(phase) ? 'stage2' : f.plan.stage}]));
  const intent = path.join(f.root, 'bundle.intent.json'), bundle = path.join(f.root, 'bundle.frozen.json');
  await atomicJson(intent, {schema: 'bootstrap-sdk-intents-v1', phases});
  await atomicJson(path.join(f.root, 'phase-observation.json'), {intent, plan: f.plan,
    expected: Object.fromEntries(f.identities)});
  const argv = [process.execPath, path.join(here, 'prepare-bootstrap-plans.mjs'), '--intents', intent, '--out', bundle];
  const frozen = await command(argv); observed(frozen, 'freeze-eight-phases'); assert.equal(frozen.rc, 0, frozen.stderr);
  const result = await readJson(bundle); assert.equal(Object.keys(result.phases).length, 8);
  for (const plan of Object.values(result.phases)) {
    validatePlan(plan); assert.equal(plan.components.find(component => component.id === 'runtime').source.commit, f.sources.runtime.commit);
  }
  const dry = await command([process.execPath, path.join(here, 'bootstrap-sdk.mjs'), '--plans', bundle,
    '--phase', 'stage1-initial', '--out', f.out, '--dry-run']);
  observed(dry, 'frozen-bundle-real-phase-entry'); assert.equal(dry.rc, 0, dry.stderr);
  await assert.rejects(fs.access(f.plan.buildRoot)); await assert.rejects(fs.access(f.out));
  delete phases.stage3; await atomicJson(intent, {schema: 'bootstrap-sdk-intents-v1', phases});
  argv[argv.length - 1] = path.join(f.root, 'incomplete.frozen.json');
  const incomplete = await command(argv); observed(incomplete, 'freeze-missing-phase');
  assert.notEqual(incomplete.rc, 0); assert.match(incomplete.stderr, /rule=BOOTSTRAP_PHASES component=intent/);
  await assert.rejects(fs.access(argv.at(-1)));
});

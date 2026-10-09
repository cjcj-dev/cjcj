#!/usr/bin/env zx
import assert from 'node:assert/strict';
import fs from 'node:fs/promises';
import path from 'node:path';
import {createHash} from 'node:crypto';
import {spawnSync, spawn} from 'node:child_process';
import test from 'node:test';
import {preserveCall, diagnose} from './producer-evidence.mjs';
import {load as loadYaml} from './vendor/js-yaml/js-yaml.mjs';
import {zxCommand} from './test-zx.mjs';

const repo = path.resolve(import.meta.dirname, '..');
const suiteRoot = process.env.PRODUCER_EVIDENCE_TEST_ROOT;
if (!suiteRoot) throw new Error('PRODUCER_EVIDENCE_TEST_ROOT must be a lane-owned persistent directory');
await fs.mkdir(suiteRoot, {recursive: true});
const fixtureElf = path.join(suiteRoot, 'controlled-producer');
const compiled = spawnSync('cc', ['-g', '-O0', '-o', fixtureElf, path.join(repo, 'ci/producer-evidence.fixture.c')], {encoding: 'utf8'});
await fs.writeFile(path.join(suiteRoot, 'fixture-build.json'), JSON.stringify({argv: ['cc', '-g', '-O0', '-o', fixtureElf, path.join(repo, 'ci/producer-evidence.fixture.c')], rc: compiled.status, stderr: compiled.stderr}));
assert.equal(compiled.status, 0, compiled.stderr);
const digest = async file => createHash('sha256').update(await fs.readFile(file)).digest('hex');
console.log(`APPARATUS_ID helper=${await digest(path.join(repo, 'ci/producer-evidence.mjs'))} smoke=${await digest(path.join(repo, 'ci/smoke/run_smoke.mjs'))} package=${await digest(path.join(repo, 'scripts/objc_preamble_unit.py'))} toy_elf=${await digest(fixtureElf)}`);

async function setup(name) {
  const root = await fs.mkdtemp(path.join(suiteRoot, `${name}-`));
  const sdk = path.join(root, 'sdk'); const tree = path.join(root, 'tree');
  for (const file of ['bin/cjc', 'tools/bin/cjpm', 'tools/lib/placeholder.so',
    'modules/linux_x86_64_cjnative/std/std.core.cjo', 'modules/linux_x86_64_cjnative/std.core.cjo',
    'lib/linux_x86_64_cjnative/libcangjie-std-core.a',
    'runtime/lib/linux_x86_64_cjnative/libcangjie-runtime.so',
    'runtime/lib/linux_x86_64_cjnative/libboundscheck.so', 'third_party/llvm/lib/libLLVM-15.so']) {
    await fs.mkdir(path.dirname(path.join(sdk, file)), {recursive: true}); await fs.writeFile(path.join(sdk, file), `controlled ${file}`);
  }
  await fs.mkdir(path.join(tree, 'ci'), {recursive: true}); await fs.mkdir(path.join(tree, 'scripts'), {recursive: true});
  await fs.copyFile(path.join(repo, 'ci/producer-evidence.mjs'), path.join(tree, 'ci/producer-evidence.mjs'));
  await fs.copyFile(path.join(repo, 'scripts/objc_preamble_unit.py'), path.join(tree, 'scripts/objc_preamble_unit.py'));
  await fs.cp(path.join(repo, 'scripts/objc_regcomp_fixtures'), path.join(tree, 'scripts/objc_regcomp_fixtures'), {recursive: true});
  await fs.mkdir(path.join(tree, 'runtime_shim')); await fs.writeFile(path.join(tree, 'runtime_shim/cjselfhost_llvmshim.o'), 'controlled shim');
  for (const args of [['init', '-q'], ['add', '.'], ['-c', 'user.name=Zxilly', '-c', 'user.email=zxilly@outlook.com', 'commit', '-qm', 'controlled fixture']])
    assert.equal(spawnSync('git', args, {cwd: tree}).status, 0);
  await fs.writeFile(path.join(tree, 'dirty-build.txt'), 'actual dirty declaration');
  const producer = path.join(root, 'producer'); await fs.copyFile(fixtureElf, producer);
  const trace = path.join(root, 'invocations.txt');
  const env = {...process.env, CANGJIE_HOME: sdk, EVIDENCE_TEST_TRACE: trace,
    CJCJ_EVIDENCE_BUILD_STAMP: 'controlled-source-dirty', GITHUB_RUN_ID: 'qualification',
    GITHUB_RUN_ATTEMPT: '2', GITHUB_JOB: 'qualification', SECRET_TOKEN: 'must-not-be-saved'};
  delete env.CJCJ_DIAGNOSTIC_CALL; delete env.CJCJ_EVIDENCE_EXPECTED_SHA256; delete env.CJCJ_EVIDENCE_ROOT;
  return {root, sdk, tree, producer, trace, env};
}

async function calls(root) {
  const found = [];
  async function walk(dir) {
    for (const item of await fs.readdir(dir, {withFileTypes: true}).catch(() => [])) {
      const file = path.join(dir, item.name);
      if (item.isDirectory()) await walk(file);
      else if (item.name === 'call.json') found.push({file, ...JSON.parse(await fs.readFile(file))});
    }
  }
  await walk(root); return found;
}
async function packageRun(fixture, extra = {}) {
  const out = path.join(fixture.root, 'package');
  const args = [path.join(fixture.tree, 'scripts/objc_preamble_unit.py'), '--prepare-only', '--build-tree', fixture.tree,
    '--sdk', fixture.sdk, '--producer', fixture.producer, '--out', out];
  const result = spawnSync('python3', args, {cwd: fixture.tree, env: {...fixture.env, ...extra}, encoding: 'utf8', timeout: 20_000});
  await fs.writeFile(path.join(fixture.root, 'package-execution.json'), JSON.stringify({argv: ['python3', ...args], parent_rc: result.status, signal: result.signal, stdout: result.stdout, stderr: result.stderr}, null, 2));
  return {result, out, fixture: JSON.parse(await fs.readFile(path.join(out, 'fixture.json'))), calls: await calls(out)};
}
async function smokeRun(fixture, extra = {}) {
  const work = path.join(fixture.root, 'smoke');
  const command = zxCommand([path.join(repo, 'ci/smoke/run_smoke.mjs'), fixture.producer, work]);
  const result = spawnSync(command[0], command.slice(1),
    {cwd: fixture.tree, env: {...fixture.env, ...extra}, encoding: 'utf8', timeout: 30_000});
  await fs.writeFile(path.join(fixture.root, 'smoke-execution.json'), JSON.stringify({parent_rc: result.status, signal: result.signal, stdout: result.stdout, stderr: result.stderr}, null, 2));
  return {result, work, calls: await calls(work)};
}
function target(name, actual) { console.log(`TARGET_ASSERT_EXECUTED ${name} ${JSON.stringify(actual)}`); }

test('package real entry preserves entities, exact invocation and dirty identity', async () => {
  const f = await setup('package-green'); const r = await packageRun(f);
  target('package_prelaunch_entities', {parent: r.result.status, calls: r.calls.length});
  assert.equal(r.result.status, 0, r.result.stderr); assert.equal(r.calls.length, 2);
  for (const call of r.calls) {
    assert.equal(call.producer.sha256, await digest(f.producer));
    assert.equal(await digest(call.producer.saved), call.producer.sha256);
    // FileUtil.FindSerializationFile first checks std/std.core.cjo, then std.core.cjo.
    for (const relative of ['std/std.core.cjo', 'std.core.cjo']) {
      const declaration = call.inputs.find(input => input.path === path.join(f.sdk, 'modules/linux_x86_64_cjnative', relative));
      target('required_input_entities', {name: call.name, relative, declaration});
      assert.ok(declaration?.saved, 'target SDK default std.core declaration entity');
      assert.equal(await digest(declaration.saved), await digest(declaration.path));
    }
    assert.ok(call.inputs.every(input => input.saved));
    assert.match(call.source.dirty.value, /dirty-build.txt/); assert.equal(call.declared_build_stamp, 'controlled-source-dirty');
    assert.equal(call.env.SECRET_TOKEN, undefined); assert.equal(JSON.stringify(call).includes('must-not-be-saved'), false);
    target('exact_invocation', {name: call.name, argv0: call.argv0, argv: call.argv});
    assert.deepEqual([call.argv0, ...call.argv], r.fixture.stubs[call.name].argv, 'target exact original argv');
    assert.equal(call.cwd, r.out); assert.equal(call.child_rc, 0);
  }
  const trace = await fs.readFile(f.trace, 'utf8'); assert.equal((trace.match(/argv0=/g) || []).length, 2);
  const workflow = loadYaml(await fs.readFile(path.join(repo, '.github/workflows/ci.yml'), 'utf8'));
  const upload = workflow.jobs['package-tests'].steps.find(step => step.name === 'Preserve Cangjie test results');
  assert.equal(upload.if, 'always()');
  assert.equal(upload.with['include-hidden-files'], true);
  assert.equal(upload.with['if-no-files-found'], 'warn');
  // Resolve the actual produced fixture files against the configured upload
  // roots, rather than accepting a hash/summary-only glob as entity coverage.
  const roots = upload.with.path.split('\n').map(line => line.trim())
    .filter(Boolean).map(line => line.replace('${{ runner.temp }}/package-tests/objc-fixture', r.out));
  const retained = [path.join(r.out, 'fixture.json'),
    ...Object.values(r.fixture.stubs).flatMap(stub => [stub.log, stub.summary_path]),
    ...r.calls.flatMap(call => [call.file, call.producer.saved, ...call.inputs.map(input => input.saved)])];
  for (const file of retained) {
    assert.ok((await fs.stat(file)).isFile(), `actual retained file missing: ${file}`);
    assert.ok(roots.some(root => file === root || (!root.includes('*') && file.startsWith(root + path.sep))),
      `target upload covers actual producer entity: ${file}`);
  }
  target('workflow_entity_upload_coverage', {files: retained.length});
});

test('entities survive deletion by the first launched producer', async () => {
  const f = await setup('prelaunch'); const source = path.join(f.root, 'input.cj'); await fs.writeFile(source, 'actual input');
  const root = path.join(f.root, 'evidence');
  const args = [path.join(repo, 'ci/producer-evidence.mjs'), '--role', 'package', '--name', 'internal', '--source-tree', f.tree, '--root', root, '--inputs', '[]', '--', f.producer, source];
  const result = spawnSync('node', args, {cwd: f.tree, env: {...f.env, EVIDENCE_TEST_MODE: 'unlink'}, encoding: 'utf8'});
  const [call] = await calls(root); target('prelaunch_survives_unlink', {rc: result.status, state: call?.state});
  assert.equal(result.status, 0, result.stderr); assert.equal(call.state, 'EXITED');
  assert.equal(await fs.stat(f.producer).then(() => true, () => false), false);
  assert.equal(await fs.stat(source).then(() => true, () => false), false);
  assert.equal(await digest(call.producer.saved), call.producer.sha256);
  const input = call.inputs.find(item => item.path === source); assert.equal(await fs.readFile(input.saved, 'utf8'), 'actual input');
});

test('package identity mismatch stops before the producer and lang', async () => {
  const f = await setup('wrong-id'); const r = await packageRun(f, {CJCJ_EVIDENCE_EXPECTED_SHA256: '0'.repeat(64)});
  target('wrong_producer_rejected', {parent: r.result.status, state: r.calls[0]?.state, rc: r.fixture.rc});
  assert.equal(r.result.status, 1); assert.equal(r.fixture.rc, 74);
  assert.equal(r.calls[0]?.state, 'PRESERVATION_FAILED'); assert.match(r.calls[0].error, /identity mismatch/);
  assert.equal(await fs.stat(f.trace).then(() => true, () => false), false); assert.equal(r.fixture.stubs.lang, undefined);
});

test('package missing required entity stops before the producer', async () => {
  const f = await setup('missing-entity'); await fs.rm(path.join(f.sdk, 'tools/lib'), {recursive: true});
  const r = await packageRun(f); target('missing_entity_rejected', {parent: r.result.status, state: r.calls[0]?.state});
  assert.equal(r.result.status, 1); assert.equal(r.calls[0]?.state, 'PRESERVATION_FAILED');
  assert.match(r.calls[0].error, /missing SDK input/); assert.equal(r.fixture.stubs.lang, undefined);
  assert.equal(await fs.stat(f.trace).then(() => true, () => false), false);
});

test('package failed child remains distinct from prepare parent and workspace NOT_RUN', async () => {
  const f = await setup('failed-child'); const {runCangjie} = await import('./run-registered-tests.mjs');
  const keys = ['CANGJIE_HOME', 'OBJC_PREAMBLE_PRODUCER', 'EVIDENCE_TEST_MODE', 'EVIDENCE_TEST_TRACE'];
  const old = keys.map(key => process.env[key]);
  let result;
  try {
    Object.assign(process.env, {CANGJIE_HOME: f.sdk, OBJC_PREAMBLE_PRODUCER: f.producer, EVIDENCE_TEST_MODE: 'fail', EVIDENCE_TEST_TRACE: f.trace});
    const out = path.join(f.root, 'workspace'); await fs.mkdir(out);
    [result] = await runCangjie(f.tree, [], out);
  } finally { keys.forEach((key, i) => old[i] === undefined ? delete process.env[key] : process.env[key] = old[i]); }
  const saved = await calls(f.root); target('parent_child_workspace_separation', {child: saved[0]?.child_rc, prepare: result.preparation.rc, workspace: result.executed});
  assert.equal(saved[0]?.child_rc, 7); assert.equal(result.preparation.rc, 1); assert.equal(result.executed, false);
  assert.equal(result.fixture.stubs.lang, undefined); assert.equal(saved[0].debugger_rc, null);
});

test('smoke retains all six business outcomes and package/smoke identities remain isolated', async () => {
  const f = await setup('smoke-green'); const packaged = await packageRun(f);
  // A genuinely different producer entity for the smoke arm, not a relabelled package digest.
  await fs.appendFile(f.producer, 'distinct-smoke-build');
  const r = await smokeRun(f); target('smoke_six_and_isolation', {rc: r.result.status, calls: r.calls.length});
  assert.equal(r.result.status, 0, r.result.stdout + r.result.stderr); assert.match(r.result.stdout, /summary: pass=6 fail=0/);
  assert.equal(r.calls.length, 7, 'target smoke preserves every real compiler invocation'); assert.ok(r.calls.every(call => call.context.role === 'smoke'));
  assert.notEqual(r.calls[0].producer.sha256, packaged.calls[0].producer.sha256);
  assert.ok(r.calls.every(call => call.producer.saved !== packaged.calls[0].producer.saved));
  assert.ok(r.calls.every(call => call.argv.includes('--verbose')));
  const parent = JSON.parse(await fs.readFile(path.join(r.work, 'smoke-result.json')));
  assert.equal(parent.parent_rc, 0); assert.equal(parent.pass, 6); assert.equal(parent.fail, 0);
  const workflow = loadYaml(await fs.readFile(path.join(repo, '.github/workflows/ci.yml'), 'utf8'));
  const upload = workflow.jobs.build.steps.find(step => step.name === 'Preserve smoke producer evidence');
  const root = upload.with.path.replace('${{ runner.temp }}/smoke-tests', r.work);
  const covered = (file, uploadRoot) => file === uploadRoot || file.startsWith(uploadRoot + path.sep);
  const resultFile = path.join(r.work, 'smoke-result.json');
  assert.ok((await fs.stat(resultFile)).isFile());
  // Positive boundary control uses the real saved result, not a synthetic path.
  assert.ok(covered(resultFile, resultFile), 'target legal single-file smoke result upload');
  target('smoke_single_file_upload_passed', {file: resultFile});
  assert.ok(covered(resultFile, root), `target smoke result upload coverage: ${resultFile}`);
  target('smoke_result_upload_passed', {file: resultFile, root});
  for (const file of r.calls.flatMap(call => [call.producer.saved, ...call.inputs.map(input => input.saved), call.file])) {
    assert.ok((await fs.stat(file)).isFile());
    target('smoke_entity_upload_checked', {file, root, covered: covered(file, root)});
    assert.ok(covered(file, root), `target smoke upload covers actual entity: ${file}`);
  }
});

test('smoke records six independent failed compile calls while keeping six failures', async () => {
  const f = await setup('smoke-fail'); const r = await smokeRun(f, {EVIDENCE_TEST_MODE: 'fail'});
  target('smoke_failed_children', {parent: r.result.status, calls: r.calls.length});
  assert.equal(r.result.status, 1); assert.match(r.result.stdout, /summary: pass=0 fail=6/);
  assert.equal(r.calls.length, 6); assert.ok(r.calls.every(call => call.child_rc === 7));
  const parent = JSON.parse(await fs.readFile(path.join(r.work, 'smoke-result.json')));
  assert.equal(parent.parent_rc, 1); assert.ok(Object.values(parent.samples).every(sample => sample.run === 'NOT_RUN'));
});

test('smoke missing producer identity stops once and preserves remaining NOT_RUN', async () => {
  const f = await setup('smoke-wrong-id'); const r = await smokeRun(f, {CJCJ_EVIDENCE_EXPECTED_SHA256: '0'.repeat(64)});
  const parent = JSON.parse(await fs.readFile(path.join(r.work, 'smoke-result.json')));
  target('smoke_prerequisite_remaining_not_run', {parent: parent.parent_rc, calls: r.calls.length, samples: parent.samples});
  assert.equal(r.result.status, 74); assert.equal(parent.parent_rc, 74); assert.equal(r.calls.length, 1);
  assert.equal(r.calls[0].state, 'PRESERVATION_FAILED');
  assert.equal(parent.samples['02_generics'].compile, 'NOT_RUN'); assert.equal(parent.samples['01_hello'].run, 'NOT_RUN');
  assert.equal(await fs.stat(f.trace).then(() => true, () => false), false);
});

test('package debugger stops once at the first signal, preserving actual maps and mapped entities', async () => {
  const f = await setup('diagnostic'); const r = await packageRun(f, {EVIDENCE_TEST_MODE: 'signal', CJCJ_DIAGNOSTIC_CALL: 'package/internal'});
  const call = r.calls[0]; target('diagnostic_stop_not_final139', {parent: r.result.status, rc: r.fixture.rc, state: call?.state, missing: call?.missing});
  assert.equal(r.result.status, 1, r.result.stderr); assert.equal(r.fixture.rc, 70); assert.equal(call.state, 'DIAGNOSTIC_STOP');
  assert.equal(call.child_rc, null); assert.equal(call.debugger_rc, 0); assert.equal(call.timeout_rc, null);
  assert.match(call.first_signal.stop, /SIGSEGV/); assert.match(call.first_signal.si_code.response, /value=/);
  assert.match(call.first_signal.si_addr.response, /value=/); assert.match(call.first_signal.pc.response, /value=/);
  target('actual_loaded_entities', {count: call.loaded_entities.length});
  assert.ok(call.loaded_entities.length >= 3, 'target actual mapped ELF/SO/loader entities'); assert.ok(call.loaded_entities.every(item => item.origin.endsWith('/maps')));
  for (const entity of call.loaded_entities) assert.equal(await digest(entity.saved), entity.sha256);
  assert.match(await fs.readFile(path.join(path.dirname(call.file), 'maps.txt'), 'utf8'), /libc|ld-linux/);
  assert.equal((await fs.readFile(f.trace, 'utf8')).match(/argv0=/g).length, 1); assert.equal(r.fixture.stubs.lang, undefined);
  assert.match(await fs.readFile(f.trace, 'utf8'), new RegExp(`argv0=${r.fixture.argv[0]} argc=`));
});

test('smoke diagnostic selects only 04_iface_enum and leaves other five failures direct', async () => {
  const f = await setup('smoke-diagnostic'); const r = await smokeRun(f, {EVIDENCE_TEST_MODE: 'signal', CJCJ_DIAGNOSTIC_CALL: 'smoke/04_iface_enum'});
  target('smoke_single_debugger_selection', r.calls.map(call => [call.name, call.state, call.child_rc]));
  assert.equal(r.result.status, 1); assert.equal(r.calls.length, 6);
  assert.equal(r.calls.filter(call => call.diagnostic).length, 1);
  assert.equal(r.calls.find(call => call.name === '04_iface_enum').state, 'DIAGNOSTIC_STOP');
  assert.ok(r.calls.filter(call => call.name !== '04_iface_enum').every(call => call.child_rc === -11));
  assert.match(r.result.stdout, /name=04_iface_enum rc=70 signal=none/);
});

test('successful diagnostic compiler transcript still reaches the existing runtime mismatch assertion', async () => {
  const f = await setup('diagnostic-link-assertion');
  const r = await smokeRun(f, {CJCJ_DIAGNOSTIC_CALL: 'smoke/04_iface_enum',
    EVIDENCE_TEST_LINK_TEXT: `/usr/bin/ld -L${f.sdk}/lib/linux_x86_64_cjnative -L/controlled/patched-runtime -lcangjie-std-core`});
  const selected = r.calls.find(call => call.name === '04_iface_enum');
  target('diagnostic_transcript_runtime_assertion', {child: selected?.child_rc, debugger: selected?.debugger_rc, parent: r.result.status});
  assert.equal(selected?.child_rc, 0); assert.equal(selected?.debugger_rc, 0);
  assert.match(r.result.stdout, /name=04_iface_enum rc=86/,
    'target diagnostic transcript must reach existing runtime mismatch assertion');
  assert.match(r.result.stdout, /summary: pass=0 fail=6/); assert.equal(r.result.status, 1);
});

test('a handled signal remains a diagnostic stop instead of a claimed final crash', async () => {
  const f = await setup('handled'); const r = await packageRun(f, {EVIDENCE_TEST_MODE: 'handled', CJCJ_DIAGNOSTIC_CALL: 'package/internal'});
  const call = r.calls[0]; target('handled_signal_not_final_crash', {state: call?.state, child: call?.child_rc});
  assert.equal(call.state, 'DIAGNOSTIC_STOP'); assert.equal(call.child_rc, null); assert.equal(call.collector_rc, 70);
  assert.doesNotMatch(await fs.readFile(path.join(path.dirname(call.file), 'debugger.mi.log'), 'utf8'), /AFTER_SIGNAL/);
});

test('missing maps is explicitly incomplete evidence with the same real launched debugger', async t => {
  const f = await setup('missing-maps');
  const call = await preserveCall({command: [f.producer], cwd: f.tree,
    env: {...f.env, EVIDENCE_TEST_MODE: 'signal', CJCJ_DIAGNOSTIC_CALL: 'package/internal'},
    role: 'package', name: 'internal', root: path.join(f.root, 'evidence'), sourceTree: f.tree});
  const readFile = fs.readFile.bind(fs);
  t.mock.method(fs, 'readFile', (file, ...args) => {
    if (/^\/proc\/\d+\/maps$/.test(String(file))) return Promise.reject(Object.assign(new Error('controlled missing maps'), {code: 'ENOENT'}));
    return readFile(file, ...args);
  });
  const result = await diagnose(call);
  target('missing_maps_rejected', {rc: result.exitCode, state: call.record.state, missing: call.record.missing});
  assert.equal(result.exitCode, 74); assert.equal(call.record.state, 'DIAGNOSTIC_STOP');
  assert.ok(call.record.missing.some(item => item.observation === 'maps'));
  assert.equal(call.record.child_rc, null); assert.equal(call.record.debugger_rc, 0);
});

test('diagnostic timeout preserves separate child/debugger/timeout exits without rerun', async () => {
  const f = await setup('timeout'); const r = await packageRun(f, {EVIDENCE_TEST_MODE: 'wait', CJCJ_DIAGNOSTIC_CALL: 'package/internal', CJCJ_DIAGNOSTIC_TIMEOUT_MS: '300'});
  const call = r.calls[0]; target('diagnostic_timeout_separate', {state: call?.state, child: call?.child_rc, debugger: call?.debugger_rc, timeout: call?.timeout_rc});
  assert.equal(call.state, 'TIMEOUT'); assert.equal(call.timeout_rc, 124); assert.equal(call.child_rc, null);
  assert.equal(call.debugger_signal, 'SIGKILL'); assert.equal(r.fixture.rc, 124); assert.equal(r.fixture.stubs.lang, undefined);
});

test('invalid diagnostic timeout is recorded and rejected before debugger or child launch', async () => {
  const f = await setup('invalid-timeout'); const r = await packageRun(f, {CJCJ_DIAGNOSTIC_CALL: 'package/internal', CJCJ_DIAGNOSTIC_TIMEOUT_MS: '1'});
  target('invalid_diagnostic_timeout_rejected', {rc: r.fixture.rc, state: r.calls[0]?.state});
  assert.equal(r.fixture.rc, 74); assert.equal(r.calls[0]?.state, 'DIAGNOSTIC_REJECTED');
  assert.equal(r.calls[0].debugger_rc, null); assert.equal(r.calls[0].child_rc, null);
  assert.equal(await fs.stat(f.trace).then(() => true, () => false), false);
});

test('normal cancellation leaves a timely child record and distinct cancellation status', async () => {
  const f = await setup('cancel'); const root = path.join(f.root, 'evidence');
  const args = [path.join(repo, 'ci/producer-evidence.mjs'), '--role', 'package', '--name', 'internal', '--source-tree', f.tree, '--root', root, '--inputs', '[]', '--', f.producer];
  const child = spawn('node', args, {cwd: f.tree, env: {...f.env, EVIDENCE_TEST_MODE: 'wait'}, stdio: 'ignore'});
  let sent = false;
  for (let i = 0; i < 100; i++) {
    if (await fs.stat(f.trace).then(() => true, () => false)) { child.kill('SIGTERM'); sent = true; break; }
    await new Promise(resolve => setTimeout(resolve, 20));
  }
  const rc = await new Promise(resolve => child.on('close', (rc, signal) => resolve({rc, signal})));
  const [call] = await calls(root); target('normal_cancel_record', {sent, rc, state: call?.state});
  assert.ok(sent); assert.equal(call.state, 'CANCELLED'); assert.equal(call.cancellation_signal, 'SIGTERM');
  assert.equal(call.child_rc, -15); assert.equal(call.debugger_rc, null);
  const summary = JSON.parse(await fs.readFile(path.join(root, 'package-internal.result.json')));
  target('cancel_bridge_raw_rc', summary);
  assert.equal(summary.execution_rc, -15); assert.equal(summary.collector_rc, 143);
});

test('declaration search inventory includes cwd, CANGJIE_PATH and explicit import paths', async () => {
  const f = await setup('search-paths');
  const explicit = path.join(f.root, 'explicit'); const environment = path.join(f.root, 'environment');
  const required = [path.join(f.tree, 'local.cjo'), path.join(explicit, 'explicit.cjo'), path.join(environment, 'environment.cjo')];
  for (const file of required) { await fs.mkdir(path.dirname(file), {recursive: true}); await fs.writeFile(file, file); }
  const root = path.join(f.root, 'evidence');
  const args = [path.join(repo, 'ci/producer-evidence.mjs'), '--role', 'package', '--name', 'internal', '--source-tree', f.tree, '--root', root, '--', f.producer, '--import-path', explicit];
  const result = spawnSync('node', args, {cwd: f.tree, env: {...f.env, CANGJIE_PATH: environment}, encoding: 'utf8'});
  const [call] = await calls(root);
  target('consumer_search_declarations', {rc: result.status, paths: call?.inputs.map(input => input.path)});
  assert.equal(result.status, 0, result.stderr);
  for (const file of required) {
    const input = call.inputs.find(input => input.path === file);
    assert.ok(input?.saved, `target declaration search entity ${file}`);
    assert.equal(await digest(input.saved), await digest(file));
  }
});

test('prepare rejects stale successful summary when the current collector fails to start', async () => {
  const f = await setup('stale-summary'); const old = await packageRun(f);
  assert.equal(old.result.status, 0);
  const first = old.fixture.stubs.internal;
  await fs.copyFile(first.summary_path, path.join(old.out, 'producer-evidence/package-internal.result.json'));
  await fs.copyFile(old.fixture.stubs.lang.summary_path, path.join(old.out, 'producer-evidence/package-lang.result.json'));
  await fs.rm(path.join(f.tree, 'ci/producer-evidence.mjs'));
  const current = await packageRun(f);
  const stub = current.fixture.stubs.internal;
  target('stale_summary_rejected', {parent: current.result.status, collector: stub.collector_process_rc, child: stub.child_rc, summary: stub.summary, id: stub.invocation_id, old_id: first.invocation_id, lang: current.fixture.stubs.lang});
  assert.equal(current.result.status, 1, 'target prepare must reject a failed collector with old success in reused out');
  assert.equal(stub.collector_process_rc, 1); assert.equal(stub.child_rc, null); assert.equal(stub.summary, null);
  assert.notEqual(stub.invocation_id, first.invocation_id); assert.equal(current.fixture.stubs.lang, undefined);
  assert.equal((await fs.readFile(f.trace, 'utf8')).match(/argv0=/g).length, 2, 'only old successful children ran');
});

test('prepare rejects collector process failure even with a fresh successful child summary', async () => {
  const f = await setup('collector-failure');
  await fs.appendFile(path.join(f.tree, 'ci/producer-evidence.mjs'), '\nprocess.exitCode = 9;\n');
  const r = await packageRun(f); const stub = r.fixture.stubs.internal;
  target('collector_process_failure_rejected', {parent: r.result.status, collector: stub.collector_process_rc, child: stub.child_rc, summary: stub.summary});
  assert.equal(r.result.status, 1, 'target prepare must reject collector process rc despite successful child');
  assert.equal(stub.collector_process_rc, 9); assert.equal(stub.child_rc, 0); assert.equal(stub.summary.collector_rc, 0);
  assert.equal(stub.summary.invocation_id, stub.invocation_id); assert.equal(r.fixture.stubs.lang, undefined);
});

test('prepare rejects collector persistence failure after a real successful child', async () => {
  const f = await setup('collector-persistence'); const file = path.join(f.tree, 'ci/producer-evidence.mjs');
  const write = "  await fs.writeFile(path.join(directory, 'execution.json'), JSON.stringify(result, null, 2));";
  // A real EISDIR at the collector's final write, after child execution and finish.
  await fs.writeFile(file, (await fs.readFile(file, 'utf8')).replace(write,
    "  await fs.mkdir(path.join(directory, 'execution.json'));\n" + write));
  const r = await packageRun(f); const stub = r.fixture.stubs.internal;
  target('collector_persistence_failure_rejected', {parent: r.result.status, collector: stub.collector_process_rc, child: stub.child_rc, summary: stub.summary});
  assert.equal(r.result.status, 1, 'target prepare must reject actual collector I/O failure after child zero');
  assert.equal(stub.child_rc, 0); assert.equal(stub.collector_process_rc, 74);
  assert.equal(stub.summary.collector_rc, 74); assert.equal(stub.summary.state, 'COLLECTOR_FAILED');
  assert.equal(r.fixture.stubs.lang, undefined);
  assert.match(r.result.stdout + await fs.readFile(stub.log, 'utf8'), /EISDIR/);
});

test('prepare rejects a current summary with the wrong invocation identity', async () => {
  const f = await setup('wrong-summary'); const file = path.join(f.tree, 'ci/producer-evidence.mjs');
  await fs.writeFile(file, (await fs.readFile(file, 'utf8')).replace("invocation_id: options['invocation-id'] ?? null", "invocation_id: 'different-invocation'"));
  const r = await packageRun(f); const stub = r.fixture.stubs.internal;
  target('summary_identity_rejected', {parent: r.result.status, collector: stub.collector_process_rc, summary: stub.summary, expected: stub.invocation_id});
  assert.equal(r.result.status, 1, 'target prepare must reject mismatched current summary identity');
  assert.equal(stub.collector_process_rc, 0); assert.equal(stub.summary.execution_rc, 0);
  assert.match(r.fixture.error, /stale collector summary/); assert.equal(r.fixture.stubs.lang, undefined);
});

async function cancelOwnedChild(f, executable, args) {
  const child = spawn(executable, args, {cwd: f.tree, env: f.env, stdio: ['ignore', 'pipe', 'pipe']});
  let stdout = ''; let stderr = '';
  child.stdout.on('data', chunk => { stdout += chunk; }); child.stderr.on('data', chunk => { stderr += chunk; });
  const closed = new Promise(resolve => child.on('close', (rc, signal) => resolve({rc, signal})));
  let sent = false;
  for (let i = 0; i < 250; i++) {
    if (await fs.stat(f.trace).then(() => true, () => false)) { child.kill('SIGTERM'); sent = true; break; }
    await new Promise(resolve => setTimeout(resolve, 20));
  }
  const start = performance.now();
  const timeout = setTimeout(async () => {
    // A cut may remove the collector's bound. Reap only its recorded direct child.
    const [call] = await calls(f.root);
    if (call?.child_pid) {
      const status = await fs.readFile(`/proc/${call.child_pid}/status`, 'utf8').catch(() => '');
      if (status.match(/^PPid:\s+(\d+)/m)?.[1] === String(child.pid)) process.kill(call.child_pid, 'SIGKILL');
      else child.kill('SIGKILL');
    } else child.kill('SIGKILL');
  }, 5000);
  const result = await closed; clearTimeout(timeout);
  return {sent, ...result, wall_ms: performance.now() - start, stdout, stderr};
}

for (const mode of ['cancel-zero', 'cancel-ignore']) {
  test(`direct cancellation ${mode} keeps raw child status and fails the collector within its bound`, async () => {
    const f = await setup(mode); f.env.EVIDENCE_TEST_MODE = mode;
    const root = path.join(f.root, 'evidence');
    const args = [path.join(repo, 'ci/producer-evidence.mjs'), '--role', 'package', '--name', 'internal', '--source-tree', f.tree, '--root', root, '--', f.producer];
    const result = await cancelOwnedChild(f, 'node', args); const [call] = await calls(root);
    await fs.writeFile(path.join(f.root, 'cancellation-parent.json'), JSON.stringify(result, null, 2));
    target('cancel_child_collector_separation', {mode, result, child: call?.child_rc, collector: call?.collector_rc, cancellation: call?.cancellation});
    assert.equal(result.rc, 143, 'target cancelled collector cannot be green even when child exits zero');
    assert.ok(result.sent); assert.equal(result.signal, null); assert.ok(result.wall_ms < 4000, 'target cancellation is bounded');
    assert.equal(call.state, 'CANCELLED'); assert.equal(call.child_rc, mode === 'cancel-zero' ? 0 : -9);
    assert.equal(call.child_signal, mode === 'cancel-zero' ? null : 'SIGKILL'); assert.equal(call.collector_rc, 143);
    assert.equal(call.cancellation.escalation_signal, mode === 'cancel-zero' ? null : 'SIGKILL');
    const summary = JSON.parse(await fs.readFile(path.join(root, 'package-internal.result.json')));
    assert.equal(summary.execution_rc, call.child_rc); assert.equal(summary.collector_rc, 143);
  });
  test(`smoke cancellation ${mode} cannot publish a green parent or continue samples`, async () => {
    const f = await setup(`smoke-${mode}`); f.env.EVIDENCE_TEST_MODE = mode;
    const work = path.join(f.root, 'smoke');
    const command = zxCommand([path.join(repo, 'ci/smoke/run_smoke.mjs'), f.producer, work]);
    const result = await cancelOwnedChild(f, command[0], command.slice(1)); const [call] = await calls(work);
    target('cancel_smoke_parent_rejected', {mode, result, child: call?.child_rc, collector: call?.collector_rc});
    assert.equal(result.rc, 143, 'target smoke parent cannot be green after cancellation');
    assert.ok(result.sent); assert.ok(result.wall_ms < 4000);
    assert.equal(call.child_rc, mode === 'cancel-zero' ? 0 : -9); assert.equal(call.collector_rc, 143);
    const parent = JSON.parse(await fs.readFile(path.join(work, 'smoke-result.json')));
    assert.equal(parent.parent_rc, 143); assert.equal(parent.pass, 0);
    assert.equal((await calls(work)).length, 1); assert.equal((await fs.readFile(f.trace, 'utf8')).match(/argv0=/g).length, 1);
  });
}

// These fixtures exercise the shipped zx entry and real child processes, not GC correctness.
import assert from 'node:assert/strict';
import {execFileSync, spawn} from 'node:child_process';
import fs from 'node:fs/promises';
import path from 'node:path';
import os from 'node:os';
import test from 'node:test';
import {fileURLToPath} from 'node:url';

const repo = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const product = path.join(repo, 'ci/build_patched_runtime.mjs');
const sourceUrl = 'https://github.com/cjcj-dev/cangjie-runtime.git';
const guard = `bool TryAcquireMutatorManagementRLock() {
  if (!mutatorManagementRWLock.TryLockRead()) return false;
  if (mgmtWritersWaiting.load(std::memory_order_acquire)) mutatorManagementRWLock.UnlockRead();
  return true;
}`;
const python = `import os, pathlib, json, sys, subprocess
root = pathlib.Path.cwd()
pathlib.Path(os.environ['FIXTURE_OBSERVATION']).write_text(json.dumps({
 'heap': os.environ.get('cjHeapSize'), 'sdk': os.environ.get('CANGJIE_HOME'),
 'language': os.environ.get('GC_UNIT_GATE_LANGUAGE_TESTS'), 'work': str(root.parent)}))
mode = os.environ['FIXTURE_MODE']
out = pathlib.Path(os.environ.get('GC_UNIT_OUT', str(root / 'tests/gc_unit/build_standalone')))
out.mkdir(parents=True, exist_ok=True)
status = pathlib.Path(os.environ.get('GC_UNIT_GATE_STATUS', str(root / 'gate.status')))
status.write_text('CPP_SUITE=' + ('PASS' if mode == 'success' else 'FAIL') + '\\nLANGUAGE=DEFERRED\\n')
(out / 'gate_run.log').write_text('GC_UNIT_OTHER_VM_EXIT_RC=0\\nGC_UNIT_OTHER_VM_TEARDOWN_RC=127\\n')
(out / 'teardown.log').write_text('timeout: failed to run command gdb\\n')
(out / 'teardown.rc').write_text('127\\n')
(out / 'other_vm_exit.log').write_text('fixture child completed\\n')
(out / 'test-manifest.tsv').write_text('main\\tFixture.Done\\t000000\\npublication\\tFixture.Incomplete\\t000001\\n')
(out / 'test-rc').mkdir()
(out / 'test-rc/000000-main.rc').write_text('0\\n')
(out / 'test-logs').mkdir()
(out / 'test-logs/000001-publication.log').write_text('started without terminal rc\\n')
(out / 'ignored.o').write_bytes(b'not diagnostic')
print('fixture stdout before exit', flush=True)
print('fixture stderr before exit', file=sys.stderr, flush=True)
if mode == 'timeout':
 rc = subprocess.call(['timeout', '0.1', 'python3', '-c', 'import time; time.sleep(30)'])
 print('GC_UNIT_GATE_FAIL: suite exited unsuccessfully (rc=%d)' % rc, file=sys.stderr)
 sys.exit(rc)
if mode == 'failure':
 print('GC_UNIT_GATE_FAIL: suite exited unsuccessfully (rc=127)', file=sys.stderr)
 sys.exit(7)
if mode.startswith('collection'):
 (root / 'output').mkdir()
 (root / 'output/conflict.txt').write_text('copy conflict')
 target = status.parent / 'runtime-output/conflict.txt'
 target.mkdir(parents=True)
 if mode == 'collection': sys.exit(9)
output = root / 'output/Release/lib'
output.mkdir(parents=True)
(output / 'libcangjie-runtime.so').write_text('fixture only, not a runtime SO')
`;
async function run(command, args, options) {
  return new Promise((resolve, reject) => {
    const child = spawn(command, args, options);
    let stdout = '', stderr = '';
    child.stdout.on('data', data => { stdout += data; });
    child.stderr.on('data', data => { stderr += data; });
    child.on('error', reject);
    child.on('close', (rc, signal) => resolve({rc, signal, stdout, stderr}));
  });
}
async function fixture(mode, check, {missingTool = false} = {}) {
  const root = await fs.mkdtemp(path.join(process.env.TMPDIR || os.tmpdir(), 'runtime-entry-'));
  try {
    const source = path.join(root, 'source');
    await fs.mkdir(path.join(source, 'runtime/src/Mutator'), {recursive: true});
    await fs.writeFile(path.join(source, 'runtime/src/Mutator/MutatorManager.h'), guard);
    await fs.writeFile(path.join(source, 'runtime/build.py'), python);
    const git = args => execFileSync('git', ['-C', source, ...args], {encoding: 'utf8'}).trim();
    git(['init', '-q']); git(['add', '.']);
    git(['-c', 'user.name=Zxilly', '-c', 'user.email=zxilly@outlook.com', 'commit', '-qm', 'fixture']);
    const bin = path.join(root, 'bin');
    await fs.mkdir(bin);
    // Controlled dependency result, not a claim that a fixture debugger runs GC.
    await fs.writeFile(path.join(bin, 'gdb'), `#!/bin/sh\necho fixture-gdb\nexit ${missingTool ? 127 : 0}\n`, {mode: 0o755});
    const diagnostics = path.join(root, 'diagnostics');
    const observation = path.join(root, 'observation.json');
    const env = {...process.env, PATH: `${bin}:${process.env.PATH}`, TMPDIR: root,
      CJCJ_SRCBUILD_SOURCE_MIRRORS: `${sourceUrl}=${source}`, CJCJ_ALLOW_RUNTIME_OVERRIDE: '1',
      CJCJ_RUNTIME_REF_OVERRIDE: git(['rev-parse', 'HEAD']), RUNTIME_REF: '',
      RUNTIME_DIAGNOSTICS_DIR: diagnostics, cjHeapSize: '12GB', CANGJIE_HOME: '/fixture/sdk',
      FIXTURE_MODE: mode, FIXTURE_OBSERVATION: observation};
    const result = await run('npx', ['--yes', 'zx@8', product, path.join(root, 'dist')], {cwd: repo, env});
    let record, dir;
    try {
      dir = path.join(diagnostics, (await fs.readdir(diagnostics)).find(name => name.startsWith('build-')));
      record = JSON.parse(await fs.readFile(path.join(dir, 'result.json')));
    } catch { /* assertions below identify missing handoff, including baseline controls */ }
    if (process.env.DIAGNOSTIC_TEST_EVIDENCE) {
      const dest = path.join(process.env.DIAGNOSTIC_TEST_EVIDENCE, mode + (missingTool ? '-missing' : '') + '-' + path.basename(root));
      await fs.mkdir(dest, {recursive: true});
      if (dir) await fs.cp(dir, path.join(dest, 'diagnostics'), {recursive: true});
      await fs.writeFile(path.join(dest, 'entry.json'), JSON.stringify(result, null, 2));
      console.log(`ENTRY_EVIDENCE=${dest}`);
    }
    await check({result, record, dir, root, observation, env});
  } finally { await fs.rm(root, {recursive: true, force: true}); }
}

test('native entry isolates heap while preserving parent and defer', async () => {
  await fixture('success', async ({result, observation, env}) => {
    assert.equal(result.rc, 0, result.stderr);
    const observed = JSON.parse(await fs.readFile(observation));
    console.log(`TARGET_ASSERT_EXECUTED heap=${observed.heap} parent=${env.cjHeapSize}`);
    assert.equal(observed.heap, null, 'native child must not inherit SDK heap');
    assert.equal(env.cjHeapSize, '12GB');
    assert.equal(observed.sdk, '/fixture/sdk');
    assert.equal(observed.language, 'defer');
    await assert.rejects(fs.stat(observed.work), {code: 'ENOENT'});
  });
});
test('unit evidence survives cleanup and missing terminal rc stays unknown', async () => {
  await fixture('success', async ({record, dir}) => {
    console.log('TARGET_ASSERT_EXECUTED unit evidence handoff');
    assert.ok(record, 'result manifest must survive cleanup');
    assert.equal(record.collection, 'COMPLETE');
    assert.equal(record.tests.length, 2);
    assert.equal(record.tests[0].rc, '0');
    assert.equal(record.tests[1].rc, 'UNKNOWN');
    assert.equal(record.layers.teardownFile, '127');
    assert.match(await fs.readFile(path.join(dir, 'unit/teardown.log'), 'utf8'), /failed to run/);
    assert.ok(record.files.every(file => !file.path.endsWith('.o')));
  });
});
for (const [mode, expected] of [['failure', 7], ['timeout', 124], ['collection', 9], ['collection-success', 0]]) {
  test(`native ${mode} preserves build rc and raw stdout/stderr`, async () => {
    await fixture(mode, async ({result, record, dir}) => {
      console.log(`TARGET_ASSERT_EXECUTED ${mode} buildRc=${record?.buildRc}`);
      assert.notEqual(result.rc, 0);
      assert.equal(record?.buildRc, expected);
      assert.match(await fs.readFile(path.join(dir, 'build.stdout.log'), 'utf8'), /stdout before exit/);
      assert.match(await fs.readFile(path.join(dir, 'build.stderr.log'), 'utf8'), /stderr before exit/);
      if (mode.startsWith('collection')) {
        assert.equal(record.collection, 'FAILED');
        if (mode === 'collection') assert.match(record.error, /rc=9/);
        assert.ok(record.collectionError);
      } else {
        assert.match(record.gateStatus, /CPP_SUITE=FAIL/);
        assert.equal(record.layers.suite, mode === 'failure' ? 127 : 124);
      }
    });
  });
}
test('missing dependency fails before native build with a stage record', async () => {
  await fixture('success', async ({result, record, observation}) => {
    console.log(`TARGET_ASSERT_EXECUTED dependency=${record?.tools?.gdb?.rc}`);
    assert.notEqual(result.rc, 0);
    assert.equal(record?.stage, 'dependencies');
    assert.equal(record.buildRc, 'NOT_RUN');
    assert.equal(record.tools.gdb.rc, 127);
    await assert.rejects(fs.stat(observation), {code: 'ENOENT'});
  }, {missingTool: true});
});
test('workflow cache hit records NOT_RUN and current SOURCE_SHA', async () => {
  const root = await fs.mkdtemp(path.join(process.env.TMPDIR || os.tmpdir(), 'runtime-cache-'));
  try {
    await fs.mkdir(path.join(root, 'dist-runtime'));
    await fs.writeFile(path.join(root, 'dist-runtime/SOURCE_SHA'), 'fixture-source\n');
    const dir = path.join(root, 'diagnostics');
    const result = await run('node', [path.join(repo, 'ci/runtime-diagnostics.mjs')], {cwd: root,
      env: {...process.env, RUNTIME_DIAGNOSTICS_DIR: dir, RUNTIME_CACHE_HIT: 'true'}});
    const record = JSON.parse(await fs.readFile(path.join(dir, 'workflow.json')));
    console.log(`TARGET_ASSERT_EXECUTED cache=${record.tests}`);
    assert.equal(result.rc, 0);
    assert.equal(record.tests, 'NOT_RUN/cache-hit');
    assert.equal(record.sourceSha, 'fixture-source');
  } finally { await fs.rm(root, {recursive: true, force: true}); }
});

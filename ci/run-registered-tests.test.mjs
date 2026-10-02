import assert from 'node:assert/strict';
import {spawnSync} from 'node:child_process';
import fs from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';
import test from 'node:test';
import {runScripts} from './run-registered-tests.mjs';
import {repoRoot} from './test-manifest.mjs';

test('script CLI executes the registered resource-selector assertions', async () => {
  const work = await fs.mkdtemp(path.join(os.tmpdir(), 'registered-cli-'));
  try {
    const output = path.join(work, 'results');
    const child = spawnSync(process.execPath,
      ['ci/run-registered-tests.mjs', 'scripts', output, 'ci/test_build_resources.py'],
      {cwd: repoRoot, encoding: 'utf8'});
    const report = JSON.parse(await fs.readFile(path.join(output, 'results.json'), 'utf8'));
    assert.deepEqual(report.results.map(result => result.file), ['ci/test_build_resources.py']);
    const log = await fs.readFile(report.results[0].log, 'utf8');
    assert.match(log, /ASSERT oversized request capped to measured physical-memory budget/);
    assert.equal(report.results[0].rc, 0, log);
    assert.equal(child.status, 0, child.stdout + child.stderr);
  } finally {
    await fs.rm(work, {recursive: true, force: true});
  }
});

test('script executor preserves each real subprocess exit and output argument', async () => {
  const work = await fs.mkdtemp(path.join(os.tmpdir(), 'registered-exit-'));
  try {
    await fs.writeFile(path.join(work, 'test_green.py'), 'print("CONTROL_GREEN")\n');
    await fs.writeFile(path.join(work, 'test_red.sh'), 'printf "%s\\n" "$1"\nexit 7\n');
    const results = await runScripts(work, [
      {file: 'test_green.py', executor: 'python3', args: []},
      {file: 'test_red.sh', executor: 'bash', args: ['{output}']},
    ], path.join(work, 'logs'));
    assert.deepEqual(results.map(result => result.rc), [0, 7]);
    assert.match(await fs.readFile(results[0].log, 'utf8'), /CONTROL_GREEN/);
    assert.equal((await fs.readFile(results[1].log, 'utf8')).trim(), path.join(work, 'logs/test_red.sh/output'));
  } finally {
    await fs.rm(work, {recursive: true, force: true});
  }
});

test('ObjC fixture validation accepts recorded modules and rejects each missing or changed input', async () => {
  const {validateObjCFixture, digest} = await import('./run-registered-tests.mjs');
  const work = await fs.mkdtemp(path.join(os.tmpdir(), 'objc-input-'));
  const imports = path.join(work, 'imports');
  try {
    await fs.mkdir(path.join(imports, 'objc'), {recursive: true});
    const files = {};
    for (const name of ['internal', 'lang']) {
      const file = `objc/objc.${name}.cjo`;
      await fs.writeFile(path.join(imports, file), name);
      files[file] = digest(path.join(imports, file));
    }
    validateObjCFixture(imports, files);
    for (const root of [undefined, '', path.join(work, 'missing')]) {
      assert.throws(() => validateObjCFixture(root, files));
    }
    for (const name of ['internal', 'lang']) {
      const file = `objc/objc.${name}.cjo`;
      await fs.rename(path.join(imports, file), path.join(work, name));
      assert.throws(() => validateObjCFixture(imports, files));
      await fs.rename(path.join(work, name), path.join(imports, file));
      await fs.writeFile(path.join(imports, file), 'changed');
      assert.throws(() => validateObjCFixture(imports, files), /mismatched/);
      await fs.writeFile(path.join(imports, file), name);
    }
    validateObjCFixture(imports, files);
  } finally {
    await fs.rm(work, {recursive: true, force: true});
  }
});

test('workspace runner records missing producer and real preparation subprocess failure before cjpm', async () => {
  const {runCangjie} = await import('./run-registered-tests.mjs');
  const work = await fs.mkdtemp(path.join(os.tmpdir(), 'objc-prerequisite-'));
  const oldHome = process.env.CANGJIE_HOME;
  const oldProducer = process.env.OBJC_PREAMBLE_PRODUCER;
  try {
    const sdk = path.join(work, 'sdk');
    for (const file of ['bin/cjc', 'tools/bin/cjpm',
      'runtime/lib/linux_x86_64_cjnative/libcangjie-runtime.so',
      'runtime/lib/linux_x86_64_cjnative/libboundscheck.so',
      'lib/linux_x86_64_cjnative/libcangjie-std-core.a', 'third_party/llvm/lib/libLLVM-15.so']) {
      await fs.mkdir(path.dirname(path.join(sdk, file)), {recursive: true});
      await fs.writeFile(path.join(sdk, file), 'identity input');
    }
    process.env.CANGJIE_HOME = sdk;
    delete process.env.OBJC_PREAMBLE_PRODUCER;
    const missing = path.join(work, 'missing');
    await fs.mkdir(missing);
    const rejected = await runCangjie(repoRoot, [], missing);
    assert.equal(rejected[0].executed, false);
    assert.match(rejected[0].error, /explicit OBJC_PREAMBLE_PRODUCER/);
    const root = path.join(work, 'tree');
    await fs.mkdir(path.join(root, 'scripts'), {recursive: true});
    await fs.copyFile(path.join(repoRoot, 'scripts/objc_preamble_unit.py'), path.join(root, 'scripts/objc_preamble_unit.py'));
    await fs.cp(path.join(repoRoot, 'scripts/objc_regcomp_fixtures'), path.join(root, 'scripts/objc_regcomp_fixtures'), {recursive: true});
    await fs.mkdir(path.join(root, 'runtime_shim'));
    await fs.writeFile(path.join(root, 'runtime_shim/cjselfhost_llvmshim.o'), 'shim identity');
    spawnSync('git', ['init', '-q'], {cwd: root});
    spawnSync('git', ['add', '.'], {cwd: root});
    const commit = spawnSync('git', ['-c', 'user.name=Zxilly', '-c', 'user.email=zxilly@outlook.com', 'commit', '-qm', 'fixture'], {cwd: root});
    assert.equal(commit.status, 0);
    const producer = path.join(work, 'producer');
    await fs.writeFile(producer, '#!/bin/sh\nexit 7\n', {mode: 0o755});
    process.env.OBJC_PREAMBLE_PRODUCER = producer;
    const output = path.join(work, 'failed');
    await fs.mkdir(output);
    const failed = await runCangjie(root, [], output);
    assert.equal(failed[0].executed, false);
    assert.equal(failed[0].preparation.rc, 1);
    const manifest = JSON.parse(await fs.readFile(path.join(output, 'objc-fixture/fixture.json')));
    assert.equal(manifest.stubs.internal.rc, 7);
    assert.equal(manifest.stubs.lang, undefined);
    assert.match(manifest.error, /internal producer rc=7/);
  } finally {
    for (const [key, value] of [['CANGJIE_HOME', oldHome], ['OBJC_PREAMBLE_PRODUCER', oldProducer]]) {
      if (value === undefined) delete process.env[key]; else process.env[key] = value;
    }
    await fs.rm(work, {recursive: true, force: true});
  }
});

test('directed parameters preserve the whole-workspace default and reject unsupported or partial selection', async () => {
  const {parseCangjieSelection, cangjieCommand} = await import('./run-registered-tests.mjs');
  const target = '/private/prebuilt';
  const hash = 'a'.repeat(64);
  const args = ['--member', 'packages/compiler_unittest', '--filter', '*ObjCPreambleTest*',
    '--skip-build', '--target-dir', target, '--elf-sha256', hash];
  const selected = parseCangjieSelection(args);
  assert.equal(parseCangjieSelection([]), undefined);
  const whole = cangjieCommand('/sdk', '/results');
  assert.ok(!whole.includes('--member'));
  assert.ok(!whole.includes('--filter'));
  assert.ok(!whole.includes('--skip-build'));
  assert.equal(whole.at(-1), '/results/target');
  const command = cangjieCommand('/sdk', '/results', selected);
  assert.equal(command[command.indexOf('--member') + 1], 'packages/compiler_unittest');
  assert.equal(command[command.indexOf('--filter') + 1], '*ObjCPreambleTest*');
  assert.equal(command[command.indexOf('--target-dir') + 1], target);
  assert.ok(command.includes('--skip-build'));
  for (const bad of [args.slice(0, -2), [...args, '--unknown'], [...args, '--skip-build'],
    args.map(arg => arg === target ? 'relative' : arg), args.map(arg => arg === '*ObjCPreambleTest*' ? '*Missing*' : arg)]) {
    assert.throws(() => parseCangjieSelection(bad));
  }
});

test('prebuilt selection and XML reject wrong identity, empty execution and incomplete or unrelated cases', async () => {
  const {inspectSelection, inspectTargetReports, digest} = await import('./run-registered-tests.mjs');
  const {REGISTERED} = await import('./test-manifest.mjs');
  const work = await fs.mkdtemp(path.join(os.tmpdir(), 'objc-selection-'));
  try {
    const elf = path.join(work, 'release/unittest_bin/compiler_unittest@cjcj');
    await fs.mkdir(path.dirname(elf), {recursive: true});
    const bytes = Buffer.alloc(20); bytes.write('\x7fELF'); bytes.writeUInt16LE(62, 18);
    await fs.writeFile(elf, bytes);
    const selection = {member: 'packages/compiler_unittest', filter: '*ObjCPreambleTest*',
      targetDir: work, skipBuild: true, elfSha256: digest(elf)};
    const qualified = inspectSelection(repoRoot, REGISTERED, selection);
    assert.deepEqual(qualified.cases, ['ordinaryFrontendControl', 'mirrorImplementationFiles']);
    assert.throws(() => inspectSelection(repoRoot, [], selection), /not registered/);
    assert.throws(() => inspectSelection(repoRoot, REGISTERED, {...selection, elfSha256: '0'.repeat(64)}), /identity/);
    await fs.writeFile(elf, 'not an ELF');
    assert.throws(() => inspectSelection(repoRoot, REGISTERED, selection), /identity/);
    const report = path.join(work, 'report.xml');
    const one = '<testcase classname="cjcj::compiler_unittest.ObjCPreambleTest" name="ordinaryFrontendControl" assertions="1"/>';
    const two = '<testcase classname="cjcj::compiler_unittest.ObjCPreambleTest" name="mirrorImplementationFiles" assertions="5"/>';
    for (const xml of ['<testsuite/>', `<testsuite>${one}</testsuite>`, `<testsuite>${one}${one}</testsuite>`,
      `<testsuite>${one}${two.replace('mirrorImplementationFiles', 'unrelated')}</testsuite>`]) {
      await fs.writeFile(report, xml);
      assert.throws(() => inspectTargetReports([report], qualified.cases), /did not execute/);
    }
    await fs.writeFile(report, `<testsuite>${one}${two}</testsuite>`);
    assert.deepEqual(inspectTargetReports([report], qualified.cases).map(c => c.assertions), [1, 5]);
  } finally { await fs.rm(work, {recursive: true, force: true}); }
});

import assert from 'node:assert/strict';
import fs from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';
import {spawnSync} from 'node:child_process';
import test from 'node:test';
import {load as loadYaml, dump as dumpYaml} from './vendor/js-yaml/js-yaml.mjs';

import {GATES} from './release-gates.mjs';

const repo = path.resolve(import.meta.dirname, '..');
const command = path.join(repo, 'ci', 'release-gates.mjs');
const SHA40 = /^[0-9a-f]{40}$/;

function run(program, args, options = {}) {
  return spawnSync(program, args, {
    encoding: 'utf8',
    maxBuffer: 16 * 1024 * 1024,
    ...options,
  });
}

function git(root, ...args) {
  const result = run('git', ['-C', root, ...args]);
  assert.equal(result.status, 0, result.stderr || result.stdout);
  return result.stdout.trim();
}

async function write(root, relative, contents) {
  const file = path.join(root, ...relative.split('/'));
  await fs.mkdir(path.dirname(file), {recursive: true});
  await fs.writeFile(file, contents);
}

function commit(root, message) {
  git(root, 'add', '.');
  git(root, '-c', 'user.name=Zxilly', '-c', 'user.email=zxilly@outlook.com',
    'commit', '-m', message);
  const sha = git(root, 'rev-parse', 'HEAD');
  assert.match(sha, SHA40);
  return sha;
}

function gate(root, name, extra = []) {
  const result = run(process.execPath, [command, name, '--repo', root, '--json', ...extra]);
  let value;
  try {
    value = JSON.parse(result.stdout);
  } catch (error) {
    assert.fail(`gate output is not JSON: ${error.message}\nstdout=${result.stdout}\nstderr=${result.stderr}`);
  }
  return {result, value};
}

test('registry keeps all 17 gates, exactly six explicit runs, and the four 0811 updates', () => {
  assert.deepEqual(Object.keys(GATES), Array.from({length: 17}, (_, index) => `G${index + 1}`));
  assert.deepEqual(Object.entries(GATES).filter(([, value]) => value.needsRun).map(([name]) => name),
    ['G3', 'G6', 'G7', 'G9', 'G10', 'G11']);
  assert.deepEqual(Object.entries(GATES).filter(([, value]) => value.updated).map(([name]) => name),
    ['G3', 'G4', 'G8', 'G9']);
});

test('G5 distinguishes an unwired checker from the same checker wired fail-closed', async t => {
  const fixture = await fs.mkdtemp(path.join(os.tmpdir(), 'release-gates-g5-'));
  t.after(() => fs.rm(fixture, {recursive: true, force: true}));
  git(fixture, 'init', '-q');
  await write(fixture, 'scripts/check_packaged_std.mjs',
    "const CLASS_NAMES = ['cjo', 'bc', 'static-ffi', 'shared', 'provenance'];\n");
  await write(fixture, '.github/workflows/build-release-package.yml', [
    'jobs:',
    '  package:',
    '    steps:',
    '      - name: Compose SDK package',
    '        run: node scripts/package_sdk.mjs',
    '',
  ].join('\n'));
  const before = commit(fixture, 'checker exists but has no consumer');
  await write(fixture, '.github/workflows/build-release-package.yml', [
    'jobs:',
    '  package:',
    '    steps:',
    '      - name: Compose SDK package',
    '        run: node scripts/package_sdk.mjs',
    '      - name: Verify packaged standard library',
    '        if: inputs.verify',
    '        timeout-minutes: 2',
    '        run: |',
    '          node scripts/check_packaged_std.mjs --sdk "$SDK" --std "$STD" --platform "$PLATFORM"',
    '      - name: Verify packaged SDK',
    '        run: node ci/smoke/run_smoke.mjs',
    '',
  ].join('\n'));
  const after = commit(fixture, 'wire checker');

  const negative = gate(fixture, 'G5', ['--ref', before]);
  assert.equal(negative.result.status, 1, negative.result.stderr);
  assert.equal(negative.value.status, 'NOT_MET');
  assert.match(negative.value.value, /workflow_consumers=0/);

  const positive = gate(fixture, 'G5', ['--ref', after]);
  assert.equal(positive.result.status, 0, positive.result.stderr);
  assert.equal(positive.value.status, 'MET');
  assert.match(positive.value.value, /workflow_consumers=1/);
});

test('G13 distinguishes ancestor, non-ancestor, and unreadable runtime histories', async t => {
  const fixture = await fs.mkdtemp(path.join(os.tmpdir(), 'release-gates-g13-'));
  const cjcj = path.join(fixture, 'cjcj');
  const runtime = path.join(fixture, 'runtime');
  t.after(() => fs.rm(fixture, {recursive: true, force: true}));
  await fs.mkdir(cjcj, {recursive: true});
  await fs.mkdir(runtime, {recursive: true});

  git(runtime, 'init', '-q');
  await write(runtime, 'history.txt', 'root\n');
  const root = commit(runtime, 'root');
  await fs.appendFile(path.join(runtime, 'history.txt'), 'loaderlife\n');
  const loaderlife = commit(runtime, 'loaderlife');
  await fs.appendFile(path.join(runtime, 'history.txt'), 'pin tip\n');
  const positivePin = commit(runtime, 'pin tip');
  git(runtime, 'checkout', '-q', '-b', 'negative-control', root);
  await write(runtime, 'negative.txt', 'sibling without loaderlife\n');
  const negativePin = commit(runtime, 'negative sibling');

  await write(cjcj, 'ci/runtime_pin.env', [
    `RUNTIME_REF=${positivePin}`,
    'RUNTIME_VERSION=fixture',
    'RUNTIME_SRC_URL=https://example.invalid/runtime.git',
    `LOADERLIFE_MIN_REF=${loaderlife}`,
    '',
  ].join('\n'));
  for (const file of ['llvm_pin.env', 'source_pin.env', 'cjpm_pin.env']) {
    await write(cjcj, `ci/${file}`, '# unused by this fixture\n');
  }

  const positive = gate(cjcj, 'G13', ['--runtime-repo', runtime]);
  assert.equal(positive.result.status, 0, positive.result.stderr);
  assert.equal(positive.value.status, 'MET');

  const negative = gate(cjcj, 'G13', [
    '--runtime-repo', runtime,
    '--runtime-ref', negativePin,
  ]);
  assert.equal(negative.result.status, 1, negative.result.stderr);
  assert.equal(negative.value.status, 'NOT_MET');

  const unknown = gate(cjcj, 'G13', ['--runtime-repo', path.join(fixture, 'missing-runtime')]);
  assert.equal(unknown.result.status, 2, unknown.result.stderr);
  assert.equal(unknown.value.status, 'UNKNOWN');
  assert.match(unknown.value.value, /runtime ancestry unreadable/);
});

// Exercise the CLI against a real checkout copy. The copied targets module and
// workflow are the production inputs, and G15 still runs its real bundle/wire tests.
async function platformFixture(t) {
  const root = await fs.mkdtemp(path.join(os.tmpdir(), 'release-platform-gates-'));
  t.after(() => fs.rm(root, {recursive: true, force: true}));
  for (const entry of ['build', 'ci', '.github', 'scripts', 'ops']) {
    await fs.cp(path.join(repo, entry), path.join(root, entry), {recursive: true});
  }
  return root;
}

const platformGates = ['G3', 'G6', 'G7', 'G9', 'G15'];

async function mutateFile(root, relative, transform) {
  const file = path.join(root, relative);
  const before = await fs.readFile(file, 'utf8');
  const after = transform(before);
  assert.notEqual(after, before, `mutation did not change ${relative}`);
  await fs.writeFile(file, after);
}

test('platform gates consume every registry row and retain explicit run requirements', async t => {
  const {allReleasePlatforms, getReleasePlatform, releasePlatformReadiness} = await import('../build/lib/targets.mjs');
  for (const name of platformGates) {
    const {result, value} = gate(repo, name);
    t.diagnostic(`${name}: real CLI rc=${result.status}, status=${value.status}`);
    assert.equal(result.status, name === 'G15' ? 0 : 2, JSON.stringify(value));
    assert.deepEqual(value.scope.platforms.map(row => row.key), allReleasePlatforms());
    for (const row of value.scope.platforms) {
      assert.equal(row.status, releasePlatformReadiness(row.key).status);
      assert.equal(row.host, getReleasePlatform(row.key).host);
      assert.deepEqual(row.reasons, [...releasePlatformReadiness(row.key).reasons]);
    }
    assert.deepEqual(value.scope.jobs.map(job => job.key).sort(), allReleasePlatforms()
      .filter(key => releasePlatformReadiness(key).status === 'buildable').sort());
    if (name !== 'G15') assert.match(value.value, /NEEDS_RUN:/);
  }
});

test('new registry platform makes each dependent gate red until its package job exists', async t => {
  const root = await platformFixture(t);
  await mutateFile(root, 'build/lib/targets.mjs', source => source.replace(
    'const RELEASE_PLATFORMS = Object.freeze([',
    "const RELEASE_PLATFORMS = Object.freeze([\n  releasePlatform({key: 'fixture-new-platform', host: 'linux-x64', runner: 'ubuntu-24.04'}),"));
  for (const name of platformGates) await t.test(`${name} detects the added platform`, () => {
    const {result, value} = gate(root, name);
    t.diagnostic(`${name}: added platform returned rc=${result.status}, status=${value.status}`);
    assert.equal(result.status, 1, `${name}: ${JSON.stringify(value)}`);
    assert.match(value.value, /fixture-new-platform: expected one package job, found 0/);
  });
  // A newly supported platform can be wired without editing the gate itself.
  await mutateFile(root, '.github/workflows/release.yml', source => source.replace('jobs:\n', [
    'jobs:',
    '  fixture-new-package:',
    '    uses: ./.github/workflows/build-release-package.yml',
    '    needs: [package-p1-linux-x64]',
    '    with:',
    '      release_key: fixture-new-platform',
    '      platform: linux-x64',
    '      llvm_platform: linux_x86_64',
    '      std_artifact: final-std-linux-x64',
    "      cross_std_artifacts: '[]'",
    '',
  ].join('\n')).replace('    needs: [source-p1-linux-x64,', '    needs: [fixture-new-package, source-p1-linux-x64,')
    .replace("        needs.package-p5-darwin-x64.result == 'success' &&", "        needs.fixture-new-package.result == 'success' &&\n        needs.package-p5-darwin-x64.result == 'success' &&"));
  for (const name of platformGates) {
    const {result, value} = gate(root, name);
    assert.equal(result.status, name === 'G15' ? 0 : 2, JSON.stringify(value));
    assert.equal(value.scope.failures.length, 0);
    assert.ok(value.scope.jobs.some(job => job.key === 'fixture-new-platform'));
  }
});

test('deleting a real package job cannot shrink the required gate set', async t => {
  const root = await platformFixture(t);
  const original = gate(root, 'G7').value.scope;
  const removed = original.jobs.at(-1);
  await mutateFile(root, '.github/workflows/release.yml', source => source.replace(
    new RegExp(`^  ${removed.id}:[\\s\\S]*?(?=^  [\\w-]+:|$(?![\\s\\S]))`, 'm'), ''));
  for (const name of platformGates) {
    const {result, value} = gate(root, name);
    assert.equal(result.status, 1, JSON.stringify(value));
    assert.ok(value.scope.failures.includes(`${removed.key}: expected one package job, found 0`));
    assert.deepEqual(value.scope.platforms, original.platforms);
  }
});

test('job identity and host mapping matter even when the package job count is unchanged', async t => {
  const root = await platformFixture(t);
  const scope = gate(root, 'G7').value.scope;
  const [first, second] = scope.jobs;
  await mutateFile(root, '.github/workflows/release.yml', source => source.replace(
    `release_key: ${first.key}\n`, `release_key: ${second.key}\n`));
  const duplicate = gate(root, 'G15');
  assert.equal(duplicate.result.status, 1, JSON.stringify(duplicate.value));
  assert.equal(duplicate.value.scope.jobs.length, scope.jobs.length);
  assert.ok(duplicate.value.scope.failures.includes(`${first.key}: expected one package job, found 0`));
  assert.ok(duplicate.value.scope.failures.includes(`${second.key}: expected one package job, found 2`));
  await fs.copyFile(path.join(repo, '.github/workflows/release.yml'), path.join(root, '.github/workflows/release.yml'));
  await mutateFile(root, '.github/workflows/release.yml', source => source.replace(
    `platform: ${first.host}\n`, 'platform: fixture-wrong-host\n'));
  const wrongHost = gate(root, 'G15');
  assert.equal(wrongHost.result.status, 1, JSON.stringify(wrongHost.value));
  assert.match(wrongHost.value.value, /host\/LLVM mismatch/);
  const workflow = await fs.readFile(path.join(repo, '.github/workflows/release.yml'), 'utf8');
  for (const [from, to, expected] of [
    [`llvm_platform: ${first.llvm_platform}\n`, 'llvm_platform: fixture-wrong-llvm\n', 'host/LLVM mismatch'],
    [`release_key: ${first.key}\n`, 'release_key: fixture-unknown-key\n', 'unexpected release_key=fixture-unknown-key'],
    [`release_key: ${first.key}\n`, '', 'unexpected release_key=<missing>'],
  ]) {
    await write(root, '.github/workflows/release.yml', workflow.replace(from, to));
    const bad = gate(root, 'G15');
    assert.equal(bad.result.status, 1, JSON.stringify(bad.value));
    assert.ok(bad.value.value.includes(expected), bad.value.value);
  }
});

test('comments do not create jobs and excluded or blocked rows keep their reasons', async t => {
  const root = await platformFixture(t);
  const before = gate(root, 'G7');
  await mutateFile(root, '.github/workflows/release.yml', source => source +
    '\n# uses: ./.github/workflows/build-release-package.yml\n');
  const after = gate(root, 'G7');
  assert.equal(after.result.status, before.result.status);
  assert.deepEqual(after.value.scope, before.value.scope);
  for (const row of after.value.scope.platforms.filter(row => row.status !== 'buildable')) {
    assert.ok(row.reasons.length, row.key);
    assert.ok(after.value.value.includes(row.key));
    assert.ok(after.value.value.includes(row.reasons[0]));
  }
  const historical = gate(root, 'G7', ['--ref', 'HEAD']);
  assert.equal(historical.result.status, 2);
  assert.match(historical.value.value, /require a checkout, not --ref/);
});


test('new blocked and excluded registry rows remain visible without inventing package jobs', async t => {
  const root = await platformFixture(t);
  await mutateFile(root, 'build/lib/targets.mjs', source => source.replace(
    'const RELEASE_PLATFORMS = Object.freeze([',
    `const RELEASE_PLATFORMS = Object.freeze([
      releasePlatform({key: 'fixture-blocked', host: 'linux-x64', runner: 'ubuntu-24.04',
        crossTuples: Object.freeze(['fixture_unproduced_tuple'])}),
      releasePlatform({key: 'fixture-excluded', host: 'linux-x64', runner: 'ubuntu-24.04',
        excluded: 'fixture documented exclusion'}),`));
  for (const name of platformGates) {
    const {result, value} = gate(root, name);
    assert.equal(result.status, name === 'G15' ? 0 : 2, JSON.stringify(value));
    const blocked = value.scope.platforms.find(row => row.key === 'fixture-blocked');
    assert.equal(blocked.status, 'blocked');
    assert.ok(value.scope.std_tuples.includes('fixture_unproduced_tuple'));
    assert.match(value.value, /fixture_unproduced_tuple: no P01-P23 stage/);
    assert.match(value.value, /fixture-excluded \(fixture documented exclusion\)/);
  }
});


test('release YAML formatting preserves real CLI gate results', async t => {
  const root = await platformFixture(t);
  const relative = '.github/workflows/release.yml';
  const original = await fs.readFile(path.join(root, relative), 'utf8');
  const expected = loadYaml(original);
  const before = Object.fromEntries(platformGates.map(name => [name, gate(root, name)]));
  const reordered = loadYaml(original);
  for (const job of Object.values(reordered.jobs)) {
    if (job.with) job.with = Object.fromEntries(Object.entries(job.with).reverse());
  }
  const variants = {
    'blank line': original.replace('      release_key: linux-x64\n', '      release_key: linux-x64\n\n'),
    'comment': original.replace('      release_key: linux-x64\n', '      release_key: linux-x64 # release identity\n    # comment between inputs\n'),
    'key order': dumpYaml(reordered, {lineWidth: -1}),
    'flow mapping': dumpYaml(expected, {flowLevel: 3, lineWidth: -1}),
  };
  for (const [label, source] of Object.entries(variants)) await t.test(label, () => {
    assert.notEqual(source, original);
    assert.deepEqual(loadYaml(source), expected, 'formatting must preserve workflow data');
    return write(root, relative, source).then(() => {
      for (const name of platformGates) {
        const after = gate(root, name);
        t.diagnostic(`${label} ${name}: rc=${after.result.status}, status=${after.value.status}`);
        assert.equal(after.result.status, before[name].result.status, JSON.stringify(after.value));
        assert.equal(after.value.status, before[name].value.status);
        assert.deepEqual(after.value.scope, before[name].value.scope);
      }
    });
  });
});

test('invalid release YAML and duplicate mapping keys fail closed', async t => {
  const root = await platformFixture(t);
  for (const source of ['jobs: [', 'jobs: {}\njobs: {}\n', 'jobs: []\n']) {
    await write(root, '.github/workflows/release.yml', source);
    const {result, value} = gate(root, 'G15');
    assert.equal(result.status, 1, JSON.stringify(value));
    assert.equal(value.status, 'NOT_MET');
    assert.match(value.value, /invalid release workflow YAML|jobs must be a mapping/);
  }
});

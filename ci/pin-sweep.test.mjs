import assert from 'node:assert/strict';
import {spawnSync} from 'node:child_process';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import test from 'node:test';
import {auditPins, discoverPins, repoRoot} from './pin-sweep.mjs';

function git(root, ...arguments_) {
  const result = spawnSync('git', ['-C', root, ...arguments_], {encoding: 'utf8'});
  assert.equal(result.status, 0, `git ${arguments_.join(' ')} failed: ${(result.stderr || '').trim()}`);
  return result.stdout.trim();
}

function commit(root, message, contents) {
  fs.writeFileSync(path.join(root, 'value.txt'), `${contents}\n`);
  git(root, 'add', 'value.txt');
  git(root, 'commit', '--quiet', '-m', message);
  return git(root, 'rev-parse', 'HEAD');
}

test('every commit-valued pin is inventoried and paired with its clone URL', () => {
  const pins = discoverPins(repoRoot);
  assert.deepEqual(pins.map(pin => pin.key).sort(), [
    'CANGJIE_COMPILER_SHA',
    'CJPM_FORK_REF',
    'COMPILER_REF',
    'FLATBUFFERS_SHA',
    'LLVM_SHA',
    'LOADERLIFE_MIN_REF',
    'RUNTIME_REF',
    'STDX_REF',
    'TOOLS_REF',
  ]);
  assert.deepEqual(
    pins.filter(pin => !pin.urlKey || !pin.url).map(pin => pin.key),
    [],
    'a commit pin without a URL cannot answer whether CI can clone its authority line',
  );
  assert.equal(
    pins.find(pin => pin.key === 'LOADERLIFE_MIN_REF').urlKey,
    'RUNTIME_SRC_URL',
    'the minimum loader-life ref must be judged in the same runtime repository as RUNTIME_REF',
  );
});

test('an existing commit on a backup line is NOT_MET for both authority questions', () => {
  const fixture = fs.mkdtempSync(path.join(os.tmpdir(), 'pin-sweep-test-'));
  const source = path.join(fixture, 'source');
  const remote = path.join(fixture, 'remote.git');
  fs.mkdirSync(source);
  try {
    git(source, 'init', '--quiet', '--initial-branch=main');
    git(source, 'config', 'user.name', 'Pin Sweep Test');
    git(source, 'config', 'user.email', 'pin-sweep@example.invalid');
    const base = commit(source, 'base', 'base');

    git(source, 'switch', '--quiet', '-c', 'backup');
    const stranded = commit(source, 'stranded', 'backup-only');

    git(source, 'switch', '--quiet', 'main');
    const positive = commit(source, 'authority', 'main-line');
    assert.notEqual(stranded, positive);
    assert.equal(git(source, 'merge-base', stranded, positive), base);

    const cloned = spawnSync('git', ['clone', '--quiet', '--bare', source, remote], {encoding: 'utf8'});
    assert.equal(cloned.status, 0, (cloned.stderr || '').trim());

    const unpublished = commit(source, 'local-unpublished', 'local-only');
    git(source, 'switch', '--quiet', '-c', 'remote-main', positive);
    const remoteAhead = commit(source, 'remote-ahead', 'remote-only');
    git(remote, 'fetch', '--quiet', source, `${remoteAhead}:refs/heads/main`);
    git(source, 'switch', '--quiet', 'main');

    const pins = [
      {file: 'ci/fixture_pin.env', key: 'POSITIVE_REF', sha: positive, urlKey: 'POSITIVE_URL', url: remote},
      {file: 'ci/fixture_pin.env', key: 'STRANDED_REF', sha: stranded, urlKey: 'STRANDED_URL', url: remote},
      {file: 'ci/fixture_pin.env', key: 'UNPUSHED_REF', sha: unpublished, urlKey: 'UNPUSHED_URL', url: remote},
      {file: 'ci/fixture_pin.env', key: 'LOCAL_STALE_REF', sha: remoteAhead, urlKey: 'LOCAL_STALE_URL', url: remote},
    ];
    const results = auditPins(pins, {
      remote: true,
      repoSpecifications: [
        `POSITIVE_REF=${source}#main`,
        `STRANDED_REF=${source}#main`,
        `UNPUSHED_REF=${source}#main`,
        `LOCAL_STALE_REF=${source}#main`,
      ],
      timeoutMs: 10_000,
    });

    const pass = results.find(result => result.key === 'POSITIVE_REF');
    assert.deepEqual([pass.q1.answer, pass.q2.answer, pass.q3.answer, pass.conclusion],
      ['MET', 'MET', 'MET', 'PASS']);

    const negative = results.find(result => result.key === 'STRANDED_REF');
    assert.deepEqual([negative.q1.answer, negative.q2.answer, negative.q3.answer, negative.conclusion],
      ['MET', 'NOT_MET', 'NOT_MET', 'STRANDED']);

    const unpushed = results.find(result => result.key === 'UNPUSHED_REF');
    assert.deepEqual([unpushed.q1.answer, unpushed.q2.answer, unpushed.q3.answer, unpushed.conclusion],
      ['MET', 'MET', 'NOT_MET', 'UNPUSHED']);

    const localStale = results.find(result => result.key === 'LOCAL_STALE_REF');
    assert.deepEqual([localStale.q1.answer, localStale.q2.answer, localStale.q3.answer, localStale.conclusion],
      ['MET', 'NOT_MET', 'MET', 'LOCAL_STALE_OR_DIVERGED']);
    console.log('GATEARM POSITIVE q1=MET q2=MET q3=MET conclusion=PASS');
    console.log('GATEARM NEGATIVE existing=MET authority=NOT_MET fetch_head=NOT_MET conclusion=STRANDED');
    console.log('GATEARM UNPUSHED q1=MET q2=MET q3=NOT_MET conclusion=UNPUSHED');
    console.log('GATEARM LOCAL_STALE q1=MET q2=NOT_MET q3=MET conclusion=LOCAL_STALE_OR_DIVERGED');
  } finally {
    fs.rmSync(fixture, {recursive: true, force: true});
  }
});

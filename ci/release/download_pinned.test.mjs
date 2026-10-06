import {test} from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import os from 'node:os';
import {spawnSync} from 'node:child_process';
import {digest} from './bootstrap_store.mjs';

// Only the remote transport is substituted. The CLI, release selection,
// digest verification, extraction and consumer bytes are the production path.
function fixture(fn) {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), 'persistent-archive-'));
  try {
    const payload = path.join(root, 'payload'); fs.mkdirSync(payload);
    fs.writeFileSync(path.join(payload, 'manifest.json'), 'reviewed producer bytes');
    const zip = path.join(root, 'original.zip');
    assert.equal(spawnSync('zip', ['-q', zip, 'manifest.json'], {cwd: payload}).status, 0);
    const bin = path.join(root, 'bin'); fs.mkdirSync(bin);
    fs.writeFileSync(path.join(bin, 'gh'), '#!/bin/sh\n[ "$1" = api ] && [ "$2" = repos/cjcj-dev/cjcj/releases/assets/789 ] && [ "$3" = -H ] && [ "$4" = "Accept: application/octet-stream" ] || exit 91\ncat "$TEST_ARCHIVE"\n', {mode: 0o755});
    const pinFile = path.join(root, 'pin.json');
    const pin = {version: 1, artifacts: {456: {repository: 'cjcj-dev/cjcj', asset: 789,
      prerelease: true, release_sha256: digest(fs.readFileSync(zip))}}};
    const save = () => fs.writeFileSync(pinFile, JSON.stringify(pin)); save();
    const env = {...process.env, PATH: `${bin}:${process.env.PATH}`, TEST_ARCHIVE: zip, BOOTSTRAP_ARCHIVES_PIN: pinFile};
    const run = (entry = 'cli') => {
      const destination = path.join(root, `out-${Math.random()}`);
      const args = entry === 'cli' ? [new URL('./download_pinned.mjs', import.meta.url).pathname,
        'cjcj-dev/cjcj', '456', destination] : ['--input-type=module', '-e',
        `import {bootstrapArtifact} from ${JSON.stringify(new URL('./bootstrap_artifact.mjs', import.meta.url).href)}; import fs from 'node:fs'; const result=bootstrapArtifact(undefined,'cjcj-dev/cjcj',456,${JSON.stringify(destination)},'AST_SUPPORT'); console.log('CONSUMER='+fs.readFileSync(result+'/manifest.json','utf8'));`];
      return {destination, ...spawnSync(process.execPath, args, {env, encoding: 'utf8'})};
    };
    fn({root, pin, save, zip, run});
  } finally { fs.rmSync(root, {recursive: true, force: true}); }
}
for (const entry of ['cli', 'bootstrap']) {
  test(`${entry}: persistent producer bytes reach the consumer`, () => fixture(({run}) => {
    const result = run(entry);
    const file = path.join(result.destination, 'manifest.json');
    const observed = {rc: result.status, bytes: entry === 'cli'
      ? (fs.existsSync(file) ? fs.readFileSync(file, 'utf8') : null)
      : (/CONSUMER=(.*)/.exec(result.stdout)?.[1] ?? null)};
    console.log(`TARGET ${entry} acceptance ${JSON.stringify(observed)}`);
    assert.deepEqual(observed, {rc: 0, bytes: 'reviewed producer bytes'},
      'verified producer bytes must reach consumer');
    assert.match(result.stdout, /PERSISTENT_ARCHIVE_VERIFIED artifact=456 asset=789 sha256=[a-f0-9]{64}/);
    console.log(`ASSERT ${entry} verified producer bytes reached consumer`);
  }));
  test(`${entry}: tampered sha256 pin rejects before extraction; restored pin passes`, () => fixture(({pin, save, run}) => {
    const original = pin.artifacts[456].release_sha256;
    pin.artifacts[456].release_sha256 = 'f'.repeat(64); save();
    const rejected = run(entry);
    console.log(`TARGET ${entry} pin rejection rc=${rejected.status}`);
    assert.notEqual(rejected.status, 0, 'tampered sha256 must reject');
    assert.match(rejected.stderr, /bootstrap digest mismatch: artifact-456.zip/);
    if (entry === 'cli') assert.deepEqual(fs.readdirSync(rejected.destination), []);
    console.log(`ASSERT ${entry} tampered pin rejected at target digest`);
    pin.artifacts[456].release_sha256 = original; save();
    const restored = run(entry);
    assert.equal(restored.status, 0, restored.stderr);
    console.log(`ASSERT ${entry} restored pin accepted`);
  }));
  test(`${entry}: tampered asset bytes reject at the reviewed sha256`, () => fixture(({zip, run}) => {
    fs.appendFileSync(zip, 'changed producer bytes');
    const result = run(entry);
    console.log(`TARGET ${entry} asset rejection rc=${result.status}`);
    assert.notEqual(result.status, 0, 'tampered asset must reject');
    assert.match(result.stderr, /bootstrap digest mismatch: artifact-456.zip/);
    console.log(`ASSERT ${entry} corrupted producer rejected at target digest`);
  }));
}
test('missing persistent pin refuses artifact fallback', () => fixture(({pin, save, run}) => {
  delete pin.artifacts[456]; save();
  const result = run('bootstrap');
  assert.notEqual(result.status, 0);
  assert.match(result.stderr, /PERSISTENT_ARCHIVE_PIN_MISSING artifact=456/);
}));

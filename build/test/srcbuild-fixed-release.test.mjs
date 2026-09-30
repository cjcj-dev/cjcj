import assert from 'node:assert/strict';
import crypto from 'node:crypto';
import fs from 'node:fs';
import path from 'node:path';
import {spawnSync} from 'node:child_process';
import test from 'node:test';
import {fixture} from '../../ci/release/prepare_bootstrap_fixture.mjs';

const entry = new URL('../../ci/release/acquire_fixed_tuple.mjs', import.meta.url).pathname;
const hash = file => crypto.createHash('sha256').update(fs.readFileSync(file)).digest('hex');

function acquire(inputs) {
  return spawnSync(process.execPath, ['--import', inputs.transport, entry,
    path.join(inputs.dir, 'native-tuple'), path.join(inputs.dir, 'fixed-tools')],
  {env: inputs.env, encoding: 'utf8'});
}

for (const mode of ['release', 'depot']) {
  test(`native and bootstrap ${mode} acquisition publish identical fixed-tool bytes`, () => fixture(inputs => {
    inputs.env.CJCJ_BOOTSTRAP_SOURCE = mode;
    const native = acquire(inputs);
    const bootstrap = inputs.run();
    const identities = /^BOOTSTRAP_INPUT_IDENTITIES=(.+)$/m.exec(bootstrap.stdout)?.[1];
    const expected = identities ? JSON.parse(identities).colour_tuple : {};
    const actual = Object.fromEntries(Object.keys(expected).filter(name => name.startsWith('fixed-llc/'))
      .map(name => {
        const file = path.join(inputs.dir, 'fixed-tools', path.basename(name));
        return [name, fs.existsSync(file) ? hash(file) : null];
      }));
    console.log(`NATIVE_TUPLE_ASSERT mode=${mode} native=${native.status} bootstrap=${bootstrap.status} ${JSON.stringify(actual)}`);
    assert.deepEqual({native: native.status, bootstrap: bootstrap.status, actual},
      {native: 0, bootstrap: 0, actual: Object.fromEntries(Object.entries(expected).filter(([name]) => name.startsWith('fixed-llc/')))});
    assert.equal(Object.keys(actual).length, 5);
    fs.writeFileSync(path.join(inputs.dir, 'fixed-tools/opt.gz'), 'altered local copy');
    const restored = acquire(inputs);
    assert.equal(restored.status, 0, restored.stderr);
    assert.equal(hash(path.join(inputs.dir, 'fixed-tools/opt.gz')), expected['fixed-llc/opt.gz']);
  }));
}

for (const defect of ['asset', 'sums', 'unavailable']) {
  test(`native shared acquisition rejects ${defect} before fixed-tool publication`, () => fixture(inputs => {
    inputs.env.CJCJ_BOOTSTRAP_SOURCE = 'release';
    if (defect === 'asset') fs.writeFileSync(inputs.env.FIXTURE_RELEASE_FILE, 'changed release bytes');
    if (defect === 'sums') inputs.env.LLVM_TUPLE_SUMS_SHA = '0'.repeat(64);
    if (defect === 'unavailable') inputs.env.FIXTURE_RELEASE_UNAVAILABLE = '1';
    const result = acquire(inputs);
    const marker = {asset: 'bootstrap digest mismatch: SHA256SUMS',
      sums: 'colour tuple SHA256SUMS disagrees', unavailable: 'bootstrap GitHub request failed: 404'}[defect];
    const observed = {rc: result.status, rejected: result.stderr.includes(marker),
      published: fs.existsSync(path.join(inputs.dir, 'fixed-tools'))};
    console.log(`NATIVE_TUPLE_REJECTION_ASSERT ${defect} ${JSON.stringify(observed)}`);
    assert.deepEqual(observed, {rc: 1, rejected: true, published: false});
  }));
}

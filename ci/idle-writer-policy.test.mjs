import assert from 'node:assert/strict';
import fs from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';
import {spawnSync} from 'node:child_process';
import test from 'node:test';
import {campaignFixture, rebind} from './gc-campaign-fixture.mjs';
const repo = path.resolve(import.meta.dirname, '..');
async function fixture(t, mutate) {
  const root = await fs.mkdtemp(path.join(os.tmpdir(), 'g14-v2-'));
  t.after(() => fs.rm(root, {recursive: true, force: true}));
  await campaignFixture(root, 'G14', repo, mutate);
  return root;
}
function gate(root) {
  const result = spawnSync(process.execPath, [path.join(repo, 'ci/release-gates.mjs'), 'G14', '--repo', repo, '--evidence', root, '--json'], {encoding: 'utf8'});
  return {rc: result.status, ...JSON.parse(result.stdout)};
}
test('G14 accepts single-profile O0/O2 verification without the deleted FYS policy', async t => {
  const value = gate(await fixture(t));
  assert.equal(value.rc, 0, JSON.stringify(value));
  assert.equal(value.samples, 40);
});
test('G14 rejects an absent O2 sample', async t => {
  const root = await fixture(t);
  const file = path.join(root, 'campaign.json');
  const data = JSON.parse(await fs.readFile(file, 'utf8'));
  data.receipts.pop();
  await fs.writeFile(file, JSON.stringify(data));
  await rebind(root, 'G14', repo);
  assert.match(gate(root).value, /incomplete run population/);
});
test('G14 observes verify mode and rejects an O2 remembered error', async t => {
  const root = await fixture(t, data => { if (data.receipt.load === 'O2' && data.receipt.round === 1) data.log += 'Missing remembered field 0x100\n'; });
  const result = gate(root);
  assert.equal(result.rc, 1);
  assert.deepEqual(result.checks.filter(c => c.status !== 'MET').map(c => c.id), ['F3']);
});
test('G14 rejects disabling remembered verification in the actual receipt', async t => {
  const root = await fixture(t, data => { if (data.receipt.round === 1) data.receipt.env.ZVerifyRemembered = '0'; });
  const result = gate(root);
  assert.equal(result.rc, 2);
  assert.match(result.value, /run environment mismatch/);
});

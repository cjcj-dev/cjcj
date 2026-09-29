import assert from 'node:assert/strict';
import fs from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';
import {spawnSync} from 'node:child_process';
import {createHash} from 'node:crypto';
import test from 'node:test';

const repo = path.resolve(import.meta.dirname, '..');
async function fixture(t) {
  const root = await fs.mkdtemp(path.join(process.env.TMPDIR || os.tmpdir(), 'colour-sdk-test-'));
  t.after(() => fs.rm(root, {recursive: true, force: true}));
  await fs.mkdir(path.join(root, 'ci'));
  await fs.mkdir(path.join(root, '.platform-ci'));
  for (const file of ['prepare-colour-sdk.mjs', 'with-colour-sdk.mjs', 'colour-std-pin.json']) {
    const bytes = await fs.readFile(path.join(repo, 'ci', file));
    await fs.writeFile(path.join(root, 'ci', file), bytes);
    console.log(`PRODUCT ${file} sha256=${createHash('sha256').update(bytes).digest('hex')}`);
  }
  const state = {host: path.join(root, 'host'), sdk: path.join(root, 'target'),
    runtime: path.join(root, 'patched-runtime/lib/linux_x86_64_cjnative'), tuple: 'linux_x86_64_cjnative'};
  await fs.mkdir(state.host);
  await fs.writeFile(path.join(root, '.platform-ci/colour-sdk.json'), JSON.stringify(state));
  return {root, state};
}
for (const mode of ['build', 'run']) {
  test(`real ${mode} wrapper forwards the selected SDK and loader domain`, async t => {
    const {root, state} = await fixture(t);
    const result = spawnSync(process.execPath, [path.join(root, 'ci/with-colour-sdk.mjs'), mode, '--',
      process.execPath, '-e', 'console.log(JSON.stringify(process.env))'],
    {encoding: 'utf8', env: {...process.env, LD_LIBRARY_PATH: '/unrelated-inherited-runtime'}});
    assert.equal(result.status, 0, result.stderr);
    const child = JSON.parse(result.stdout);
    assert.equal(child.CANGJIE_HOME, state.sdk);
    const expected = mode === 'build' ? path.join(state.host, 'runtime/lib', state.tuple) : state.runtime;
    console.log(`TARGET_ASSERT mode=${mode} loader=${child.LD_LIBRARY_PATH} expected=${expected}`);
    assert.equal(child.LD_LIBRARY_PATH.split(':')[0], expected, 'selected loader domain');
    assert.equal(child.LD_LIBRARY_PATH.includes('/unrelated-inherited-runtime'), false);
    assert.equal(child.CJCJ_PATCHED_RUNTIME_LIB_DIR, state.runtime);
    assert.equal(child.PATH.split(':')[0], path.join(state.host, 'bin'));
  });
}
test('real preparation entry refuses the published std from a different runtime generation', async t => {
  const {root, state} = await fixture(t);
  const pin = JSON.parse(await fs.readFile(path.join(root, 'ci/colour-std-pin.json'), 'utf8'));
  const result = spawnSync(process.execPath, [path.join(root, 'ci/prepare-colour-sdk.mjs'), 'absent-runtime'],
    {encoding: 'utf8', env: {...process.env, CANGJIE_HOME: state.host, RUNTIME_REF: '5d35d19345d76dfa585fabfd562df19336fe8e5e'}});
  console.log(`TARGET_ASSERT runtime-generation rc=${result.status} pin=${pin.runtime_sha}`);
  assert.notEqual(result.status, 0);
  assert.match(result.stderr, /COLOUR_STD_NOT_RUN: manifest runtime=4c4cbf53.*required=5d35d193/);
  assert.equal(await fs.stat(path.join(root, 'patched-runtime')).then(() => true, () => false), false);
});

import assert from 'node:assert/strict';
import fs from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';
import {spawnSync} from 'node:child_process';
import test from 'node:test';
import {readHostToolchainPin} from '../../ci/host-toolchain-pin.mjs';
import {baseSdkDownload, RELEASE_HOST_TOOLCHAIN} from '../lib/release-component-provenance.mjs';
import {REVIEWED_GATE_HOST_TOOLCHAIN} from '../lib/release-gate-apparatus.mjs';

test('release archive and apparatus selectors consume the source host pin', () => {
  const pin = readHostToolchainPin();
  assert.equal(RELEASE_HOST_TOOLCHAIN, pin);
  assert.equal(REVIEWED_GATE_HOST_TOOLCHAIN, pin);
  for (const platform of ['linux-x64', 'linux-aarch64', 'darwin-x64', 'darwin-arm64', 'windows-x64']) {
    assert.equal(baseSdkDownload(platform, pin).version, pin.replace(/^nightly-/, ''));
  }
});

test('a changed pin reaches both release selectors and requires matching archive identities', async t => {
  const fixture = await fs.mkdtemp(path.join(os.tmpdir(), 'release-pin-'));
  t.after(() => fs.rm(fixture, {recursive: true, force: true}));
  const root = path.resolve(import.meta.dirname, '../..');
  for (const relative of [
    'ci/host-toolchain-pin.mjs', 'ci/release/base-sdk-identities.json',
    'build/lib/release-component-provenance.mjs', 'build/lib/release-gate-apparatus.mjs',
    'build/lib/targets.mjs', 'build/lib/errors.mjs',
  ]) {
    const destination = path.join(fixture, relative);
    await fs.mkdir(path.dirname(destination), {recursive: true});
    await fs.copyFile(path.join(root, relative), destination);
  }
  const pin = 'nightly-control';
  await fs.writeFile(path.join(fixture, 'ci/host_sdk_pin.env'), `CJCJ_TOOLCHAIN=${pin}\n`);
  const entry = [
    "import {baseSdkDownload, RELEASE_HOST_TOOLCHAIN} from './build/lib/release-component-provenance.mjs';",
    "import {REVIEWED_GATE_HOST_TOOLCHAIN} from './build/lib/release-gate-apparatus.mjs';",
    'const value = {release: RELEASE_HOST_TOOLCHAIN, apparatus: REVIEWED_GATE_HOST_TOOLCHAIN};',
    "try { value.download = baseSdkDownload('linux-x64', RELEASE_HOST_TOOLCHAIN); }",
    'catch (error) { value.error = error.message; }',
    'console.log(JSON.stringify(value));',
  ].join('\n');
  const run = () => {
    const result = spawnSync(process.execPath, ['--input-type=module', '-e', entry], {
      cwd: fixture, encoding: 'utf8',
    });
    assert.equal(result.status, 0, result.stderr);
    return JSON.parse(result.stdout);
  };
  const unregistered = run();
  assert.equal(unregistered.release, pin);
  assert.equal(unregistered.apparatus, pin);
  assert.match(unregistered.error, /no pinned archive identity/);
  const identityPath = path.join(fixture, 'ci/release/base-sdk-identities.json');
  const identities = JSON.parse(await fs.readFile(identityPath, 'utf8'));
  identities.version = 'control';
  await fs.writeFile(identityPath, JSON.stringify(identities));
  const registered = run();
  assert.equal(registered.error, undefined);
  assert.equal(registered.download.version, 'control');
});

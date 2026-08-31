import assert from 'node:assert/strict';
import fs from 'node:fs/promises';
import path from 'node:path';
import test from 'node:test';
import {baseSdkDownload} from '../build/lib/release-component-provenance.mjs';
import {
  hostToolchainFromCjcVersion,
  requireHostToolchain,
  requireMatchingBaseSdkToolchain,
} from './host-toolchain-pin.mjs';

const root = path.resolve(import.meta.dirname, '..');
const pinPath = path.join(root, 'ci', 'cjpm_pin.env');
const loadCommand = 'cat ci/cjpm_pin.env >> "$GITHUB_ENV"';

async function filesBelow(directory) {
  const found = [];
  for (const entry of await fs.readdir(directory, {withFileTypes: true})) {
    const target = path.join(directory, entry.name);
    if (entry.isDirectory()) found.push(...await filesBelow(target));
    else found.push(target);
  }
  return found;
}

async function hostPin() {
  const text = await fs.readFile(pinPath, 'utf8');
  const match = text.match(/^CJCJ_TOOLCHAIN=(\S+)$/m);
  assert.ok(match, 'ci/cjpm_pin.env must define CJCJ_TOOLCHAIN');
  return match[1];
}

test('host toolchain consumers fail closed when the pin was not loaded', () => {
  assert.throws(() => requireHostToolchain({}), /CJCJ_TOOLCHAIN is required/);
  assert.throws(() => requireHostToolchain({CJCJ_TOOLCHAIN: '   '}), /CJCJ_TOOLCHAIN is required/);
});

test('host toolchain consumers accept the value loaded from the sole pin', async () => {
  const pin = await hostPin();
  assert.equal(requireHostToolchain({CJCJ_TOOLCHAIN: pin}), pin);
});

test('the ordinary host nightly literal has one pin and the release exception is explicit', async () => {
  const files = [
    ...await filesBelow(path.join(root, 'ci')),
    ...await filesBelow(path.join(root, '.github', 'workflows')),
  ];
  const offenders = [];
  for (const file of files) {
    if (file === pinPath || file.endsWith('/.github/workflows/build-release-package.yml')) continue;
    const text = await fs.readFile(file, 'utf8');
    if (/nightly-\d+\.\d+\.\d+-alpha\.\d+/.test(text)) {
      offenders.push(path.relative(root, file));
    }
  }
  assert.deepEqual(offenders, []);
  const release = await fs.readFile(path.join(root, '.github', 'workflows', 'build-release-package.yml'), 'utf8');
  assert.equal(release.match(/^  RELEASE_HOST_TOOLCHAIN: nightly-\S+$/gm)?.length, 1);
  assert.match(release, /Five-platform 1\.3 archive hashes do not exist yet/);
  assert.match(release, /smoke changing from 13\/15 to 0\/15/);
});

test('every workflow host consumer loads ci/cjpm_pin.env after checkout', async () => {
  const expectedLoads = new Map([
    ['build-cjpm.yml', 1],
    ['build-windows-runtime.yml', 1],
    ['ci.yml', 2],
    ['platform-matrix.yml', 1],
    ['srcbuild.yml', 1],
  ]);
  const workflows = path.join(root, '.github', 'workflows');
  for (const [name, count] of expectedLoads) {
    const text = await fs.readFile(path.join(workflows, name), 'utf8');
    assert.equal(text.split(loadCommand).length - 1, count, name);
  }

  const windowsRuntime = await fs.readFile(path.join(workflows, 'build-windows-runtime.yml'), 'utf8');
  assert.ok(!windowsRuntime.includes('inputs.toolchain'));
  const platformMatrix = await fs.readFile(path.join(workflows, 'platform-matrix.yml'), 'utf8');
  assert.ok(!platformMatrix.includes('sdk_archive:'));
  assert.ok(!platformMatrix.includes('SDK_ARCHIVE:'));
  const release = await fs.readFile(path.join(workflows, 'release.yml'), 'utf8');
  assert.ok(!release.includes('CJCJ_TOOLCHAIN'));
});

test('base SDK linking rejects a release archive aimed at a differently named host directory', () => {
  assert.throws(() => requireMatchingBaseSdkToolchain({
    hostToolchain: 'nightly-host-control',
    baseSdkToolchain: 'nightly-base-control',
  }), /refusing to link base SDK/);
  assert.equal(requireMatchingBaseSdkToolchain({
    hostToolchain: 'nightly-same-control',
    baseSdkToolchain: 'nightly-same-control',
  }), 'nightly-same-control');
});

test('measured cjc version is converted to the exact nightly identity', () => {
  const version = '1.3.0-alpha.20260831010012';
  assert.equal(hostToolchainFromCjcVersion(
    `Cangjie Compiler: ${version} (cjnative)\nTarget: x86_64-unknown-linux-gnu\n`,
  ), `nightly-${version}`);
  assert.throws(() => hostToolchainFromCjcVersion('not a compiler version'), /did not report/);
});

test('release base SDK dry-run resolves the explicit 1.2 exception, not the ordinary 1.3 host pin', async () => {
  const release = await fs.readFile(path.join(root, '.github', 'workflows', 'build-release-package.yml'), 'utf8');
  const releaseHost = release.match(/^  RELEASE_HOST_TOOLCHAIN: (\S+)$/m)?.[1];
  const ordinaryHost = await hostPin();
  assert.ok(releaseHost);
  assert.notEqual(releaseHost, ordinaryHost);
  for (const platform of ['linux-x64', 'linux-aarch64', 'darwin-x64', 'darwin-arm64', 'windows-x64']) {
    assert.match(baseSdkDownload(platform, releaseHost).sha256, /^[0-9a-f]{64}$/);
  }
  assert.throws(() => baseSdkDownload('linux-x64', ordinaryHost), /no pinned archive identity/);
  assert.match(release, /--toolchain "\$RELEASE_HOST_TOOLCHAIN"/);
  assert.match(release, /--base-sdk-id "\$RELEASE_HOST_TOOLCHAIN"/);
});

test('both JavaScript entry points require the loaded environment value', async () => {
  for (const name of ['ci/setup_sdk.mjs', 'ci/platform_matrix/build_cjcj.mjs']) {
    const text = await fs.readFile(path.join(root, name), 'utf8');
    assert.ok(text.includes('requireHostToolchain()'), name);
    assert.ok(!text.includes('process.env.CJCJ_TOOLCHAIN ||'), name);
  }
});

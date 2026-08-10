import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import test from 'node:test';
import {
  HLE_PROVENANCE,
  parseToolsPin,
  verifyComponentProvenance,
  writeComponentProvenance,
} from '../lib/release-component-provenance.mjs';

const REPOSITORY = 'https://github.com/cjcj-dev/cangjie-tools.git';
const COMMIT = '2003d20ae84050fd2f70525bf00be214542113a6';

function stage(contents = 'hle-binary') {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), 'hle-artifact-'));
  const binary = path.join(root, 'hle');
  fs.writeFileSync(binary, contents);
  return {root, binary, sidecar: path.join(root, HLE_PROVENANCE)};
}

const verify = ({binary, sidecar}) => verifyComponentProvenance({
  component: 'hle', artifactName: 'hle', binary, sidecar,
  platform: 'linux-x64', expectedRepository: REPOSITORY, expectedCommit: COMMIT,
});

test('the tools pin supplies hle its source identity', () => {
  const pin = parseToolsPin(fs.readFileSync(
    new URL('../../ci/source_pin.env', import.meta.url), 'utf8'));
  assert.match(pin.repository, /^https:\/\//);
  assert.match(pin.commit, /^[0-9a-f]{40}$/);
});

test('an hle sidecar round-trips and pins the binary it was written for', async () => {
  const fixture = stage();
  try {
    const written = await writeComponentProvenance({
      component: 'hle', binary: fixture.binary, destination: fixture.sidecar,
      platform: 'linux-x64', repository: REPOSITORY, commit: COMMIT,
    });
    assert.equal(written.component, 'hle');
    assert.equal(written.artifact.path, 'hle');
    assert.equal(written.artifact.sha256, createHash('sha256').update('hle-binary').digest('hex'));
    assert.deepEqual(await verify(fixture), written);
  } finally {
    fs.rmSync(fixture.root, {recursive: true, force: true});
  }
});

test('a swapped hle binary is rejected rather than installed', async () => {
  // Without this the sidecar is decoration: the release would happily install
  // whatever binary sat next to a well-formed json file.
  const fixture = stage();
  try {
    await writeComponentProvenance({
      component: 'hle', binary: fixture.binary, destination: fixture.sidecar,
      platform: 'linux-x64', repository: REPOSITORY, commit: COMMIT,
    });
    fs.writeFileSync(fixture.binary, 'someone-elses-hle');
    await assert.rejects(verify(fixture), /hle provenance binary SHA-256 mismatch/);
  } finally {
    fs.rmSync(fixture.root, {recursive: true, force: true});
  }
});

test('an hle sidecar cannot pass as some other component', async () => {
  const fixture = stage();
  try {
    await writeComponentProvenance({
      component: 'cjpm', binary: fixture.binary, destination: fixture.sidecar,
      platform: 'linux-x64', repository: REPOSITORY, commit: COMMIT,
    });
    await assert.rejects(verify(fixture), /component/);
  } finally {
    fs.rmSync(fixture.root, {recursive: true, force: true});
  }
});

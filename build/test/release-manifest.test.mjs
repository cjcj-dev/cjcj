import assert from 'node:assert/strict';
import fs from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';
import {spawnSync} from 'node:child_process';
import test from 'node:test';
import {fileURLToPath} from 'node:url';
import {
  RELEASE_SIGNATURE_POLICY,
  writeReleaseManifest,
} from '../lib/release-manifest.mjs';

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..', '..');
const platforms = ['linux-x64', 'linux-aarch64', 'darwin-x64', 'darwin-arm64', 'windows-x64'];

async function fixture() {
  const work = await fs.mkdtemp(path.join(os.tmpdir(), 'release-manifest-'));
  const stage = path.join(work, 'stage');
  const dist = path.join(work, 'dist');
  await fs.mkdir(stage);
  await fs.mkdir(dist);
  const pythonArtifact = path.join(stage, 'third_party', 'python', 'bin', 'python3.11');
  await fs.mkdir(path.dirname(pythonArtifact), {recursive: true});
  await fs.writeFile(pythonArtifact, 'Python 3.11.9 fixture\n');
  return {work, stage, dist, pythonArtifact};
}

function render(dist, output) {
  return spawnSync(process.execPath, [
    path.join(root, 'scripts', 'render_release_notes.mjs'),
    '--version', '0.0.0-test', '--dist', dist, '--output', output,
  ], {encoding: 'utf8'});
}

test('five release manifests carry one nonempty SHA_ONLY policy and notes render it', async () => {
  const {work, stage, dist, pythonArtifact} = await fixture();
  try {
    const {rows} = await writeReleaseManifest({
      stage, platform: platforms[0], pythonArtifact, pythonVersion: '3.11.9',
    });
    assert.equal(rows.length, 8);
    for (const platform of platforms) {
      const platformRows = rows.map(row => ({...row, platform}));
      assert.ok(platformRows.every(row => row.signature_policy === RELEASE_SIGNATURE_POLICY));
      await fs.writeFile(path.join(dist,
        `cjcj-0.0.0-test-${platform}.RELEASE-MANIFEST.jsonl`),
      `${platformRows.map(row => JSON.stringify(row)).join('\n')}\n`);
    }
    const output = path.join(work, 'notes.md');
    const rendered = render(dist, output);
    assert.equal(rendered.status, 0, rendered.stderr);
    assert.match(await fs.readFile(output, 'utf8'), /Signature policy: `SHA_ONLY`\./);
  } finally {
    await fs.rm(work, {recursive: true, force: true});
  }
});

test('empty signature policy fails closed in writer and renderer', async () => {
  const {work, stage, dist, pythonArtifact} = await fixture();
  try {
    await assert.rejects(writeReleaseManifest({
      stage, platform: platforms[0], pythonArtifact, pythonVersion: '3.11.9', signaturePolicy: '',
    }),
      /signature_policy must be SHA_ONLY, got <empty>/);
    const {rows} = await writeReleaseManifest({
      stage, platform: platforms[0], pythonArtifact, pythonVersion: '3.11.9',
    });
    rows[0].signature_policy = '';
    await fs.writeFile(path.join(dist, 'cjcj-0.0.0-test-linux-x64.RELEASE-MANIFEST.jsonl'),
      `${rows.map(row => JSON.stringify(row)).join('\n')}\n`);
    const rendered = render(dist, path.join(work, 'notes.md'));
    assert.notEqual(rendered.status, 0);
    assert.match(rendered.stderr, /release manifests must have one SHA_ONLY signature_policy/);
  } finally {
    await fs.rm(work, {recursive: true, force: true});
  }
});

test('missing Python bundle artifact fails closed', async () => {
  const {work, stage} = await fixture();
  try {
    await assert.rejects(writeReleaseManifest({
      stage,
      platform: platforms[0],
      pythonArtifact: path.join(stage, 'third_party', 'python', 'bin', 'missing-python3.11'),
      pythonVersion: '3.11.9',
    }), /packaged Python 3\.11\.9 artifact is missing/);
  } finally {
    await fs.rm(work, {recursive: true, force: true});
  }
});

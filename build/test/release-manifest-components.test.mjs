import assert from 'node:assert/strict';
import crypto from 'node:crypto';
import fs from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';
import {spawnSync} from 'node:child_process';
import test from 'node:test';
import {
  CJDB_PYTHON_MODULES,
  CJDB_PYTHON_UNIX_MODULES,
  RELEASE_PYTHON_SOURCE_SHA256,
  RELEASE_PYTHON_SOURCE_URL,
  RELEASE_PYTHON_VERSION,
} from '../lib/python-bundle.mjs';
import {RELEASE_MANIFEST, writeReleaseManifest} from '../lib/release-manifest.mjs';

const CJCJ_SHA = '1'.repeat(40);
const RUNTIME_SHA = '2'.repeat(40);
const LLVM_SHA = '3'.repeat(40);
const STD_SHA = '4'.repeat(40);
const CJPM_SHA = '5'.repeat(40);

async function write(root, relative, contents) {
  const file = path.join(root, relative);
  await fs.mkdir(path.dirname(file), {recursive: true});
  await fs.writeFile(file, contents);
  return file;
}

function digest(contents) {
  return crypto.createHash('sha256').update(contents).digest('hex');
}

test('release manifest keeps every component and records a removed stamp', async t => {
  const root = await fs.mkdtemp(path.join(os.tmpdir(), 'release-manifest-'));
  t.after(() => fs.rm(root, {recursive: true, force: true}));
  const stage = path.join(root, 'stage');
  const runtime = await write(stage, 'runtime/lib/linux_x86_64_cjnative/libcangjie-runtime.so',
    `runtime\0CJRT-COMMIT:${RUNTIME_SHA}\0`);
  await write(stage, 'bin/cjc', `compiler\0CJCJ-COMMIT:${CJCJ_SHA}\0`);
  await write(stage, 'third_party/llvm/bin/llc', `llc\0CJLLVM-COMMIT:${LLVM_SHA}\0`);
  const opt = await write(stage, 'third_party/llvm/bin/opt', `opt\0CJLLVM-COMMIT:${LLVM_SHA}\0`);
  const cjpmContents = 'patched-cjpm-without-an-embedded-stamp';
  await write(stage, 'tools/bin/cjpm', cjpmContents);
  const provenance = await write(stage, 'PROVENANCE.txt', [
    `CJSTD-COMMIT:${STD_SHA} BUILT-BY:${CJCJ_SHA}`,
    `STD_SOURCE_COMMIT = ${STD_SHA}`,
    'ARTIFACT-SHA256:',
    '',
  ].join('\n'));
  const llvmManifest = await write(root, 'llvm-tools.manifest', [
    `LLVM_SHA=${LLVM_SHA}`,
    `LLC_SHA256=${'6'.repeat(64)}`,
    `OPT_SHA256=${'7'.repeat(64)}`,
    '',
  ].join('\n'));
  const pythonArtifact = await write(stage, 'third_party/python/bin/python3.11',
    'Python 3.11.9 fixture\n');
  const pythonMetadata = {
    schema: 1,
    platform: 'linux-x64',
    version: RELEASE_PYTHON_VERSION,
    source_type: 'python.org-source-native',
    source_url: RELEASE_PYTHON_SOURCE_URL,
    source_sha256: RELEASE_PYTHON_SOURCE_SHA256,
    configure_args: '--prefix=<bundle> --enable-shared --without-ensurepip',
    configure_environment: 'LDFLAGS=-Wl,-rpath,$ORIGIN/../lib',
    required_modules: [...CJDB_PYTHON_MODULES],
    required_unix_modules: [...CJDB_PYTHON_UNIX_MODULES],
  };
  const pythonMetadataArtifact = await write(stage, 'third_party/python/PYTHON-BUNDLE.json',
    `${JSON.stringify(pythonMetadata, null, 2)}\n`);

  const options = {
    stage,
    platform: 'linux-x64',
    runtimeArtifact: runtime,
    stdProvenance: provenance,
    llvmManifest,
    baseSdkId: 'nightly-fixture',
    cjcjCommit: CJCJ_SHA,
    runtimeCommit: RUNTIME_SHA,
    stdRepository: 'https://github.com/cjcj-dev/cangjie-runtime.git',
    cjpmRepository: 'https://github.com/cjcj-dev/cangjie-tools.git',
    cjpmCommit: CJPM_SHA,
    pythonArtifact,
    pythonMetadata,
    pythonMetadataArtifact,
    pythonVersion: RELEASE_PYTHON_VERSION,
  };
  const positive = await writeReleaseManifest(options);
  assert.equal(positive.rows.length, 8);
  assert.deepEqual(positive.rows.map(row => row.component),
    ['base-sdk', 'cjcj', 'runtime', 'llvm-llc', 'llvm-opt', 'std', 'cjpm', 'python']);
  assert.equal(positive.rows.find(row => row.component === 'llvm-opt').embedded_stamp,
    `CJLLVM-COMMIT:${LLVM_SHA}`);
  assert.equal(positive.rows.find(row => row.component === 'std').embedded_stamp, 'no-stamp');
  assert.equal(positive.rows.find(row => row.component === 'cjpm').artifact.sha256, digest(cjpmContents));
  assert.match(positive.rows.find(row => row.component === 'base-sdk').source.commit,
    /^unavailable: official SDK nightly-fixture/);

  await fs.writeFile(opt, 'opt-with-stamp-deliberately-removed');
  const negative = await writeReleaseManifest(options);
  assert.equal(negative.rows.find(row => row.component === 'llvm-opt').embedded_stamp, 'no-stamp');
  assert.ok(negative.rows.every(row => Object.values({
    repository: row.source.repository,
    commit: row.source.commit,
    path: row.artifact.path,
    sha256: row.artifact.sha256,
    stamp: row.embedded_stamp,
  }).every(value => typeof value === 'string' && value.length > 0)));

  const dist = path.join(root, 'dist');
  await fs.mkdir(dist);
  await fs.copyFile(negative.destination,
    path.join(dist, `cjcj-9.9.9-linux-x64.${RELEASE_MANIFEST}`));
  const notes = path.join(root, 'notes.md');
  const rendered = spawnSync(process.execPath, [
    path.resolve('scripts/render_release_notes.mjs'),
    '--version', '9.9.9', '--dist', dist, '--output', notes,
  ], {encoding: 'utf8'});
  assert.equal(rendered.status, 0, rendered.stderr);
  const notesText = await fs.readFile(notes, 'utf8');
  assert.match(notesText, /\| cjcj \| 1111111111111111111111111111111111111111 \| [0-9a-f]{64} \|/);
  assert.match(notesText, /\| llvm-opt \| 3333333333333333333333333333333333333333 \| [0-9a-f]{64} \| no-stamp \|/);
  console.log(`NEGATIVE-CONTROL llvm-opt ${positive.rows.find(row => row.component === 'llvm-opt').embedded_stamp} -> ${negative.rows.find(row => row.component === 'llvm-opt').embedded_stamp}`);
  console.log(`RELEASE-NOTES-BEGIN\n${notesText.trim()}\nRELEASE-NOTES-END`);
});

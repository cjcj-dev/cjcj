import assert from 'node:assert/strict';
import fs from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';
import {spawnSync} from 'node:child_process';
import test from 'node:test';
import {fileURLToPath} from 'node:url';
import {
  CJDB_PYTHON_MODULES,
  CJDB_PYTHON_UNIX_MODULES,
  RELEASE_PYTHON_SOURCE_SHA256,
  RELEASE_PYTHON_SOURCE_URL,
  RELEASE_PYTHON_VERSION,
} from '../lib/python-bundle.mjs';
import {
  RELEASE_SIGNATURE_POLICY,
  writeReleaseManifest,
} from '../lib/release-manifest.mjs';
import {
  GATE_APPARATUS_COMPONENT,
  GATE_APPARATUS_PROVENANCE,
  KNOWN_GATE_APPARATUS_LIMITATIONS,
  REVIEWED_GATE_HOST_TOOLCHAIN,
} from '../lib/release-gate-apparatus.mjs';

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..', '..');
const platforms = ['linux-x64', 'linux-aarch64', 'darwin-x64', 'darwin-arm64', 'windows-x64'];
const CJCJ_SHA = '1'.repeat(40);
const RUNTIME_SHA = '2'.repeat(40);
const LLVM_SHA = '3'.repeat(40);
const gateRuntimeByPlatform = {
  'linux-x64': ['runtime/lib/linux_x86_64_cjnative/libcangjie-runtime.so', 'nm -D --defined-only'],
  'linux-aarch64': ['runtime/lib/linux_aarch64_cjnative/libcangjie-runtime.so', 'nm -D --defined-only'],
  'darwin-x64': ['runtime/lib/darwin_x86_64_cjnative/libcangjie-runtime.dylib', 'nm -gU'],
  'darwin-arm64': ['runtime/lib/darwin_aarch64_cjnative/libcangjie-runtime.dylib', 'nm -gU'],
  'windows-x64': ['runtime/lib/windows_x86_64_cjnative/libcangjie-runtime.dll', 'nm -g --defined-only'],
};

async function fixture() {
  const work = await fs.mkdtemp(path.join(os.tmpdir(), 'release-manifest-'));
  const stage = path.join(work, 'stage');
  const dist = path.join(work, 'dist');
  await fs.mkdir(stage);
  await fs.mkdir(dist);
  await fs.mkdir(path.join(stage, 'bin'), {recursive: true});
  await fs.writeFile(path.join(stage, 'bin', 'cjc'),
    `compiler\0CJCJ-COMMIT:${CJCJ_SHA}\0`);
  const runtimeArtifact = path.join(stage, 'runtime', 'lib', 'linux_x86_64_cjnative',
    'libcangjie-runtime.so');
  await fs.mkdir(path.dirname(runtimeArtifact), {recursive: true});
  await fs.writeFile(runtimeArtifact, `runtime\0CJRT-COMMIT:${RUNTIME_SHA}\0`);
  const llvmBin = path.join(stage, 'third_party', 'llvm', 'bin');
  await fs.mkdir(llvmBin, {recursive: true});
  await fs.writeFile(path.join(llvmBin, 'llc'), `llc\0CJLLVM-COMMIT:${LLVM_SHA}\0`);
  await fs.writeFile(path.join(llvmBin, 'opt'), `opt\0CJLLVM-COMMIT:${LLVM_SHA}\0`);
  const pythonArtifact = path.join(stage, 'third_party', 'python', 'bin', 'python3.11');
  await fs.mkdir(path.dirname(pythonArtifact), {recursive: true});
  await fs.writeFile(pythonArtifact, 'Python 3.11.9 fixture\n');
  const pythonMetadata = {
    schema: 1,
    platform: platforms[0],
    version: RELEASE_PYTHON_VERSION,
    source_type: 'python.org-source-native',
    source_url: RELEASE_PYTHON_SOURCE_URL,
    source_sha256: RELEASE_PYTHON_SOURCE_SHA256,
    configure_args: '--prefix=<bundle> --enable-shared --without-ensurepip',
    configure_environment: 'LDFLAGS=-Wl,-rpath,$ORIGIN/../lib',
    required_modules: [...CJDB_PYTHON_MODULES],
    required_unix_modules: [...CJDB_PYTHON_UNIX_MODULES],
  };
  const pythonMetadataArtifact = path.join(stage, 'third_party', 'python', 'PYTHON-BUNDLE.json');
  await fs.writeFile(pythonMetadataArtifact, `${JSON.stringify(pythonMetadata, null, 2)}\n`);
  const gateApparatusArtifact = path.join(stage, GATE_APPARATUS_PROVENANCE);
  await fs.writeFile(gateApparatusArtifact, `${JSON.stringify({
    schema: 1,
    component: GATE_APPARATUS_COMPONENT,
    platform: platforms[0],
    gate_host_toolchain: REVIEWED_GATE_HOST_TOOLCHAIN,
    base_sdk: {
      release_repository: 'https://gitcode.com/Cangjie/nightly_build',
      version: REVIEWED_GATE_HOST_TOOLCHAIN.replace(/^nightly-/, ''),
      download_url: 'https://gitcode.com/Cangjie/nightly_build/releases/download/fixture/sdk.tar.gz',
      archive_path: 'sdk.tar.gz',
      archive_sha256: 'a'.repeat(64),
    },
    host_runtime: {
      path: 'runtime/lib/linux_x86_64_cjnative/libcangjie-runtime.so',
      sha256: 'b'.repeat(64),
      g_cjLoadBadMask_count: 0,
      symbol_probe: 'nm -D --defined-only',
    },
    known_apparatus_limitations: KNOWN_GATE_APPARATUS_LIMITATIONS,
  }, null, 2)}\n`);
  const pythonArgs = {
    runtimeArtifact,
    cjcjCommit: CJCJ_SHA,
    runtimeCommit: RUNTIME_SHA,
    llvmCommit: LLVM_SHA,
    pythonArtifact,
    pythonMetadata,
    pythonMetadataArtifact,
    pythonVersion: RELEASE_PYTHON_VERSION,
    baseSdkId: REVIEWED_GATE_HOST_TOOLCHAIN,
    gateApparatusArtifact,
  };
  return {work, stage, dist, pythonArgs};
}

function render(dist, output) {
  return spawnSync(process.execPath, [
    path.join(root, 'scripts', 'render_release_notes.mjs'),
    '--version', '0.0.0-test', '--dist', dist, '--output', output,
  ], {encoding: 'utf8'});
}

test('five release manifests carry one nonempty SHA_ONLY policy and notes render it', async () => {
  const {work, stage, dist, pythonArgs} = await fixture();
  try {
    const {rows} = await writeReleaseManifest({
      stage, platform: platforms[0], ...pythonArgs,
    });
    assert.equal(rows.length, 9);
    const python = rows.find(row => row.component === 'python');
    assert.equal(python.source.commit, RELEASE_PYTHON_VERSION);
    assert.equal(python.source.download_url, RELEASE_PYTHON_SOURCE_URL);
    assert.equal(python.source.archive_sha256, RELEASE_PYTHON_SOURCE_SHA256);
    assert.equal(python.build.configure_args, pythonArgs.pythonMetadata.configure_args);
    assert.match(python.build.provenance_sha256, /^[0-9a-f]{64}$/);
    for (const platform of platforms) {
      const platformRows = structuredClone(rows);
      for (const row of platformRows) row.platform = platform;
      const apparatus = platformRows.find(row => row.component === GATE_APPARATUS_COMPONENT)
        .acceptance_apparatus.host_runtime;
      [apparatus.path, apparatus.symbol_probe] = gateRuntimeByPlatform[platform];
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
  const {work, stage, dist, pythonArgs} = await fixture();
  try {
    await assert.rejects(writeReleaseManifest({
      stage, platform: platforms[0], ...pythonArgs, signaturePolicy: '',
    }),
      /signature_policy must be SHA_ONLY, got <empty>/);
    const {rows} = await writeReleaseManifest({
      stage, platform: platforms[0], ...pythonArgs,
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

test('missing or changed acceptance apparatus fails closed in renderer', async () => {
  const {work, stage, dist, pythonArgs} = await fixture();
  try {
    const {rows} = await writeReleaseManifest({
      stage, platform: platforms[0], ...pythonArgs,
    });
    const manifest = path.join(dist, 'cjcj-0.0.0-test-linux-x64.RELEASE-MANIFEST.jsonl');
    const withoutApparatus = rows.filter(row => row.component !== GATE_APPARATUS_COMPONENT);
    await fs.writeFile(manifest, `${withoutApparatus.map(row => JSON.stringify(row)).join('\n')}\n`);
    const missing = render(dist, path.join(work, 'missing-notes.md'));
    assert.notEqual(missing.status, 0);
    assert.match(missing.stderr, /manifest components mismatch/);

    const changed = structuredClone(rows);
    changed.find(row => row.component === GATE_APPARATUS_COMPONENT)
      .acceptance_apparatus.known_apparatus_limitations.text = 'tampered apparatus limitation';
    await fs.writeFile(manifest, `${changed.map(row => JSON.stringify(row)).join('\n')}\n`);
    const tampered = render(dist, path.join(work, 'tampered-notes.md'));
    assert.notEqual(tampered.status, 0);
    assert.match(tampered.stderr, /does not match the reviewed G8 apparatus evidence/);
  } finally {
    await fs.rm(work, {recursive: true, force: true});
  }
});

test('missing Python bundle artifact fails closed', async () => {
  const {work, stage, pythonArgs} = await fixture();
  try {
    await assert.rejects(writeReleaseManifest({
      stage,
      platform: platforms[0],
      ...pythonArgs,
      pythonArtifact: path.join(stage, 'third_party', 'python', 'bin', 'missing-python3.11'),
    }), /packaged Python 3\.11\.9 artifact is missing/);
  } finally {
    await fs.rm(work, {recursive: true, force: true});
  }
});

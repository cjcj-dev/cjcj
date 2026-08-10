import assert from 'node:assert/strict';
import crypto from 'node:crypto';
import fs from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';
import {spawnSync} from 'node:child_process';
import test from 'node:test';
import {pathToFileURL} from 'node:url';
import {
  BASE_SDK_SOURCE_REASON,
  SOURCE_PROVENANCE_NOT_APPLICABLE,
  SOURCE_PROVENANCE_RESOLVED,
  baseSdkDownload,
} from '../lib/release-component-provenance.mjs';
import {
  GATE_APPARATUS_COMPONENT,
  GATE_APPARATUS_PROVENANCE,
  KNOWN_GATE_APPARATUS_LIMITATIONS,
  REVIEWED_GATE_HOST_TOOLCHAIN,
} from '../lib/release-gate-apparatus.mjs';
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
const OTHER_SHA = '6'.repeat(40);

const writerModule = pathToFileURL(path.resolve('build/lib/release-manifest.mjs')).href;
const writerRunner = [
  "import fs from 'node:fs/promises';",
  `import {writeReleaseManifest} from ${JSON.stringify(writerModule)};`,
  "const options = JSON.parse(await fs.readFile(process.argv[1], 'utf8'));",
  'await writeReleaseManifest(options);',
].join('\n');

test('base SDK provenance maps every release platform to its nightly archive', () => {
  const version = 'nightly-1.2.0-alpha.20260721165458';
  const expected = new Map([
    ['linux-x64', 'cangjie-sdk-linux-x64-1.2.0-alpha.20260721165458.tar.gz'],
    ['linux-aarch64', 'cangjie-sdk-linux-aarch64-1.2.0-alpha.20260721165458.tar.gz'],
    ['darwin-x64', 'cangjie-sdk-mac-x64-1.2.0-alpha.20260721165458.tar.gz'],
    ['darwin-arm64', 'cangjie-sdk-mac-aarch64-1.2.0-alpha.20260721165458.tar.gz'],
    ['windows-x64', 'cangjie-sdk-windows-x64-1.2.0-alpha.20260721165458.zip'],
  ]);
  for (const [platform, archive] of expected) {
    const value = baseSdkDownload(platform, version);
    assert.equal(value.archive, archive);
    assert.ok(value.url.endsWith(`/1.2.0-alpha.20260721165458/${archive}`));
  }
});

async function write(root, relative, contents) {
  const file = path.join(root, relative);
  await fs.mkdir(path.dirname(file), {recursive: true});
  await fs.writeFile(file, contents);
  return file;
}

function digest(contents) {
  return crypto.createHash('sha256').update(contents).digest('hex');
}

function baseSdkProvenance(platform) {
  const download = baseSdkDownload(platform, REVIEWED_GATE_HOST_TOOLCHAIN);
  return {
    schema: 1,
    component: 'base-sdk',
    platform,
    source: {
      status: SOURCE_PROVENANCE_NOT_APPLICABLE,
      reason: BASE_SDK_SOURCE_REASON,
    },
    release: {
      repository: download.releaseRepository,
      version: download.version,
      download_url: download.url,
    },
    artifact: {
      path: download.archive,
      sha256: '8'.repeat(64),
    },
  };
}

async function writeGateApparatus(stage, platform) {
  const baseSdk = baseSdkProvenance(platform);
  return write(stage, GATE_APPARATUS_PROVENANCE, `${JSON.stringify({
    schema: 1,
    component: GATE_APPARATUS_COMPONENT,
    platform,
    gate_host_toolchain: REVIEWED_GATE_HOST_TOOLCHAIN,
    base_sdk: {
      source: baseSdk.source,
      release_repository: baseSdk.release.repository,
      version: baseSdk.release.version,
      download_url: baseSdk.release.download_url,
      archive_path: baseSdk.artifact.path,
      archive_sha256: baseSdk.artifact.sha256,
    },
    host_runtime: {
      path: 'runtime/lib/linux_x86_64_cjnative/libcangjie-runtime.so',
      sha256: '9'.repeat(64),
      g_cjLoadBadMask_count: 0,
      symbol_probe: 'nm -D --defined-only',
    },
    known_apparatus_limitations: KNOWN_GATE_APPARATUS_LIMITATIONS,
  }, null, 2)}\n`);
}

test('release manifest keeps every component and requires frozen clean stamps', async t => {
  const root = await fs.mkdtemp(path.join(os.tmpdir(), 'release-manifest-'));
  t.after(() => fs.rm(root, {recursive: true, force: true}));
  const stage = path.join(root, 'stage');
  const cjcContents = `compiler\0CJCJ-COMMIT:${CJCJ_SHA}\0`;
  const runtimeContents = `runtime\0CJRT-COMMIT:${RUNTIME_SHA}\0`;
  const llcContents = `llc\0CJLLVM-COMMIT:${LLVM_SHA}\0`;
  const optContents = `opt\0CJLLVM-COMMIT:${LLVM_SHA}\0`;
  const runtime = await write(stage, 'runtime/lib/linux_x86_64_cjnative/libcangjie-runtime.so', runtimeContents);
  const cjc = await write(stage, 'bin/cjc', cjcContents);
  const llc = await write(stage, 'third_party/llvm/bin/llc', llcContents);
  const opt = await write(stage, 'third_party/llvm/bin/opt', optContents);
  // Cangjie-written, and now discovered by that property rather than by name.
  const cjpmContents = 'patched-cjpm-without-an-embedded-stamp\0CJ_MCC_WriteRefField\0';
  await write(stage, 'tools/bin/cjpm', cjpmContents);
  // std ships bytes, and PROVENANCE.txt's ARTIFACT-SHA256 block is the only
  // record tying those bytes to the build. An empty block meant the packaged std
  // could be swapped wholesale without the manifest changing at all.
  const stdArtifacts = [
    ['modules/linux_x86_64_cjnative/std/core.cjo', 'fixture std core cjo'],
    ['lib/linux_x86_64_cjnative/libcangjie-std-core.a', 'fixture std core archive'],
  ];
  const stdHashes = [];
  for (const [relative, contents] of stdArtifacts) {
    await write(stage, relative, contents);
    stdHashes.push(`${digest(contents)}  ${relative}`);
  }
  const provenance = await write(stage, 'PROVENANCE.txt', [
    `CJSTD-COMMIT:${STD_SHA} BUILT-BY:${CJCJ_SHA}`,
    `STD_SOURCE_COMMIT = ${STD_SHA}`,
    'ARTIFACT-SHA256:',
    ...stdHashes,
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
  const gateApparatusArtifact = await writeGateApparatus(stage, 'linux-x64');

  const options = {
    stage,
    platform: 'linux-x64',
    runtimeArtifact: runtime,
    stdProvenance: provenance,
    baseSdkId: REVIEWED_GATE_HOST_TOOLCHAIN,
    baseSdkProvenance: baseSdkProvenance('linux-x64'),
    gateApparatusArtifact,
    cjcjCommit: CJCJ_SHA,
    runtimeCommit: RUNTIME_SHA,
    llvmCommit: LLVM_SHA,
    stdRepository: 'https://github.com/cjcj-dev/cangjie-runtime.git',
    cjpmRepository: 'https://github.com/cjcj-dev/cangjie-tools.git',
    cjpmCommit: CJPM_SHA,
    pythonArtifact,
    pythonMetadata,
    pythonMetadataArtifact,
    pythonVersion: RELEASE_PYTHON_VERSION,
  };
  const positive = await writeReleaseManifest(options);
  assert.equal(positive.rows.length, 9);
  assert.deepEqual(positive.rows.map(row => row.component),
    ['base-sdk', GATE_APPARATUS_COMPONENT, 'cjcj', 'runtime', 'llvm-llc', 'llvm-opt', 'std', 'cjpm', 'python']);
  const apparatus = positive.rows.find(row => row.component === GATE_APPARATUS_COMPONENT).acceptance_apparatus;
  assert.equal(apparatus.gate_host_toolchain, REVIEWED_GATE_HOST_TOOLCHAIN);
  assert.match(apparatus.host_runtime.sha256, /^[0-9a-f]{64}$/);
  assert.equal(apparatus.host_runtime.g_cjLoadBadMask_count, 0);
  assert.equal(apparatus.known_apparatus_limitations.evidence[0].report, 'REPORT-gateconc.md');
  assert.equal(positive.rows.find(row => row.component === 'llvm-opt').embedded_stamp,
    `CJLLVM-COMMIT:${LLVM_SHA}`);
  assert.equal(positive.rows.find(row => row.component === 'std').embedded_stamp, 'no-stamp');
  assert.equal(positive.rows.find(row => row.component === 'cjpm').artifact.sha256, digest(cjpmContents));
  const baseSdkRow = positive.rows.find(row => row.component === 'base-sdk');
  assert.equal(baseSdkRow.source.status, SOURCE_PROVENANCE_NOT_APPLICABLE);
  assert.equal(baseSdkRow.source.commit, SOURCE_PROVENANCE_NOT_APPLICABLE);
  assert.equal(baseSdkRow.source.reason, BASE_SDK_SOURCE_REASON);
  assert.equal(positive.rows.find(row => row.component === 'cjpm').source.status,
    SOURCE_PROVENANCE_RESOLVED);

  const optionsFile = await write(root, 'writer-options.json', `${JSON.stringify(options)}\n`);
  async function expectStampGuard({name, mutate, restore, expected}) {
    await t.test(name, async () => {
      await mutate();
      try {
        const sentinel = `manifest-write-sentinel:${name}\n`;
        await fs.writeFile(positive.destination, sentinel);
        const result = spawnSync(process.execPath,
          ['--input-type=module', '--eval', writerRunner, optionsFile], {encoding: 'utf8'});
        const output = `${result.stdout}\n${result.stderr}`;
        assert.equal(result.status, 1, output);
        assert.match(output, expected);
        assert.equal(await fs.readFile(positive.destination, 'utf8'), sentinel,
          'stamp guard must reject before writing the release manifest');
        const errorLine = output.split(/\r?\n/).find(line => line.includes('Error:'))?.trim() || '<missing error>';
        console.log(`STAMP-GUARD ${name} RC=${result.status} ${errorLine}`);
      } finally {
        await restore();
      }
    });
  }

  await expectStampGuard({
    name: 'occurrence=0',
    mutate: () => fs.writeFile(cjc, 'compiler-without-stamp'),
    restore: () => fs.writeFile(cjc, cjcContents),
    expected: /cjc CJCJ-COMMIT occurrence must be exactly 1; actual count=0; actual stamps=<none>/,
  });
  await expectStampGuard({
    name: 'occurrence=2',
    mutate: () => fs.writeFile(runtime,
      `runtime\0CJRT-COMMIT:${RUNTIME_SHA}\0CJRT-COMMIT:${RUNTIME_SHA}\0`),
    restore: () => fs.writeFile(runtime, runtimeContents),
    expected: new RegExp(`runtime CJRT-COMMIT occurrence must be exactly 1; actual count=2; ` +
      `actual stamps=CJRT-COMMIT:${RUNTIME_SHA}, CJRT-COMMIT:${RUNTIME_SHA}`),
  });
  await expectStampGuard({
    name: 'dirty',
    mutate: () => fs.writeFile(llc, `llc\0CJLLVM-COMMIT:${LLVM_SHA}-dirty\0`),
    restore: () => fs.writeFile(llc, llcContents),
    expected: new RegExp(`llvm-llc CJLLVM-COMMIT must not be dirty; ` +
      `actual=CJLLVM-COMMIT:${LLVM_SHA}-dirty`),
  });
  await expectStampGuard({
    name: 'frozen-mismatch',
    mutate: () => fs.writeFile(opt, `opt\0CJLLVM-COMMIT:${OTHER_SHA}\0`),
    restore: () => fs.writeFile(opt, optContents),
    expected: new RegExp(`llvm-opt CJLLVM-COMMIT must equal frozen SHA; ` +
      `actual=${OTHER_SHA}; frozen=${LLVM_SHA}`),
  });

  const restored = await writeReleaseManifest(options);
  assert.ok(restored.rows.every(row => Object.values({
    repository: row.source.repository,
    commit: row.source.commit,
    path: row.artifact.path,
    sha256: row.artifact.sha256,
    stamp: row.embedded_stamp,
  }).every(value => typeof value === 'string' && value.length > 0)));

  const dist = path.join(root, 'dist');
  await fs.mkdir(dist);
  await fs.copyFile(restored.destination,
    path.join(dist, `cjcj-9.9.9-linux-x64.${RELEASE_MANIFEST}`));
  const notes = path.join(root, 'notes.md');
  const rendered = spawnSync(process.execPath, [
    path.resolve('scripts/render_release_notes.mjs'),
    '--version', '9.9.9', '--dist', dist, '--output', notes,
  ], {encoding: 'utf8'});
  assert.equal(rendered.status, 0, rendered.stderr);
  const notesText = await fs.readFile(notes, 'utf8');
  assert.match(notesText, /\| cjcj \| 1111111111111111111111111111111111111111 \| [0-9a-f]{64} \|/);
  assert.match(notesText, new RegExp(`\\| llvm-opt \\| ${LLVM_SHA} \\| [0-9a-f]{64} \\| ` +
    `CJLLVM-COMMIT:${LLVM_SHA} \\|`));
  console.log(`RELEASE-NOTES-BEGIN\n${notesText.trim()}\nRELEASE-NOTES-END`);
});

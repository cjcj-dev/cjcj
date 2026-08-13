// Negative arms for the rebuilt-component identity rules.
//
// Each guard here is checked by making the thing it guards against actually
// happen. A guard nobody has watched fire is indistinguishable from no guard,
// and this repository has shipped three of those (a hard-coded artifact name, a
// hard-coded count, and an arm that passed on `'limits' file not found`).
import assert from 'node:assert/strict';
import crypto from 'node:crypto';
import fs from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';
import {spawnSync} from 'node:child_process';
import test from 'node:test';
import {fileURLToPath} from 'node:url';
import {classifyStamp} from '../lib/provenance.mjs';
import {writeReleaseManifest} from '../lib/release-manifest.mjs';
import {
  CJDB_PYTHON_MODULES,
  CJDB_PYTHON_UNIX_MODULES,
  RELEASE_PYTHON_SOURCE_SHA256,
  RELEASE_PYTHON_SOURCE_URL,
  RELEASE_PYTHON_VERSION,
} from '../lib/python-bundle.mjs';
import {
  BASE_SDK_SOURCE_REASON,
  SOURCE_PROVENANCE_NOT_APPLICABLE,
  baseSdkDownload,
} from '../lib/release-component-provenance.mjs';
import {
  GATE_APPARATUS_COMPONENT,
  GATE_APPARATUS_PROVENANCE,
  KNOWN_GATE_APPARATUS_LIMITATIONS,
  REVIEWED_GATE_HOST_TOOLCHAIN,
} from '../lib/release-gate-apparatus.mjs';

const CJCJ_SHA = '1'.repeat(40);
const RUNTIME_SHA = '2'.repeat(40);
const LLVM_SHA = '3'.repeat(40);
const STD_SHA = '4'.repeat(40);
const TUPLE = 'linux_x86_64_cjnative';
const CJ = '\0CJ_MCC_WriteRefField\0';

const digest = contents => crypto.createHash('sha256').update(contents).digest('hex');

async function write(root, relative, contents) {
  const file = path.join(root, relative);
  await fs.mkdir(path.dirname(file), {recursive: true});
  await fs.writeFile(file, contents);
  return file;
}

// A stage that passes every rule, so each test can break exactly one thing.
async function fixture({stdOnDisk, stdInProvenance, tools} = {}) {
  const work = await fs.mkdtemp(path.join(os.tmpdir(), 'rebuilt-identity-'));
  const stage = path.join(work, 'stage');
  await write(stage, 'bin/cjc', `compiler\0CJCJ-COMMIT:${CJCJ_SHA}\0`);
  const runtimeArtifact = await write(stage, `runtime/lib/${TUPLE}/libcangjie-runtime.so`,
    `runtime\0CJRT-COMMIT:${RUNTIME_SHA}\0`);
  await write(stage, 'third_party/llvm/bin/llc', `llc\0CJLLVM-COMMIT:${LLVM_SHA}\0`);
  await write(stage, 'third_party/llvm/bin/opt', `opt\0CJLLVM-COMMIT:${LLVM_SHA}\0`);
  for (const [name, contents] of Object.entries(tools ?? {cjpm: `cjpm fixture${CJ}`})) {
    await write(stage, `tools/bin/${name}`, contents);
  }
  const onDisk = stdOnDisk ?? {[`lib/${TUPLE}/libcangjie-std-core.a`]: 'std core archive'};
  for (const [relative, contents] of Object.entries(onDisk)) await write(stage, relative, contents);
  const listed = stdInProvenance ?? onDisk;
  const stdProvenance = await write(stage, 'PROVENANCE.txt', [
    `CJSTD-COMMIT:${STD_SHA} BUILT-BY:${CJCJ_SHA}`,
    `STD_SOURCE_COMMIT = ${STD_SHA}`,
    'ARTIFACT-SHA256:',
    ...Object.entries(listed).map(([relative, contents]) => `${digest(contents)}  ${relative}`),
    '',
  ].join('\n'));
  const pythonArtifact = await write(stage, 'third_party/python/bin/python3.11', 'python fixture');
  const pythonMetadata = {
    schema: 1,
    platform: 'linux-x64',
    version: RELEASE_PYTHON_VERSION,
    source_type: 'python.org-source-native',
    source_url: RELEASE_PYTHON_SOURCE_URL,
    source_sha256: RELEASE_PYTHON_SOURCE_SHA256,
    configure_args: '--prefix=<bundle>',
    configure_environment: 'LDFLAGS=-Wl,-rpath,$ORIGIN/../lib',
    required_modules: [...CJDB_PYTHON_MODULES],
    required_unix_modules: [...CJDB_PYTHON_UNIX_MODULES],
  };
  const pythonMetadataArtifact = await write(stage, 'third_party/python/PYTHON-BUNDLE.json',
    `${JSON.stringify(pythonMetadata, null, 2)}\n`);
  const baseDownload = baseSdkDownload('linux-x64', REVIEWED_GATE_HOST_TOOLCHAIN);
  const baseSdkProvenance = {
    schema: 1,
    component: 'base-sdk',
    platform: 'linux-x64',
    source: {status: SOURCE_PROVENANCE_NOT_APPLICABLE, reason: BASE_SDK_SOURCE_REASON},
    release: {
      repository: baseDownload.releaseRepository,
      version: baseDownload.version,
      download_url: baseDownload.url,
    },
    artifact: {path: baseDownload.archive, sha256: 'a'.repeat(64)},
  };
  const gateApparatusArtifact = await write(stage, GATE_APPARATUS_PROVENANCE,
    `${JSON.stringify({
      schema: 1,
      component: GATE_APPARATUS_COMPONENT,
      platform: 'linux-x64',
      gate_host_toolchain: REVIEWED_GATE_HOST_TOOLCHAIN,
      base_sdk: {
        source: baseSdkProvenance.source,
        release_repository: baseSdkProvenance.release.repository,
        version: baseSdkProvenance.release.version,
        download_url: baseSdkProvenance.release.download_url,
        archive_path: baseSdkProvenance.artifact.path,
        archive_sha256: baseSdkProvenance.artifact.sha256,
      },
      host_runtime: {
        path: `runtime/lib/${TUPLE}/libcangjie-runtime.so`,
        sha256: 'b'.repeat(64),
        g_cjLoadBadMask_count: 0,
        symbol_probe: 'nm -D --defined-only',
      },
      known_apparatus_limitations: KNOWN_GATE_APPARATUS_LIMITATIONS,
    }, null, 2)}\n`);
  return {
    work,
    options: {
      stage,
      platform: 'linux-x64',
      runtimeArtifact,
      stdProvenance,
      baseSdkId: REVIEWED_GATE_HOST_TOOLCHAIN,
      baseSdkProvenance,
      gateApparatusArtifact,
      cjcjCommit: CJCJ_SHA,
      runtimeCommit: RUNTIME_SHA,
      llvmCommit: LLVM_SHA,
      stdRepository: 'https://example.invalid/std',
      cjpmRepository: 'https://example.invalid/tools',
      cjpmCommit: '5'.repeat(40),
      pythonArtifact,
      pythonMetadataArtifact,
      pythonVersion: RELEASE_PYTHON_VERSION,
      pythonMetadata: {
        source_type: 'source',
        source_url: RELEASE_PYTHON_SOURCE_URL,
        source_sha256: RELEASE_PYTHON_SOURCE_SHA256,
        configure_args: '--prefix',
        configure_environment: 'CC=cc',
      },
    },
  };
}

// The whole point of the std row: swapping the packaged bytes must be visible.
// Before this change the row hashed PROVENANCE.txt only, so replacing every std
// archive with a factory copy left the manifest byte-identical.
test('packaged std bytes that are not in PROVENANCE.txt fail closed', async () => {
  // One archive swapped back and one left alone: a partial swap is the realistic
  // shape, and it also separates "one file is wrong" from "nothing verified".
  const {options} = await fixture({
    stdOnDisk: {
      [`lib/${TUPLE}/libcangjie-std-core.a`]: 'FACTORY std core archive',
      [`lib/${TUPLE}/libcangjie-std-io.a`]: 'std io archive',
    },
    stdInProvenance: {
      [`lib/${TUPLE}/libcangjie-std-core.a`]: 'std core archive',
      [`lib/${TUPLE}/libcangjie-std-io.a`]: 'std io archive',
    },
  });
  await assert.rejects(writeReleaseManifest(options),
    /packaged std artifact\(s\) are not in PROVENANCE.txt/);
});

test('a std build with no ARTIFACT-SHA256 block fails closed', async () => {
  const {options} = await fixture();
  const text = await fs.readFile(options.stdProvenance, 'utf8');
  await fs.writeFile(options.stdProvenance, text.replace(/ARTIFACT-SHA256:[\s\S]*$/, ''));
  await assert.rejects(writeReleaseManifest(options), /has no ARTIFACT-SHA256 block/);
});

// Verifying nothing is not the same as verifying everything, and the difference
// is exactly where a gate silently turns green.
test('a stage with no packaged std artifact refuses to claim coverage', async () => {
  const {options} = await fixture({
    stdOnDisk: {},
    stdInProvenance: {[`lib/${TUPLE}/libcangjie-std-core.a`]: 'std core archive'},
  });
  await assert.rejects(writeReleaseManifest(options),
    /no packaged std artifact matched PROVENANCE.txt/);
});

test('a stage with no Cangjie-written tool is an apparatus failure, not a clean tree', async () => {
  const {options} = await fixture({tools: {cjpm: 'a blob with no runtime entry points'}});
  await assert.rejects(writeReleaseManifest(options), /no Cangjie-written tool was found/);
});

// Discovery, not a name list: a tool nobody added to any list still gets a row.
test('every Cangjie-written tool in the stage gets its own row', async () => {
  const {options} = await fixture({
    tools: {cjpm: `cjpm${CJ}`, hle: `hle${CJ}`, cjfmt: 'a C++ tool with no runtime entry points'},
  });
  const {rows} = await writeReleaseManifest(options);
  const components = rows.map(row => row.component);
  assert.ok(components.includes('cjpm'), 'cjpm keeps its own component name');
  assert.ok(components.includes('tool-hle'), 'a newly wired Cangjie tool is covered without a code change');
  assert.ok(!components.includes('tool-cjfmt'), 'a C++ tool must not be claimed as Cangjie-written');
});

// The exemption expires by itself: the first stamped tool makes the stamp
// mandatory for all of them, so nobody has to remember to switch it on.
test('once any tool carries CJTOOL-COMMIT the unstamped ones fail closed', async () => {
  const {options} = await fixture({
    tools: {cjpm: `cjpm\0CJTOOL-COMMIT:${'6'.repeat(40)}\0${CJ}`, hle: `hle${CJ}`},
  });
  await assert.rejects(writeReleaseManifest({
    ...options,
    toolSources: {
      cjpm: {repository: 'https://example.invalid/tools', commit: '6'.repeat(40)},
      'tool-hle': {repository: 'https://example.invalid/tools', commit: '6'.repeat(40)},
    },
  }), /tool-hle CJTOOL-COMMIT occurrence must be exactly 1/);
});

test('while no tool carries CJTOOL-COMMIT the rows say so instead of staying silent', async () => {
  const {options} = await fixture({tools: {cjpm: `cjpm${CJ}`, hle: `hle${CJ}`}});
  const {rows} = await writeReleaseManifest(options);
  for (const component of ['cjpm', 'tool-hle']) {
    assert.equal(rows.find(row => row.component === component).build.identity_rule,
      'inherited-base-sdk');
  }
});

// The renderer's component check was relaxed from "exactly this list" to "these
// plus any discovered tool", so it has to be shown still rejecting the two
// things it is there for: a missing core component, and a component nobody
// declared. Otherwise "relaxed" is indistinguishable from "removed".
function render(dist, output) {
  return spawnSync(process.execPath, [
    path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..', '..',
      'scripts', 'render_release_notes.mjs'),
    '--version', '0.0.0-test', '--dist', dist, '--output', output,
  ], {encoding: 'utf8'});
}

test('the renderer accepts discovered tool rows but still rejects a missing core component', async () => {
  const {work, options} = await fixture({tools: {cjpm: `cjpm${CJ}`, hle: `hle${CJ}`}});
  const {rows} = await writeReleaseManifest(options);
  assert.ok(rows.some(row => row.component === 'tool-hle'));
  const dist = path.join(work, 'dist');
  const manifest = path.join(dist, 'cjcj-0.0.0-test-linux-x64.RELEASE-MANIFEST.jsonl');
  const render1 = `${rows.map(row => JSON.stringify(row)).join('\n')}\n`;
  await fs.mkdir(dist, {recursive: true});
  await fs.writeFile(manifest, render1);
  assert.equal(render(dist, path.join(work, 'notes-ok.md')).status, 0,
    'a manifest carrying a discovered tool row must render');

  await fs.writeFile(manifest,
    `${rows.filter(row => row.component !== 'std').map(row => JSON.stringify(row)).join('\n')}\n`);
  const dropped = render(dist, path.join(work, 'notes-missing.md'));
  assert.notEqual(dropped.status, 0, 'a manifest missing std must not render');
  assert.match(dropped.stderr, /missing=std/);

  await fs.writeFile(manifest,
    `${render1}${JSON.stringify({...rows[0], component: 'smuggled'})}\n`);
  const smuggled = render(dist, path.join(work, 'notes-extra.md'));
  assert.notEqual(smuggled.status, 0, 'an undeclared component must not render');
  assert.match(smuggled.stderr, /unexpected=smuggled/);
});

// absent and stamped-unknown were one string, and they call for different work:
// one means the stamping step never ran, the other means it ran with nothing to
// write.
test('an absent stamp and a stamped-unknown one are different states', () => {
  assert.equal(classifyStamp(''), 'absent');
  assert.equal(classifyStamp('unknown'), 'stamped-unknown');
  assert.equal(classifyStamp('1.2.0-alpha'), 'stamped-unknown');
  assert.equal(classifyStamp('a'.repeat(40)), 'stamped');
});

import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import {spawnSync} from 'node:child_process';
import test from 'node:test';
import {
  LLVM_TOOLS_MANIFEST_SCHEMAS,
  PACKAGED_LLVM_TOOL_NAMES,
  formatPackagedLlvmToolsManifest,
  parseLlvmToolsManifest,
  parsePackagedLlvmToolsManifest,
} from './llvm-tools-manifest.mjs';

const pins = Object.fromEntries(
  fs.readFileSync(new URL('./llvm_pin.env', import.meta.url), 'utf8')
    .split(/\r?\n/)
    .filter((line) => /^[A-Z0-9_]+=[0-9a-f]+$/.test(line))
    .map((line) => line.split('=')),
);
const tupleManifest = [
  'PLATFORM=linux_x86_64',
  `LLVM_SHA=${pins.LLVM_SHA}`,
  `CANGJIE_COMPILER_SHA=${pins.CANGJIE_COMPILER_SHA}`,
  `FLATBUFFERS_SHA=${pins.FLATBUFFERS_SHA}`,
  `LLC_SOURCE=tuple:${pins.LLVM_SHA}`,
  'LLC_VERSION=LLVM version 15.0.4',
  `LLC_SHA256=${'1'.repeat(64)}`,
  `OPT_SOURCE=tuple:${pins.LLVM_SHA}`,
  'OPT_VERSION=LLVM version 15.0.4',
  `OPT_SHA256=${'2'.repeat(64)}`,
  'LLD_TOOL=ld.lld',
  `LLD_SOURCE=tuple:${pins.LLVM_SHA}`,
  'LLD_VERSION=LLD 15.0.4',
  `LLD_SHA256=${'4'.repeat(64)}`,
  `SHIM_SHA256=${'3'.repeat(64)}`,
].join('\n');

test('one tuple schema binds all fifteen fields on every platform', () => {
  for (const platform of ['linux_x86_64', 'linux_aarch64', 'darwin_x86_64', 'darwin_aarch64', 'windows_x86_64']) {
    const text = tupleManifest.replace('PLATFORM=linux_x86_64', `PLATFORM=${platform}`);
    const parsed = parseLlvmToolsManifest(text);
    assert.equal(parsed.schema, 'tuple');
    assert.deepEqual([...parsed.values.keys()].sort(), [...LLVM_TOOLS_MANIFEST_SCHEMAS.tuple].sort());
  }
});

test('tuple rejects every missing field and every tool source mismatch', () => {
  for (const field of LLVM_TOOLS_MANIFEST_SCHEMAS.tuple) {
    const partial = tupleManifest.split('\n').filter(line => !line.startsWith(`${field}=`)).join('\n');
    assert.throws(() => parseLlvmToolsManifest(partial), new RegExp(`missing=${field}`));
  }
  for (const tool of ['LLC', 'OPT', 'LLD']) {
    assert.throws(
      () => parseLlvmToolsManifest(tupleManifest.replace(`${tool}_SOURCE=tuple:${pins.LLVM_SHA}`, `${tool}_SOURCE=tuple:${'0'.repeat(40)}`)),
      new RegExp(`${tool}_SOURCE does not match LLVM_SHA`),
    );
  }
});

test('legacy partial manifests and unknown fields are rejected', () => {
  const legacyFields = [
    ['LLVM_SHA', 'LLC_SHA256', 'OPT_SHA256'],
    ['PLATFORM', 'LLVM_SHA', 'CANGJIE_COMPILER_SHA', 'FLATBUFFERS_SHA', 'LLC_SHA256', 'OPT_SHA256', 'LLD_TOOL', 'LLD_SOURCE', 'LLD_VERSION', 'LLD_SHA256', 'SHIM_SHA256'],
    ['LLVM_SHA', 'LLC_SOURCE', 'LLC_VERSION', 'LLC_SHA256', 'OPT_SOURCE', 'OPT_VERSION', 'OPT_SHA256', 'LLD_TOOL', 'LLD_SOURCE', 'LLD_VERSION', 'LLD_SHA256'],
  ];
  for (const fields of legacyFields) {
    const legacy = tupleManifest.split('\n').filter(line => fields.includes(line.split('=')[0])).join('\n');
    assert.throws(() => parseLlvmToolsManifest(legacy), /field contract mismatch/);
  }
  assert.throws(() => parseLlvmToolsManifest(tupleManifest + '\nEXTRA=value'), /unexpected=EXTRA/);
  assert.throws(() => parseLlvmToolsManifest(tupleManifest.replace('LLD_TOOL=ld.lld', 'LLD_TOOL=lld-link')), /invalid LLD_TOOL/);
});

function packagedRows() {
  return PACKAGED_LLVM_TOOL_NAMES.map((tool) => ({
    tool,
    present: 'yes',
    source: ['llc', 'opt'].includes(tool) ? `tuple:${pins.LLVM_SHA}` : `base-sdk:${'a'.repeat(64)}`,
    version: 'LLVM version 15.0.4',
    sha256: tool === 'llc' ? '1'.repeat(64) : '2'.repeat(64),
  }));
}

test('tuple CLI validates the source identity read from its real file input', t => {
  const directory = fs.mkdtempSync(path.join(os.tmpdir(), 'tuple-manifest-'));
  t.after(() => fs.rmSync(directory, {recursive: true, force: true}));
  const manifest = path.join(directory, 'llvm-tools.manifest');
  const command = path.join(import.meta.dirname, 'llvm-tools-manifest.mjs');
  fs.writeFileSync(manifest, tupleManifest);
  const valid = spawnSync(process.execPath, [command, 'validate', 'tuple', manifest], {encoding: 'utf8'});
  console.log(`TUPLE_CLI valid_rc=${valid.status} ${valid.stdout.trim()}`);
  assert.equal(valid.status, 0, valid.stderr);
  assert.match(valid.stdout, /schema=tuple fields=15/);
  fs.writeFileSync(manifest, tupleManifest.replace(`OPT_SOURCE=tuple:${pins.LLVM_SHA}`, `OPT_SOURCE=tuple:${'0'.repeat(40)}`));
  const invalid = spawnSync(process.execPath, [command, 'validate', 'tuple', manifest], {encoding: 'utf8'});
  console.log(`TUPLE_CLI changed_source_rc=${invalid.status}`);
  assert.equal(invalid.status, 1, 'mismatched source must be rejected by the CLI');
  assert.match(invalid.stderr, /OPT_SOURCE does not match LLVM_SHA/);
});

test('packaged manifest round-trips every canonical LLVM tool lineage row', () => {
  const expected = {
    llvmSha: pins.LLVM_SHA,
    baseSdkSha256: 'a'.repeat(64),
    tools: packagedRows(),
  };
  const text = formatPackagedLlvmToolsManifest(expected);
  assert.deepEqual(parsePackagedLlvmToolsManifest(text), expected);
});

test('packaged manifest rejects missing, reordered and malformed lineage rows', () => {
  const metadata = {llvmSha: pins.LLVM_SHA, baseSdkSha256: 'a'.repeat(64)};
  assert.throws(
    () => formatPackagedLlvmToolsManifest({...metadata, tools: packagedRows().slice(1)}),
    /missing canonical tool rows: ld\.lld/,
  );
  assert.throws(
    () => formatPackagedLlvmToolsManifest({...metadata, tools: packagedRows().reverse()}),
    /tool rows must be sorted/,
  );
  const badHash = packagedRows();
  badHash[0] = {...badHash[0], sha256: 'not-a-sha'};
  assert.throws(
    () => formatPackagedLlvmToolsManifest({...metadata, tools: badHash}),
    /invalid sha256/,
  );
});

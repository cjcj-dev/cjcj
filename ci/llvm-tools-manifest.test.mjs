import assert from 'node:assert/strict';
import fs from 'node:fs';
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
const nativeManifest = [
  'PLATFORM=linux_x86_64',
  `LLVM_SHA=${pins.LLVM_SHA}`,
  `CANGJIE_COMPILER_SHA=${pins.CANGJIE_COMPILER_SHA}`,
  `FLATBUFFERS_SHA=${pins.FLATBUFFERS_SHA}`,
  `LLC_SHA256=${'1'.repeat(64)}`,
  `OPT_SHA256=${'2'.repeat(64)}`,
  `SHIM_SHA256=${'3'.repeat(64)}`,
].join('\n');

test('native producer manifest satisfies the seven-field consumer contract', () => {
  const parsed = parseLlvmToolsManifest(nativeManifest, {schema: 'native'});
  assert.equal(parsed.schema, 'native');
  assert.deepEqual([...parsed.values.keys()], LLVM_TOOLS_MANIFEST_SCHEMAS.native);
});

test('native manifest missing one field is rejected', () => {
  const missingShim = nativeManifest.split('\n').slice(0, -1).join('\n');
  assert.throws(
    () => parseLlvmToolsManifest(missingShim, {schema: 'native'}),
    /missing=SHIM_SHA256/,
  );
});

test('platform tuple core manifest remains a separate valid contract', () => {
  const coreManifest = [
    `LLVM_SHA=${pins.LLVM_SHA}`,
    `LLC_SHA256=${'1'.repeat(64)}`,
    `OPT_SHA256=${'2'.repeat(64)}`,
  ].join('\n');
  const parsed = parseLlvmToolsManifest(coreManifest, {schema: 'core-or-native'});
  assert.equal(parsed.schema, 'core');
  assert.deepEqual([...parsed.values.keys()], LLVM_TOOLS_MANIFEST_SCHEMAS.core);
});

test('platform tuple lineage binds source, version and hash for both tools', () => {
  const lineageManifest = [
    `LLVM_SHA=${pins.LLVM_SHA}`,
    `LLC_SOURCE=tuple:${pins.LLVM_SHA}`,
    'LLC_VERSION=LLVM version 15.0.4',
    `LLC_SHA256=${'1'.repeat(64)}`,
    `OPT_SOURCE=tuple:${pins.LLVM_SHA}`,
    'OPT_VERSION=LLVM version 15.0.4',
    `OPT_SHA256=${'2'.repeat(64)}`,
  ].join('\n');
  const parsed = parseLlvmToolsManifest(lineageManifest, {schema: 'core-or-native'});
  assert.equal(parsed.schema, 'core-lineage');
  assert.deepEqual([...parsed.values.keys()], LLVM_TOOLS_MANIFEST_SCHEMAS['core-lineage']);
  assert.throws(
    () => parseLlvmToolsManifest(lineageManifest.replace(`LLC_SOURCE=tuple:${pins.LLVM_SHA}`, `LLC_SOURCE=tuple:${'0'.repeat(40)}`)),
    /LLC_SOURCE does not match LLVM_SHA/,
  );
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

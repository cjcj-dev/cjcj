import assert from 'node:assert/strict';
import fs from 'node:fs';
import test from 'node:test';
import {LLVM_TOOLS_MANIFEST_SCHEMAS, parseLlvmToolsManifest} from './llvm-tools-manifest.mjs';

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

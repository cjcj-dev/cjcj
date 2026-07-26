import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import test from 'node:test';
import {
  OPTIMIZED_STD_SUBDIR,
  STICKY_LLC_OPTION,
  compareStdCjos,
  copyCompiledStdLibraries,
  createStickySdkOverlay,
  stickyPreflight,
} from '../lib/std-variants.mjs';

function directory(root, ...parts) {
  const result = path.join(root, ...parts);
  fs.mkdirSync(result, {recursive: true});
  return result;
}

function file(root, parts, contents = '') {
  const result = path.join(root, ...parts);
  fs.mkdirSync(path.dirname(result), {recursive: true});
  fs.writeFileSync(result, contents);
  return result;
}

test('sticky SDK overlay replaces only llc', () => {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), 'stddual-overlay-'));
  try {
    const sdk = directory(root, 'sdk');
    for (const name of ['bin', 'include', 'lib', 'modules', 'runtime', 'tools']) directory(sdk, name);
    directory(sdk, 'third_party', 'llvm', 'lib');
    file(sdk, ['third_party', 'llvm', 'bin', 'llc'], 'original llc');
    file(sdk, ['third_party', 'llvm', 'bin', 'opt'], 'original opt');
    const overlay = createStickySdkOverlay(sdk, path.join(root, 'overlay'));
    assert.equal(fs.realpathSync(path.join(overlay, 'bin')), path.join(sdk, 'bin'));
    assert.equal(fs.realpathSync(path.join(overlay, 'third_party', 'llvm', 'bin', 'opt')),
      path.join(sdk, 'third_party', 'llvm', 'bin', 'opt'));
    const wrapper = fs.readFileSync(path.join(overlay, 'third_party', 'llvm', 'bin', 'llc'), 'utf8');
    assert.match(wrapper, new RegExp(STICKY_LLC_OPTION));
    assert.match(wrapper, /"\$@"/);
    assert.equal(OPTIMIZED_STD_SUBDIR, 'cjcj-optimization');
  } finally {
    fs.rmSync(root, {recursive: true, force: true});
  }
});

test('compiled std copy keeps std-named archives and excludes unrelated libraries', () => {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), 'stddual-libs-'));
  try {
    const source = directory(root, 'source');
    file(source, ['libcangjie-std-core.a'], 'core-a');
    file(source, ['libcangjie-std-core.so'], 'core-so');
    file(source, ['libcangjie-std.a'], 'std-a');
    file(source, ['libcangjie-std-coreFFI.a'], 'ffi');
    file(source, ['libboundscheck.so'], 'bounds');
    const destination = path.join(root, 'destination');
    const copied = copyCompiledStdLibraries(source, destination);
    assert.deepEqual(copied.files, [
      'libcangjie-std-core.a', 'libcangjie-std-core.so', 'libcangjie-std-coreFFI.a', 'libcangjie-std.a',
    ]);
    assert.equal(fs.existsSync(path.join(destination, 'libboundscheck.so')), false);
  } finally {
    fs.rmSync(root, {recursive: true, force: true});
  }
});

test('CJO comparison reports byte identity and differences', () => {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), 'stddual-cjo-'));
  try {
    const flagOff = directory(root, 'off');
    const sticky = directory(root, 'sticky');
    file(flagOff, ['std.core.cjo'], 'same');
    file(sticky, ['std.core.cjo'], 'same');
    file(flagOff, ['std.collection.cjo'], 'off');
    file(sticky, ['std.collection.cjo'], 'sticky');
    const compared = compareStdCjos(flagOff, sticky);
    assert.deepEqual(compared.map(item => [item.name, item.identical]), [
      ['std.collection.cjo', false], ['std.core.cjo', true],
    ]);
  } finally {
    fs.rmSync(root, {recursive: true, force: true});
  }
});

test('sticky preflight rejects an ELF without sticky symbols', () => {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), 'stddual-preflight-'));
  try {
    fs.copyFileSync('/bin/true', path.join(root, 'libcangjie-std-core.so'));
    assert.throws(() => stickyPreflight(root), /sticky std preflight failed/);
  } finally {
    fs.rmSync(root, {recursive: true, force: true});
  }
});

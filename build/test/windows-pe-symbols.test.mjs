import test from 'node:test';
import {linkedPeFixture} from './linked-pe-fixture.mjs';
import assert from 'node:assert/strict';
import path from 'node:path';
import {getBuildTarget} from '../lib/build-target.mjs';
import {assertX64PeImage,readPeSymbols} from '../lib/pe-symbols.mjs';
import {readRuntimeSymbols, readCompilerSymbols, countLoadBadMask} from '../lib/runtime-split.mjs';

// Existing apparatus dependencies: Clang 15 C producer, LLVM 14 COFF reader/linker.
// These are not the platform SDK Ndb51 tuple or native Windows qualification.
const bin = '/usr/lib/llvm-14/bin';
const target = getBuildTarget('windows-x64', {platform: 'win32', arch: 'x64', env: {CJCJ_NATIVE_LLVM_BIN: bin}});
for (const [symbol, count] of [['g_cjLoadBadMask', 1], ['ordinary_fixture_symbol', 0]]) {
  test(`real PE import/export tables count ${symbol} without nm dynamic ELF flags`, t => {
    const root = linkedPeFixture(t, symbol);
    assertX64PeImage(path.join(root,'consumer.exe'),false);
    assertX64PeImage(path.join(root,'runtime.dll'),true);
    assert.throws(()=>assertX64PeImage(path.join(root,'runtime.dll'),false),/expected executable/);
    assert.equal(readPeSymbols(path.join(root,'consumer.exe'),target,'libraries'),'runtime.dll');
    const exported = readRuntimeSymbols(path.join(root, 'runtime.dll'), target);
    const imported = readCompilerSymbols(path.join(root, 'consumer.exe'), target);
    console.log('WINDOWS_PE_SYMBOL_ASSERT_REACHED ' + symbol);
    assert.equal(countLoadBadMask(exported), count);
    assert.equal(countLoadBadMask(imported), count);
    assert.match(exported, new RegExp('^' + symbol + '$', 'm'));
    assert.match(imported, new RegExp('^' + symbol + '$', 'm'));
    assert.equal(readPeSymbols(path.join(root, 'consumer.exe'), target, 'imports', 'runtime.dll'), symbol);
    assert.equal(readPeSymbols(path.join(root, 'consumer.exe'), target, 'imports', 'different.dll'), '');
    assert.throws(() => readRuntimeSymbols(path.join(root, 'runtime.obj'), target), /expected x64 PE\/COFF image/);
  });
}
test('Windows reader rejects an ELF image rather than interpreting no COFF symbols as zero', () => {
  assert.throws(() => readCompilerSymbols(process.execPath, target), /expected x64 PE\/COFF image/);
});

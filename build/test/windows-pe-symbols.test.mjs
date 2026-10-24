import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import {spawnSync} from 'node:child_process';
import {createHash} from 'node:crypto';
import {getBuildTarget} from '../lib/build-target.mjs';
import {readRuntimeSymbols, readCompilerSymbols, countLoadBadMask} from '../lib/runtime-split.mjs';

// Existing apparatus dependencies: Clang 15 C producer, LLVM 14 COFF reader/linker.
// These are not the platform SDK Ndb51 tuple or native Windows qualification.
const bin = '/usr/lib/llvm-14/bin';
const target = getBuildTarget('windows-x64', {platform: 'win32', arch: 'x64', env: {CJCJ_NATIVE_LLVM_BIN: bin}});
function fixture(t, symbol) {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), 'pe-symbols-'));
  t.after(() => fs.rmSync(root, {recursive: true, force: true}));
  const evidence = process.env.WINDOWS_PE_EVIDENCE && path.join(process.env.WINDOWS_PE_EVIDENCE, symbol);
  if (evidence) fs.mkdirSync(evidence, {recursive: true});
  const records = [];
  function run(program, args) {
    const executable = path.join(program === 'clang' ? '/usr/lib/llvm-15/bin' : bin, program);
    const r = spawnSync(executable, args, {cwd: root, encoding: 'utf8'});
    records.push({program, executable, args, rc: r.status, signal: r.signal, error: r.error?.message, stdout: r.stdout, stderr: r.stderr});
    if (evidence) fs.writeFileSync(path.join(evidence, 'commands.json'), JSON.stringify(records, null, 2));
    assert.equal(r.status, 0, JSON.stringify(records.at(-1)));
  }
  fs.writeFileSync(path.join(root, 'runtime.c'), `__declspec(dllexport) int ${symbol} = 1;\n`);
  fs.writeFileSync(path.join(root, 'consumer.c'), `__declspec(dllimport) extern volatile int ${symbol};\nint entry(void) { return ${symbol}; }\n`);
  run('clang', ['--target=x86_64-pc-windows-msvc', '-c', 'runtime.c', '-o', 'runtime.obj']);
  run('lld-link', ['/dll', '/noentry', '/out:runtime.dll', '/implib:runtime.lib', 'runtime.obj']);
  run('clang', ['--target=x86_64-pc-windows-msvc', '-c', 'consumer.c', '-o', 'consumer.obj']);
  run('lld-link', ['/entry:entry', '/subsystem:console', '/nodefaultlib', '/out:consumer.exe', 'consumer.obj', 'runtime.lib']);
  if (evidence) {
    const files = {};
    for (const name of fs.readdirSync(root)) {
      const bytes = fs.readFileSync(path.join(root, name));
      files[name] = {sha256: createHash('sha256').update(bytes).digest('hex'), bytes: bytes.length};
      fs.writeFileSync(path.join(evidence, name), bytes);
    }
    fs.writeFileSync(path.join(evidence, 'files.json'), JSON.stringify(files, null, 2));
  }
  return root;
}
for (const [symbol, count] of [['g_cjLoadBadMask', 1], ['ordinary_fixture_symbol', 0]]) {
  test(`real PE import/export tables count ${symbol} without nm dynamic ELF flags`, t => {
    const root = fixture(t, symbol);
    const exported = readRuntimeSymbols(path.join(root, 'runtime.dll'), target);
    const imported = readCompilerSymbols(path.join(root, 'consumer.exe'), target);
    console.log('WINDOWS_PE_SYMBOL_ASSERT_REACHED ' + symbol);
    assert.equal(countLoadBadMask(exported), count);
    assert.equal(countLoadBadMask(imported), count);
    assert.match(exported, new RegExp('^' + symbol + '$', 'm'));
    assert.match(imported, new RegExp('^' + symbol + '$', 'm'));
    assert.throws(() => readRuntimeSymbols(path.join(root, 'runtime.obj'), target), /expected x64 PE\/COFF image/);
  });
}
test('Windows reader rejects an ELF image rather than interpreting no COFF symbols as zero', () => {
  assert.throws(() => readCompilerSymbols(process.execPath, target), /expected x64 PE\/COFF image/);
});

#!/usr/bin/env node
import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import test from 'node:test';
import {buildWasmStdFull} from './wasm-std-full.mjs';
import {buildWasmStdCore, wasmStdInputs, WASM_LOCAL_MODE_CJC_ARGS} from './wasm-std-core.mjs';

const LOCAL = [...WASM_LOCAL_MODE_CJC_ARGS];

function write(file, text, mode = 0o644) {
  fs.mkdirSync(path.dirname(file), {recursive: true});
  fs.writeFileSync(file, text, {mode});
}

function assertLocalOnce(args, where) {
  const at = args.indexOf('--experimental');
  assert.notEqual(at, -1, where);
  assert.deepEqual(args.slice(at, at + LOCAL.length), LOCAL, where);
  for (const flag of ['--experimental', '--enable-local-mode', '--cfg']) {
    assert.equal(args.filter(arg => arg === flag).length, 1, `${where} ${flag}`);
  }
  assert.equal(args.filter(arg => arg === 'local_mode_api=off').length, 1, where);
}

function packageOf(args) {
  const dir = args[args.indexOf('-p') + 1];
  if (dir.endsWith(`${path.sep}core`) || dir.endsWith('/core')) return 'std.core';
  if (dir.endsWith(`${path.sep}env`) || dir.endsWith('/env')) return 'std.env';
  return 'std';
}

function readCjcArgs(log) {
  return fs.readFileSync(log, 'utf8').trim().split('\n').filter(Boolean).map(line => JSON.parse(line));
}

function fixture() {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'wasm-std-args-'));
  const sdk = path.join(dir, 'sdk');
  const stdlib = path.join(dir, 'stdlib');
  const stdRoot = path.join(stdlib, 'libs', 'std');
  const log = path.join(dir, 'cjc-args.jsonl');
  write(path.join(sdk, 'bin', 'cjc'), `#!${process.execPath}
const fs = require('node:fs');
const args = process.argv.slice(2);
fs.appendFileSync(${JSON.stringify(log)}, JSON.stringify(args) + '\\n');
if (args.includes('-O2') && process.env.FAIL_O2 === '1') process.exit(1);
const out = args.find(arg => arg.startsWith('--output=')).slice('--output='.length);
fs.mkdirSync(require('node:path').dirname(out), {recursive: true});
fs.writeFileSync(out, 'archive');
fs.writeFileSync(out + '.cjo', 'module');
`, 0o755);
  write(path.join(stdRoot, 'pkg.cj'), 'package std\npublic func rootPkg(): Int64 { 0 }\n');
  write(path.join(stdRoot, 'env', 'env.cj'), 'package std.env\npublic func envPkg(): Int64 { 0 }\n');
  const native = path.join(stdRoot, 'core', 'native');
  write(path.join(native, 'CMakeLists.txt'), '--redefine-sym ${SYM_PREFIX}Int64_ti=${SYM_PREFIX}Int64.ti\n');
  write(path.join(native, 'typetemplate.c'), 'template source\n');
  write(path.join(native, 'ffi.c'), 'ffi source\n');
  write(path.join(stdRoot, 'core', 'core.cj'), 'package std.core\npublic func corePkg(): Int64 { 0 }\n');
  const bounds = path.join(dir, 'bounds');
  write(path.join(bounds, 'src', 'memcpy_s.c'), 'bounds source\n');
  fs.mkdirSync(path.join(bounds, 'include'));
  const clang = path.join(dir, 'clang');
  write(clang, `#!${process.execPath}
const fs = require('node:fs');
const args = process.argv.slice(2);
const src = args.at(-3);
const out = args.at(-1);
if (String(src).endsWith('typetemplate.c')) fs.writeFileSync(out, '@Int64_ti = global i32 0\\n');
else fs.writeFileSync(out, 'object\\n');
`, 0o755);
  const llvmAr = path.join(dir, 'llvm-ar');
  write(llvmAr, `#!${process.execPath}
const fs = require('node:fs');
const [op, archive, ...objects] = process.argv.slice(2);
if (op !== 'rs') process.exit(2);
let body = fs.existsSync(archive) ? fs.readFileSync(archive) : Buffer.alloc(0);
for (const object of objects) body = Buffer.concat([body, Buffer.from('|'), fs.readFileSync(object)]);
fs.writeFileSync(archive, body);
`, 0o755);
  write(path.join(dir, 'pcre2', 'src', 'config.h.generic'), 'x');
  return {dir, sdk, stdlib, bounds, clang, llvmAr, log, pcre2: path.join(dir, 'pcre2')};
}

function assertPackageArgs(invocations, name, {subpkg, levels}) {
  const mine = invocations.filter(args => packageOf(args) === name);
  assert.deepEqual(mine.map(args => args.includes('-O2')), levels, name);
  for (const args of mine) {
    assertLocalOnce(args, name);
    assert.equal(args.filter(arg => arg === '--no-sub-pkg').length, subpkg ? 1 : 0, name);
    assert.equal(args.filter(arg => arg === '--target=wasm32-wasi').length, 1, name);
  }
}

test('std.core, ordinary packages, and aggregate root keep local-mode args at -O2', () => {
  const fx = fixture();
  try {
    const inputs = wasmStdInputs({
      stdlibSource: fx.stdlib, boundscheckSource: fx.bounds, clang: fx.clang, llvmAr: fx.llvmAr,
    });
    buildWasmStdCore(fx.sdk, path.join(fx.dir, 'core-direct'), inputs, {cjcArgs: ['-O2']});
    const direct = readCjcArgs(fx.log);
    assert.equal(direct.length, 1);
    assertPackageArgs(direct, 'std.core', {subpkg: true, levels: [true]});
    fs.writeFileSync(fx.log, '');
    const built = buildWasmStdFull({
      sdk: fx.sdk, stdlibSource: fx.stdlib, boundscheckSource: fx.bounds, pcre2Source: fx.pcre2,
      clang: fx.clang, llvmAr: fx.llvmAr, work: path.join(fx.dir, 'work-o2'),
      only: ['std.core', 'std.env', 'std'], fallbackOpt: false,
    });
    const args = readCjcArgs(fx.log);
    assertPackageArgs(args, 'std.core', {subpkg: true, levels: [true]});
    assertPackageArgs(args, 'std.env', {subpkg: true, levels: [true]});
    assertPackageArgs(args, 'std', {subpkg: false, levels: [true]});
    assert.equal(built.results.find(rec => rec.name === 'std').opt, 'O2');
    assert.equal(built.results.find(rec => rec.name === 'std.env').opt, 'O2');
    assert.equal(built.results.find(rec => rec.name === 'std.core').opt, 'O2');
  } finally {
    fs.rmSync(fx.dir, {recursive: true, force: true});
  }
});

test('default-opt fallback keeps local-mode args and still omits --no-sub-pkg on root std', () => {
  const fx = fixture();
  const prev = process.env.FAIL_O2;
  process.env.FAIL_O2 = '1';
  try {
    const built = buildWasmStdFull({
      sdk: fx.sdk, stdlibSource: fx.stdlib, boundscheckSource: fx.bounds, pcre2Source: fx.pcre2,
      clang: fx.clang, llvmAr: fx.llvmAr, work: path.join(fx.dir, 'work-fallback'),
      only: ['std.core', 'std.env', 'std'], fallbackOpt: true,
    });
    const args = readCjcArgs(fx.log);
    assertPackageArgs(args, 'std.core', {subpkg: true, levels: [true, false]});
    assertPackageArgs(args, 'std.env', {subpkg: true, levels: [true, false]});
    assertPackageArgs(args, 'std', {subpkg: false, levels: [true, false]});
    assert.equal(built.results.find(rec => rec.name === 'std').opt, 'default');
    assert.equal(built.results.find(rec => rec.name === 'std').status, 'BUILT_DEFAULT_OPT');
    assert.equal(built.results.find(rec => rec.name === 'std.core').opt, 'default');
  } finally {
    if (prev === undefined) delete process.env.FAIL_O2;
    else process.env.FAIL_O2 = prev;
    fs.rmSync(fx.dir, {recursive: true, force: true});
  }
});

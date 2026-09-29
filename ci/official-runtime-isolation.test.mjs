import assert from 'node:assert/strict';
import {spawnSync} from 'node:child_process';
import fs from 'node:fs';
import path from 'node:path';
import crypto from 'node:crypto';
import test from 'node:test';
import {gzipSync} from 'node:zlib';

const repo = path.resolve(import.meta.dirname, '..');
const hash = file => crypto.createHash('sha256').update(fs.readFileSync(file)).digest('hex');
function run(command, args, env, cwd = repo) {
  return spawnSync(command, args, {env: {...process.env, ...env}, cwd, encoding: 'utf8'});
}
function ok(result) { assert.equal(result.status, 0, `${result.stdout}\n${result.stderr}`); }
function fixture(t) {
  const root = fs.mkdtempSync(path.join(process.env.RUNNER_TEMP || repo, 'isolation-test-'));
  t.after(() => fs.rmSync(root, {recursive: true, force: true}));
  const sdk = path.join(root, 'sdk');
  const host = path.join(sdk, 'runtime/lib/linux_x86_64_cjnative');
  const dist = path.join(root, 'dist');
  for (const dir of [host, dist, path.join(sdk, 'bin')]) fs.mkdirSync(dir, {recursive: true});
  for (const [dir, value] of [[host, 7], [dist, 9]]) {
    const source = path.join(dir, 'runtime.c');
    fs.writeFileSync(source, `int runtime_value(void) { return ${value}; }\n`);
    ok(run('cc', ['-shared', '-fPIC', source, '-o', path.join(dir, 'libcangjie-runtime.so')], {}));
  }
  const source = path.join(root, 'main.c');
  fs.writeFileSync(source, '#include <stdio.h>\nextern int runtime_value(void);\nint main(void) { printf("runtime=%d\\n", runtime_value()); return 0; }\n');
  const exe = path.join(sdk, 'bin/host');
  ok(run('cc', [source, `-L${host}`, '-lcangjie-runtime', '-Wl,-rpath,$ORIGIN/../runtime/lib/linux_x86_64_cjnative', '-o', exe], {}));
  const pin = fs.readFileSync(path.join(repo, 'ci/runtime_pin.env'), 'utf8').match(/^RUNTIME_REF=(.+)$/m)[1];
  fs.writeFileSync(path.join(dist, 'SOURCE_SHA'), `${pin}\n`);
  fs.writeFileSync(path.join(dist, 'libcangjie-runtime.so.sha256'), `${hash(path.join(dist, 'libcangjie-runtime.so'))}\n`);
  const env = {CANGJIE_HOME: sdk, RUNNER_TEMP: root, LD_LIBRARY_PATH: host,
    CJCJ_PATCHED_RUNTIME_LIB_DIR: dist, GITHUB_ENV: path.join(root, 'github-env')};
  console.log(`FIXTURE exe=${hash(exe)} official=${hash(path.join(host, 'libcangjie-runtime.so'))} coloured=${hash(path.join(dist, 'libcangjie-runtime.so'))}`);
  return {root, sdk, host, dist, exe, env};
}
function audit(f, command = f.exe, args = [], env = {}) {
  return run(process.execPath, ['ci/with-runtime-audit.mjs', '--', command, ...args], {...f.env, ...env});
}

test('installer preserves official SDK bytes and publishes an independent runtime', t => {
  const f = fixture(t);
  const before = hash(path.join(f.host, 'libcangjie-runtime.so'));
  const dest = path.join(f.root, 'patched');
  const result = run('npx', ['--yes', 'zx@8', 'ci/install_patched_runtime.mjs', f.dist, dest], f.env);
  ok(result);
  const after = hash(path.join(f.host, 'libcangjie-runtime.so'));
  console.log(`TARGET_ASSERT_EXECUTED sdk_unchanged before=${before} after=${after}`);
  assert.equal(after, before, 'official SDK runtime must remain byte-identical');
  const published = path.join(dest, 'lib/linux_x86_64_cjnative');
  assert.equal(hash(path.join(published, 'libcangjie-runtime.so')), hash(path.join(f.dist, 'libcangjie-runtime.so')));
  assert.equal(fs.readFileSync(f.env.GITHUB_ENV, 'utf8'), `CJCJ_PATCHED_RUNTIME_LIB_DIR=${published}\n`);
  const observed = audit(f, f.exe, [], {CJCJ_PATCHED_RUNTIME_LIB_DIR: published});
  ok(observed);
  assert.match(observed.stdout, /runtime=7/);
});

test('actual host runtime load is accepted and recorded', t => {
  const f = fixture(t); const result = audit(f); ok(result);
  console.log(`TARGET_ASSERT_EXECUTED host_runtime ${result.stdout}`);
  assert.match(result.stdout, /runtime=7/);
  assert.match(result.stdout, /RUNTIME_LOAD .*official=1 coloured=0/);
});

test('coloured runtime path rejects the official executable before main', t => {
  const f = fixture(t); const result = audit(f, f.exe, [], {LD_LIBRARY_PATH: f.dist});
  console.log(`TARGET_ASSERT_EXECUTED path_rejection rc=${result.status} ${result.stdout}`);
  assert.equal(result.status, 86);
  assert.match(result.stdout, /OFFICIAL_RUNTIME_MISMATCH .*official=1 coloured=1/);
  assert.doesNotMatch(result.stdout, /runtime=9/);
});

test('original in-place overwrite is rejected by hash, including an absorbed child failure', t => {
  const f = fixture(t);
  fs.copyFileSync(path.join(f.dist, 'libcangjie-runtime.so'), path.join(f.host, 'libcangjie-runtime.so'));
  const result = audit(f, '/bin/sh', ['-c', '"$1"; exit 0', 'sh', f.exe]);
  console.log(`TARGET_ASSERT_EXECUTED overwrite_rejection rc=${result.status} ${result.stdout}`);
  assert.equal(result.status, 86);
  assert.match(result.stdout, /OFFICIAL_RUNTIME_MISMATCH/);
  assert.ok(result.stdout.includes(`so=${f.host}/libcangjie-runtime.so`));
});

test('rebuilt executable outside the SDK may explicitly select coloured runtime', t => {
  const f = fixture(t); const rebuilt = path.join(f.root, 'rebuilt');
  const source = path.join(f.root, 'rebuilt.c');
  fs.writeFileSync(source, '#include <stdio.h>\nextern int runtime_value(void);\nint main(void) { puts("rebuilt consumer"); printf("runtime=%d\\n", runtime_value()); return 0; }\n');
  ok(run('cc', [source, `-L${f.dist}`, '-lcangjie-runtime', '-o', rebuilt], {}));
  const result = audit(f, rebuilt, [], {LD_LIBRARY_PATH: f.dist}); ok(result);
  console.log(`TARGET_ASSERT_EXECUTED rebuilt_runtime ${result.stdout}`);
  assert.match(result.stdout, /runtime=9/);
  assert.match(result.stdout, /official=0 coloured=1/);
});


test('installer rejects a destination inside the official SDK before creating it', t => {
  const f = fixture(t); const dest = path.join(f.sdk, 'forbidden');
  const result = run('npx', ['--yes', 'zx@8', 'ci/install_patched_runtime.mjs', f.dist, dest], f.env);
  assert.notEqual(result.status, 0);
  assert.match(result.stderr, /destination must be outside the official SDK/);
  assert.equal(fs.existsSync(dest), false);
});

test('renamed coloured preload is rejected by content hash', t => {
  const f = fixture(t); const alias = path.join(f.root, 'renamed.so');
  fs.copyFileSync(path.join(f.dist, 'libcangjie-runtime.so'), alias);
  const result = audit(f, f.exe, [], {LD_PRELOAD: alias});
  console.log(`TARGET_ASSERT_EXECUTED renamed_rejection rc=${result.status} ${result.stdout}`);
  assert.equal(result.status, 86);
  assert.ok(result.stdout.includes(`so=${alias}`));
});


test('copied official executable outside SDK remains official by identity', t => {
  const f = fixture(t); const copy = path.join(f.root, 'copied-host');
  fs.copyFileSync(f.exe, copy);
  const result = audit(f, copy, [], {LD_LIBRARY_PATH: f.dist});
  console.log(`TARGET_ASSERT_EXECUTED copied_host_rejection rc=${result.status} ${result.stdout}`);
  assert.equal(result.status, 86);
  assert.match(result.stdout, /official=1 coloured=1/);
});


function optimizerFixture(t) {
  const f = fixture(t);
  const bin = path.join(f.sdk, 'third_party/llvm/bin');
  fs.mkdirSync(bin, {recursive: true});
  f.officialOpt = path.join(bin, 'opt');
  f.patchedOpt = path.join(f.root, 'patched-opt');
  for (const [file, text] of [[f.officialOpt, 'official optimizer executed'], [f.patchedOpt, 'coloured optimizer executed']]) {
    const src = path.join(f.root, 'opt.c');
    fs.writeFileSync(src, `#include <stdio.h>\nint main(void) { puts("${text}"); return 0; }\n`);
    ok(run('cc', [src, '-o', file], {}));
  }
  f.compiler = path.join(f.sdk, 'bin/cjc');
  f.rebuiltCompiler = path.join(f.root, 'rebuilt-cjc');
  for (const [file, text] of [[f.compiler, 'official frontend'], [f.rebuiltCompiler, 'rebuilt frontend']]) {
    const src = path.join(f.root, 'compiler.c');
    fs.writeFileSync(src, `#include <stdio.h>\n#include <stdlib.h>\nint main(int argc, char **argv) { puts("${text}"); return argc == 2 ? (system(argv[1]) != 0) : 0; }\n`);
    ok(run('cc', [src, '-o', file], {}));
  }
  f.env.CJCJ_PATCHED_OPT = f.patchedOpt;
  return f;
}

test('optimizer publication leaves the official optimizer byte-identical', t => {
  const f = optimizerFixture(t); const before = hash(f.officialOpt);
  const archive = path.join(f.root, 'opt.gz');
  fs.writeFileSync(archive, gzipSync(fs.readFileSync(f.patchedOpt)));
  const output = path.join(f.root, 'patched-llvm/bin/opt');
  const result = run(process.execPath, ['ci/install_patched_opt.mjs', f.officialOpt, archive, hash(f.patchedOpt), output], f.env);
  const after = hash(f.officialOpt);
  console.log(`TARGET_ASSERT_EXECUTED official_opt_unchanged before=${before} after=${after}`);
  assert.equal(after, before, 'official optimizer must remain byte-identical');
  ok(result);
  assert.equal(hash(output), hash(f.patchedOpt));
  assert.equal(fs.readFileSync(f.env.GITHUB_ENV, 'utf8'), `CJCJ_PATCHED_OPT=${output}\n`);
});

test('official compiler may execute its official optimizer', t => {
  const f = optimizerFixture(t); const result = audit(f, f.compiler, [f.officialOpt]);
  console.log(`TARGET_ASSERT_EXECUTED official_opt_allowed rc=${result.status} ${result.stdout}`);
  ok(result);
  assert.match(result.stdout, /official optimizer executed/);
});

test('official compiler cannot execute coloured optimizer through a shell', t => {
  const f = optimizerFixture(t); const result = audit(f, f.compiler, [f.patchedOpt]);
  console.log(`TARGET_ASSERT_EXECUTED official_opt_rejected rc=${result.status} ${result.stdout}`);
  assert.equal(result.status, 86);
  assert.match(result.stdout, /OFFICIAL_TOOLCHAIN_MISMATCH .*official_parent=1/);
  assert.doesNotMatch(result.stdout, /coloured optimizer executed/);
});

test('overwritten SDK optimizer is rejected by hash under the official compiler', t => {
  const f = optimizerFixture(t); fs.copyFileSync(f.patchedOpt, f.officialOpt);
  const result = audit(f, f.compiler, [f.officialOpt]);
  console.log(`TARGET_ASSERT_EXECUTED overwritten_opt_rejected rc=${result.status} ${result.stdout}`);
  assert.equal(result.status, 86);
  assert.match(result.stdout, /OFFICIAL_TOOLCHAIN_MISMATCH .*official_parent=1/);
});

test('rebuilt compiler may explicitly execute the isolated optimizer', t => {
  const f = optimizerFixture(t); const result = audit(f, f.rebuiltCompiler, [f.patchedOpt]);
  console.log(`TARGET_ASSERT_EXECUTED rebuilt_opt_allowed rc=${result.status} ${result.stdout}`);
  ok(result);
  assert.match(result.stdout, /coloured optimizer executed/);
  assert.match(result.stdout, /OPT_LOAD .*official_parent=0/);
});

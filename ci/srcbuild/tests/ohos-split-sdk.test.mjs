import assert from 'node:assert/strict';
import test from 'node:test';
import fs from 'node:fs/promises';
import path from 'node:path';
import {tmpdir} from 'node:os';
import {fileURLToPath} from 'node:url';
import {spawnSync} from 'node:child_process';
import {readLocalExportFlag} from '../lib/ohos-runtime.mjs';
import {checkPair, installOhosStage3, targetRef, tuple} from '../lib/ohos-split-sdk.mjs';

const host = '9991cf4f4c9cb3465bb5aec28a5590f6c529be4e';
const compiler = 'ea6d3b5fc73b5e4cc2926535005a46a92109b2b9';
const stage = {phase:'stage2', platform:'linux_x86_64', runtimeCommit:host, compilerCommit:compiler,
  compilerSha256:'ab8e03d32d95b8a84da42a4d11520b2644796cc339e50825426bb38bf5c33be0',
  sources:{compiler:{commit:compiler}, llvm:{commit:'f2a8e33d2dbb6797d65813cd20f529d9567843a1'},
    runtime:{commit:host}, std:{commit:host}}};
test('OHOS split runtime is bound to the host stage, compiler bytes and target tuple', () => {
  checkPair(stage, host, targetRef, targetRef, tuple);
  for (const changed of [{phase:'stage3'}, {compilerSha256:'0'.repeat(64)}, {compilerCommit:targetRef},
    {runtimeCommit:targetRef}, {sources:{...stage.sources,llvm:{commit:compiler}}}, {llvmCommit:compiler}])
    assert.throws(() => checkPair({...stage,...changed}, host, targetRef, targetRef, tuple), /OHOS split source mismatch/);
  for (const args of [[host, targetRef, host, tuple], [host, host, host, tuple],
    [targetRef, targetRef, targetRef, tuple], [host, targetRef, targetRef, 'linux_ohos_x86_64_cjnative']])
    assert.throws(() => checkPair(stage, ...args), /OHOS split source mismatch/);
});

test('local export rejects a conflicting parent toolchain and records literal zero on recovery', async t => {
  const dir = await fs.mkdtemp(path.join(tmpdir(), 'ohos-local-'));
  t.after(() => fs.rm(dir, {recursive:true, force:true}));
  const parent = path.join(dir, 'parent.cmake'), build = path.join(dir, 'build');
  await fs.writeFile(path.join(dir, 'CMakeLists.txt'), 'cmake_minimum_required(VERSION 3.16)\nproject(probe NONE)\n');
  const configure = () => spawnSync('cmake', ['-S', dir, '-B', build,
    '-DCMAKE_TOOLCHAIN_FILE=' + fileURLToPath(new URL('../lib/ohos-local-export.cmake', import.meta.url))],
    {encoding:'utf8', env:{...process.env, CJCJ_PARENT_RUNTIME_TOOLCHAIN:parent}});
  const conflict = 'set(GLOBAL_EXPORT_FLAG 10 CACHE STRING "parent setting" FORCE)\n';
  for (const [input, message] of [[conflict, /got '10'/], [conflict + 'set(GLOBAL_EXPORT_FLAG 0)\n', /cached '10'/]]) {
    await fs.writeFile(parent, input);
    const result = configure();
    assert.equal(result.status, 1, result.error?.message ?? result.stderr);
    assert.match(result.stderr, /OHOS local export requires GLOBAL_EXPORT_FLAG=0/);
    assert.match(result.stderr, message);
  }
  await fs.writeFile(parent, 'set(GLOBAL_EXPORT_FLAG 0 CACHE STRING "parent setting" FORCE)\n');
  const recovered = configure();
  assert.equal(recovered.status, 0, recovered.stderr);
  assert.equal(await readLocalExportFlag(path.join(build, 'CMakeCache.txt')), '0');
});

test('only one exact string cache entry can qualify the Stage3 install', async t => {
  const dir = await fs.mkdtemp(path.join(tmpdir(), 'ohos-cache-'));
  t.after(() => fs.rm(dir, {recursive:true, force:true}));
  const file = path.join(dir, 'CMakeCache.txt');
  for (const entry of ['', 'GLOBAL_EXPORT_FLAG:STRING=10', 'GLOBAL_EXPORT_FLAG:STRING=1',
    'GLOBAL_EXPORT_FLAG:STRING=0 ', 'GLOBAL_EXPORT_FLAG:BOOL=0',
    'GLOBAL_EXPORT_FLAG:STRING=0\nGLOBAL_EXPORT_FLAG:STRING=10']) {
    await fs.writeFile(file, entry + '\n');
    await assert.rejects(readLocalExportFlag(file), /expected GLOBAL_EXPORT_FLAG=0/);
  }
  await fs.writeFile(file, 'GLOBAL_EXPORT_FLAG:UNINITIALIZED=0\r\n');
  assert.equal(await readLocalExportFlag(file), '0');
  for (const globalExportFlag of [undefined, '10', '1', 0]) {
    await assert.rejects(installOhosStage3({globalExportFlag}), /requires verified GLOBAL_EXPORT_FLAG=0/);
  }
});

#!/usr/bin/env zx
import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs/promises';
import path from 'node:path';
import os from 'node:os';
import crypto from 'node:crypto';
import {spawnSync} from 'node:child_process';
import {fileURLToPath} from 'node:url';

// Migration of the retired Python installer's frontend-alias obligation.
// These are native control executables, not a qualified Cangjie compiler.
test('formal SDK flow compiler fixture rejects a replaced frontend and restores its producer', async () => {
  const parent = process.env.RELEASE_EVIDENCE_TEST_ROOT || os.tmpdir();
  await fs.mkdir(parent, {recursive: true});
  const root = await fs.mkdtemp(path.join(parent, 'compiler-entry-'));
  const sdk = path.join(root, 'install');
  const cli = fileURLToPath(new URL('./compiler_identity.mjs', import.meta.url));
  const producer = '/bin/true';
  const expected = crypto.createHash('sha256').update(await fs.readFile(producer)).digest('hex');
  const config=path.join(root,'fixture.json');
  await fs.writeFile(config,JSON.stringify({work:path.join(root,'work'),install:sdk,repos:{},finalStage:'fixture',
    stages:[{id:'fixture',output:sdk,copies:[{from:producer,to:'bin/cjcj-stage1'}],
      links:{'bin/cjc':'cjcj-stage1','bin/cjc-frontend':'cjcj-stage1'},
      metadata:{compilerFile:'bin/cjcj-stage1',compilerSha256:expected}}]}));
  const run = args => spawnSync(process.execPath, [cli, sdk, ...args], {encoding:'utf8'});
  const install = () => spawnSync(process.execPath,[fileURLToPath(new URL('./sdk-build.mjs',import.meta.url)),
    '--config',config,'--no-package'],{encoding:'utf8'});
  const results = [];
  const record = (name, result) => {
    results.push({name, rc:result.status, signal:result.signal, stdout:result.stdout, stderr:result.stderr});
    return result;
  };
  let result = record('install', install());
  assert.equal(result.status, 0, result.stderr);
  const frontend = path.join(sdk, 'bin/cjc-frontend');
  assert.equal(await fs.readlink(frontend), 'cjcj-stage1');
  await fs.unlink(frontend);
  await fs.copyFile('/bin/false', frontend);
  result = record('frontend-cut', run(['--expected-producer-sha256', expected]));
  assert.equal(result.status, 1);
  assert.match(result.stderr, /cjc-frontend: expected same-directory cjcj-stage1 link/);
  const control = spawnSync(path.join(sdk, 'bin/cjc'), [], {encoding:'utf8'});
  record('independent-cjc-control', control);
  assert.equal(control.status, 0);
  result = record('restore', install());
  assert.equal(result.status, 0, result.stderr);
  result = record('verify-restored', run(['--expected-producer-sha256', expected]));
  assert.equal(result.status, 0, result.stderr);
  const restored = spawnSync(frontend, [], {encoding:'utf8'});
  record('frontend-restored-consumer', restored);
  assert.equal(restored.status, 0);
  await fs.writeFile(path.join(root, 'commands.json'), JSON.stringify(results, null, 2));
  console.log('SDK_VERIFY_FRONTEND_RESTORED ' + root);
});

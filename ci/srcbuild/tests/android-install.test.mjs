#!/usr/bin/env zx
import assert from 'node:assert/strict';
import {test} from 'node:test';
import fs from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';
import crypto from 'node:crypto';
import {spawnSync} from 'node:child_process';
import {fileURLToPath} from 'node:url';
import {androidTuple as tuple, readAndroidInputs} from '../lib/android-sdk.mjs';
import {reconcileStdArtifacts} from '../../../build/lib/release-manifest.mjs';
import {writeCrossRuntimeManifest} from '../../release/cross-runtime.mjs';

test('Android install replaces only its tuple and keeps host and target provenance independent', async t => {
  const workspace = await fs.mkdtemp(path.join(os.tmpdir(), 'android-install-'));
  t.after(() => fs.rm(workspace, {recursive:true, force:true}));
  const sdk = path.join(workspace, 'software/cangjie');
  const std = path.join(workspace, 'software/final-std-android-aarch64'), runtime = path.join(std, 'cross-runtime');
  const put = async (root, rel, bytes) => {
    const file = path.join(root, rel);
    await fs.mkdir(path.dirname(file), {recursive:true});
    await fs.writeFile(file, bytes);
    return crypto.createHash('sha256').update(bytes).digest('hex') + '  ' + rel;
  };
  const ref = '1'.repeat(40), source = {repository:'runtime', commit:ref, status:'resolved'};
  await put(sdk, 'STAGE-INPUTS.json', JSON.stringify({runtimeCommit:ref,sources:{runtime:source}}));
  const host = await put(sdk, 'modules/host/std/std.core.cjo', 'host std');
  const core = 'modules/' + tuple + '/std/std.core.cjo';
  const old = 'lib/' + tuple + '/stale.a';
  await put(sdk, old, 'old');
  await put(sdk, core, 'stale target module');
  assert.equal(await readAndroidInputs(sdk, source), null);
  const files = [await put(std, core, 'target module'), await put(std, 'lib/' + tuple + '/libcangjie-std-core.a', 'target archive'),
    await put(std, 'runtime/lib/' + tuple + '/libcangjie-std-core.so', 'target library')];
  await put(std, 'PROVENANCE.txt', 'STD_SOURCE_COMMIT = ' + ref + '\nARTIFACT-SHA256:\n' + files.join('\n') + '\n');
  // The runtime manifest checks ELF class, byte order and AArch64 machine.
  const elf = Buffer.alloc(64);
  elf.set([0x7f, 69, 76, 70, 2, 1]); elf.writeUInt16LE(183, 18);
  for (const rel of ['libcangjie-runtime.so','libboundscheck.so'])
    await put(runtime, 'runtime/lib/' + tuple + '/' + rel, elf);
  await put(runtime, 'lib/' + tuple + '/cjstart.o', 'entry');
  await writeCrossRuntimeManifest({root:runtime, tuple, runtimeRef:ref});
  const install = () => spawnSync(process.execPath, [fileURLToPath(new URL('../steps/install-android.mjs', import.meta.url))],
    {encoding:'utf8', env:{...process.env, CANGJIE_WORKSPACE:workspace, CJCJ_NATIVE_RUNTIME_REF:ref, CJCJ_SRCBUILD_TARGET:'linux-x64'}});
  const first = install();
  assert.equal(first.status, 0, first.stderr);
  assert.equal(await fs.readFile(path.join(sdk,'modules/host/std/std.core.cjo'),'utf8'), 'host std');
  console.log('HOST_CONTROL_OK; ASSERT_INSTALLED_ANDROID_MODULE');
  assert.equal(await fs.readFile(path.join(sdk, core),'utf8'), 'target module');
  await assert.rejects(fs.stat(path.join(sdk, old)), {code:'ENOENT'});
  const android = await readAndroidInputs(sdk, source);
  const reconcile = () => reconcileStdArtifacts(sdk, 'ARTIFACT-SHA256:\n' + host + '\n', {otherStdFiles:android.stdFiles});
  await reconcile();
  await put(std, core, 'corrupted');
  const bad = install();
  assert.equal(bad.status, 1);
  assert.match(bad.stderr, /ANDROID_ARTIFACT_BYTES .*std.core.cjo/);
  assert.equal(await fs.readFile(path.join(sdk,core),'utf8'), 'target module');
  await put(sdk, 'modules/host/std/unrecorded.cjo', 'extra');
  await assert.rejects(reconcile, /STD_ARTIFACT_UNRECORDED modules\/host/);
});

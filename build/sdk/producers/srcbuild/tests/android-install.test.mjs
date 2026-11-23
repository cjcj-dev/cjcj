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
import {reconcileStdArtifacts} from '../../../../lib/release-manifest.mjs';
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
  const install = (extra = {}) => spawnSync(process.execPath, [fileURLToPath(new URL('../steps/install-android.mjs', import.meta.url))],
    {encoding:'utf8', env:{...process.env, CANGJIE_WORKSPACE:workspace, CJCJ_NATIVE_RUNTIME_REF:ref, CJCJ_SRCBUILD_TARGET:'linux-x64', CJCJ_ANDROID_RUNTIME_REF:'', ...extra}});
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

  const hostRef = '9991cf4f4c9cb3465bb5aec28a5590f6c529be4e', targetRef = '5afcbc85cca1569db8c80b4fea6ed0f19da0b758';
  const hostSource = {...source, commit:hostRef};
  const stage = {phase:'stage3', compilerSha256:'5190316791e889c882684361d79a8fc70f7a1f9d606316b3cde032bf0c5f6fc1', runtimeCommit:hostRef, compilerCommit:'ea6d3b5fc73b5e4cc2926535005a46a92109b2b9',
    sources:{runtime:hostSource, std:hostSource, llvm:{commit:'f2a8e33d2dbb6797d65813cd20f529d9567843a1'}}};
  const stageText = JSON.stringify(stage);
  await put(sdk, 'STAGE-INPUTS.json', stageText);
  await put(std, core, 'target module');
  await put(std, 'PROVENANCE.txt', 'STD_SOURCE_COMMIT = ' + targetRef + '\nARTIFACT-SHA256:\n' + files.join('\n') + '\n');
  await writeCrossRuntimeManifest({root:runtime, tuple, runtimeRef:targetRef, sourceRepository:'target-source'});
  const splitEnv = {CJCJ_NATIVE_RUNTIME_REF:hostRef, CJCJ_ANDROID_RUNTIME_REF:targetRef};
  const rejected = install({...splitEnv, CJCJ_ANDROID_RUNTIME_REF:'a'.repeat(40)});
  assert.equal(rejected.status, 1); assert.match(rejected.stderr, /ANDROID_INSTALL_RUNTIME_PAIR/);
  // The previous target has the PCRE2 fix but lacks four dynamic exports.
  const previous = install({...splitEnv, CJCJ_ANDROID_RUNTIME_REF:'20995aae195f134ecc2c94bb6a90239c31b673f4'});
  assert.equal(previous.status, 1); assert.match(previous.stderr, /ANDROID_INSTALL_RUNTIME_PAIR/);
  const split = install(splitEnv);
  assert.equal(split.status, 0, split.stderr);
  assert.equal(await fs.readFile(path.join(sdk,'STAGE-INPUTS.json'),'utf8'), stageText);
  const actual = await readAndroidInputs(sdk,hostSource,undefined,stage);
  for (const row of actual.components) assert.deepEqual(row.source,{...source, repository:'target-source', commit:targetRef});
  await assert.rejects(readAndroidInputs(sdk, hostSource, undefined, {...stage,compilerCommit:ref}), /ANDROID_INSTALL_RUNTIME_PAIR/);
});

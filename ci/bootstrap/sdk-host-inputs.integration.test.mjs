#!/usr/bin/env zx
// Check original download integrity and actual selected compiler execution.
// Repaired host LLVM remains a separate producer input.
import path from 'node:path';
import test from 'node:test';
import assert from 'node:assert/strict';
import {verifyOfficialSdkIdentity} from '../../build/lib/official-sdk-identity.mjs';
import {targetForHost} from '../../build/lib/targets.mjs';
import {hostIdentity} from '../release/host_llvm.mjs';
import {readHostToolchainPin} from '../host-toolchain-pin.mjs';
import {fileDigest, readJson} from './sdk-io.mjs';
const sdk=process.env.HOST_IDENTITY_SDK, archive=process.env.HOST_IDENTITY_ARCHIVE, library=process.env.HOST_IDENTITY_LLVM;
const artifact=process.env.HOST_IDENTITY_LLVM_ARTIFACT || process.env.CJCJ_BOOTSTRAP_HOST_LLVM_ARTIFACT;
if (!sdk || !archive || !library || !artifact) throw new Error('HOST_IDENTITY_SDK/ARCHIVE/LLVM and original LLVM artifact must identify genuine received inputs');
const target=targetForHost().spec.key;
test('selected official H reports its original release and actual compiler version',async()=>{
  const facts=await verifyOfficialSdkIdentity({root:sdk,archive,version:readHostToolchainPin(),platform:target});
  console.log(`OFFICIAL_H_INPUT_TARGET_ASSERTION_EXECUTED ${JSON.stringify(facts)}`);
  assert.equal(facts.compiler.rc,0);assert.equal(facts.compiler.version,facts.version);
});
test('repaired H LLVM retains original source, producer, artifact and ordinary digest',async()=>{
  const pin=hostIdentity(), observed=await readJson(path.join(artifact,'manifest.json'));
  const sha256=await fileDigest(library);
  console.log(`HOST_LLVM_INPUT_TARGET_ASSERTION_EXECUTED actual=${sha256} expected=${pin.sha256}`);
  assert.equal(sha256,pin.sha256);
  for(const key of ['source_sha','run_id','run_attempt','producer_sha','platform','sha256'])
    assert.equal(observed[key],pin[key],`original repaired H producer field ${key}`);
});

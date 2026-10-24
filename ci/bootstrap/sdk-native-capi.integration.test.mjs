#!/usr/bin/env zx
// Actual frozen N, actual native producer, and the formal qualification CLI.
// This test exclusively owns its isolated product checkout during cut arms.
import fs from 'node:fs/promises';
import path from 'node:path';
import {fileURLToPath} from 'node:url';
import {spawnSync} from 'node:child_process';
import test from 'node:test';
import assert from 'node:assert/strict';
const request = process.env.SDK_CAPI_REQUEST, evidence = process.env.SDK_CAPI_EVIDENCE;
if (!request || !evidence) throw new Error('SDK_CAPI_REQUEST and SDK_CAPI_EVIDENCE are required');
const root = process.env.SDK_CAPI_PRODUCT || path.dirname(fileURLToPath(import.meta.url));
await fs.mkdir(evidence,{recursive:true});
const cli = path.join(root,'sdk-native-capi.mjs'), cpp = path.join(root,'native-qualification/capi.cpp');
const call = 'reinterpret_cast<void (*)()>(symbol(std::string("LLVMInitialize") + target + part))();';
async function invoke(name) {
  const argv = [cli,request], result = spawnSync(process.execPath,argv,{encoding:'utf8',maxBuffer:8*1024*1024});
  await fs.writeFile(path.join(evidence,name+'.log'),result.stdout+result.stderr);
  await fs.writeFile(path.join(evidence,name+'.json'),JSON.stringify({argv,rc:result.status,signal:result.signal})+'\n');
  const line=result.stdout.split('\n').find(line=>line.startsWith('LLVM_NATIVE_CAPI_OBSERVED '));
  const observed=line&&JSON.parse(line.slice('LLVM_NATIVE_CAPI_OBSERVED '.length));
  console.log(`CAPI_TARGET_ASSERTION_EXECUTED name=${name} rc=${result.status} observed=${JSON.stringify(observed)}`);
  return {result,observed};
}
test('real N C API registers all three targets through the formal entry',async()=>{
  const {result,observed}=await invoke('normal');
  assert.ok(observed,'actual C API result must reach the qualifier');
  assert.deepEqual(observed.lookups.map(row=>[row.rc,row.name]),[[0,'x86-64'],[0,'arm'],[0,'aarch64']], 'actual target lookup result');
  assert.equal(result.status,0,result.stderr);
});
test('formal consumer rejects one missing real registration while the other targets remain available',async()=>{
  const before=await fs.readFile(cpp,'utf8');
  assert.ok(before.includes(call),'actual native producer registration call exists');
  try {
    await fs.writeFile(cpp,before.replace(call,`if (std::string(target) != "X86" || std::string(part) != "TargetInfo") ${call}`));
    const {result,observed}=await invoke('missing-x86-registration');
    assert.ok(observed,'no compile/load error may mask the lookup result');
    assert.equal(observed.lookups[0].rc,1,'real X86 lookup must observe missing registration');
    assert.deepEqual(observed.lookups.slice(1).map(row=>[row.rc,row.name]),[[0,'arm'],[0,'aarch64']],'independent target control');
    assert.equal(result.status,1,'formal qualifier must reject its observed failed target lookup');
    assert.match(result.stderr,/rule=LLVM_DYLIB_TARGET_LOOKUP/);
  } finally { await fs.writeFile(cpp,before); }
});

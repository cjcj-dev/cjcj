#!/usr/bin/env zx
// Native object consumer qualification; no runtime/std/LLVM producer runs.
// The real stage0 reaches SDK verification, then stops at the explicitly absent
// source-layout program. This never certifies a finished bootstrap or compiler.
import fs from 'node:fs';
import path from 'node:path';
import {fileURLToPath} from 'node:url';
import {spawnSync} from 'node:child_process';
import {prepareNativeTestInputs} from './native_test_inputs.mjs';
import {sha256File} from './sdk_verify.mjs';
import {execute} from './host_tools.mjs';
const repo=path.resolve(path.dirname(fileURLToPath(import.meta.url)),'../..');
const out=path.resolve(process.argv[2]||'');
if(!process.argv[2]||!path.isAbsolute(process.argv[2]))throw new Error('absolute evidence directory required');
fs.mkdirSync(out,{recursive:true});
const f=prepareNativeTestInputs(out+'/inputs',repo);
const identity={head:execute('git',['-C',repo,'rev-parse','HEAD']).stdout.trim(),native:f.native,product:Object.fromEntries(['ci/bootstrap/bootstrap.sh','ci/bootstrap/bootstrap.mjs','ci/bootstrap/sdk_build.sh','ci/bootstrap/sdk_build.mjs','ci/bootstrap/sdk_verify.py','ci/bootstrap/sdk_verify.mjs','ci/bootstrap/native_libraries.mjs','ci/bootstrap/host_tools.mjs','ci/runtime_pin.env'].map(file=>[file,sha256File(repo+'/'+file)])),inputs:Object.fromEntries([f.hostLlvm,f.base+'/third_party/llvm/lib/'+f.native.library,f.base+'/bin/cjc',f.colour,f.host,f.ast,f.tuple+'/SHA256SUMS'].map(file=>[file,sha256File(file)]))};
fs.writeFileSync(out+'/identity.json',JSON.stringify(identity,null,2)+'\n');
const result=spawnSync('bash',[repo+'/ci/bootstrap/bootstrap.sh',...f.args,'--stage','stage0'],{env:{...process.env,STAGE0_CACHE_ROOT:out+'/cache'},encoding:'utf8',maxBuffer:16*1024*1024});
const text=(result.stdout||'')+(result.stderr||'');
fs.writeFileSync(out+'/entry.log',text);fs.writeFileSync(out+'/entry.rc',`${result.status===null?'NOT_EXITED':result.status}\n`);
const verifiers=[...text.matchAll(/^SDK-VERIFY-OK lock_sha256=([a-f0-9]{64}) role=host files=(\d+)$/gm)];
const sdk=f.out+'/work/sdk-stage0';
const observed={identity,entry_rc:result.status,executor_error:result.error?.message||null,tuple:[...text.matchAll(/^HOST-TUPLE ([^ ]+)/gm)].map(match=>match[1]),verifier_observations:verifiers.map(match=>({lock_sha256:match[1],files:Number(match[2]),sdk_verifier_rc:0})),sdk_build_ok:/^SDK-BUILD-OK role=host /m.test(text),fixture_only:true,compiler_bootstrap:'NOT_RUN(absent fixture source-layout program; zero production contract)',sdk_lock_sha256:fs.existsSync(sdk+'/SDK.lock.json')?sha256File(sdk+'/SDK.lock.json'):null};
fs.writeFileSync(out+'/result.json',JSON.stringify(observed,null,2)+'\n');
const target=observed.tuple.length===1&&observed.tuple[0]===f.native.tuple&&observed.sdk_build_ok&&verifiers.length===2&&observed.sdk_lock_sha256===verifiers[0][1]&&observed.sdk_lock_sha256===verifiers[1][1];
fs.writeFileSync(out+'/assertion.log',`ASSERT native-sdk-consumer tuple=${observed.tuple.join(',')} sdk_build_ok=${observed.sdk_build_ok} verifier_calls=${verifiers.length} verifier_rc=${verifiers.length?'0':'NOT_RUN'} entry_rc=${observed.entry_rc}\n${target?'PASS':'FAIL'} native-sdk-consumer (native object fixtures only)\n`);
console.log(fs.readFileSync(out+'/assertion.log','utf8'));
if(result.error||result.status===null)throw new Error('native entry executor failure');
if(!target)process.exitCode=1;
// The later failure must be exactly the declared absent fixture program, so
// an unexpected product failure cannot be relabeled as a completed SDK chain.
else if(result.status!==1||!text.includes('check-codegen-runtime-layout.mjs')||!text.includes('MODULE_NOT_FOUND'))throw new Error('unexpected post-verifier result; stop dependent arms');

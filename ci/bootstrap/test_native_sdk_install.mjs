#!/usr/bin/env zx
// Real SDK CLI, same native inputs and path for candidate/cut/restoration.
// This qualifies canonical LLVM installation only, not a compiler bootstrap.
import fs from 'node:fs';
import path from 'node:path';
import {fileURLToPath} from 'node:url';
import {spawnSync} from 'node:child_process';
import {prepareNativeTestInputs} from './native_test_inputs.mjs';
import {execute} from './host_tools.mjs';
import {sha256File} from './sdk_verify.mjs';
const repo=path.resolve(path.dirname(fileURLToPath(import.meta.url)),'../..');
const out=process.argv[2];
if(!out||!path.isAbsolute(out))throw new Error('absolute evidence directory required');
fs.mkdirSync(out,{recursive:true});
const head=execute('git',['-C',repo,'rev-parse','HEAD']).stdout.trim();
const source=out+'/source',carrier='ci/bootstrap/sdk_build.mjs';
const original=fs.readFileSync(repo+'/'+carrier,'utf8');
if(original.split('let target = canonical;').length!==2)throw new Error('unique canonical installation bearing point required');
const cut=original.replace('let target = canonical;',"let target = path.join(to,'third_party/llvm/bin',name);");
const f=prepareNativeTestInputs(out+'/inputs',repo),sdk=out+'/sdk';
const input=sha256File(f.hostLlvm),baseline=sha256File(f.base+'/third_party/llvm/lib/'+f.native.library);
if(input===baseline)throw new Error('native positive control must differ from baseline LLVM');
const fixture=Object.fromEntries([f.hostLlvm,f.colour,f.host,f.base+'/bin/cjc',f.base+'/third_party/llvm/lib/'+f.native.library].map(file=>[file,sha256File(file)]));
const noncarriers=['ci/bootstrap/sdk_build.sh','ci/bootstrap/sdk_verify.mjs','ci/bootstrap/native_libraries.mjs','ci/bootstrap/host_tools.mjs','ci/bootstrap/compiler_identity.py','ci/runtime_pin.env','ci/runtime-pin.mjs','build/lib/targets.mjs'];
execute('git',['-C',repo,'worktree','add','--detach',source,head]);
const results={};
try {
  for(const [arm,bytes] of Object.entries({candidate:original,cut,restored:original})) {
    const evidence=out+'/'+arm;fs.mkdirSync(evidence);
    fs.writeFileSync(source+'/'+carrier,bytes);
    fs.writeFileSync(evidence+'/sdk_build.mjs',bytes);
    if(arm==='cut')fs.writeFileSync(out+'/cut.diff',execute('git',['-C',source,'diff','--',carrier]).stdout);
    const result=spawnSync('bash',[source+'/ci/bootstrap/sdk_build.sh','--from',f.base,'--to',sdk,'--host','--llvm-so',f.hostLlvm,'--colour-runtime',f.colour,'--host-runtime',f.host,'--force'],{env:process.env,encoding:'utf8',maxBuffer:16*1024*1024});
    const text=(result.stdout||'')+(result.stderr||'');
    fs.writeFileSync(evidence+'/entry.log',text);fs.writeFileSync(evidence+'/entry.rc',String(result.status)+'\n');
    const installed=sdk+'/third_party/llvm/lib/'+f.native.library;
    const observed=fs.existsSync(installed)?sha256File(installed):null;
    const assertionRc=observed===input?0:1;
    fs.writeFileSync(evidence+'/assertion.log',`ASSERT canonical-llvm-install expected=${input} actual=${observed||'missing'} entry_rc=${result.status}\n${assertionRc?'FAIL':'PASS'} canonical-llvm-install\n`);
    const record={head,entry_rc:result.status,executor_error:result.error?.message||null,assertion_rc:assertionRc,assertions:1,target_assertion:true,input_sha256:input,base_llvm_sha256:baseline,installed_sha256:observed,carrier_sha256:sha256File(source+'/'+carrier),fixture:Object.fromEntries(Object.keys(fixture).map(file=>[file,sha256File(file)])),noncarriers:Object.fromEntries(noncarriers.map(file=>[file,sha256File(source+'/'+file)]))};
    results[arm]=record;fs.writeFileSync(out+'/results.json',JSON.stringify(results,null,2)+'\n');
    console.log(fs.readFileSync(evidence+'/assertion.log','utf8').trim());
    const expectedRc=arm==='cut'?1:0;
    if(result.error||result.status!==expectedRc||assertionRc!==expectedRc)throw new Error('unexpected '+arm+' SDK result; stop dependent arms');
    if(arm==='cut'&&!text.includes('SDK-BUILD-FAIL llvm-so 安装后 sha256 不一致'))throw new Error('canonical target guard was hidden by earlier failure');
    if(arm!=='cut'&&!/^SDK-VERIFY-OK /m.test(text))throw new Error('green SDK verifier not observed');
  }
  if(results.candidate.carrier_sha256!==results.restored.carrier_sha256||results.cut.carrier_sha256===results.candidate.carrier_sha256)throw new Error('carrier identity mismatch');
  for(const record of Object.values(results))if(JSON.stringify(record.fixture)!==JSON.stringify(fixture)||JSON.stringify(record.noncarriers)!==JSON.stringify(results.candidate.noncarriers))throw new Error('input/noncarrier identity mismatch');
} finally {
  fs.writeFileSync(source+'/'+carrier,original);
  execute('git',['-C',repo,'worktree','remove',source]);
}

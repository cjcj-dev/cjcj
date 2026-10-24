#!/usr/bin/env zx
// Finite real ELF/SO/ar capture and source gate. The release archive verifier is
// a controlled boundary; these native C products are not a Cangjie SDK.
import fs from 'node:fs/promises';
import path from 'node:path';
import assert from 'node:assert/strict';
import {spawnSync} from 'node:child_process';
import {fileDigest} from './bootstrap/sdk-flow.mjs';
const base=process.env.RELEASE_EVIDENCE_TEST_ROOT,host=process.env.NATIVE_HOST_TEST_INPUT_ROOT;
if(!base||!host||!process.env.CJCJ_TEST_RUNTIME_GENERATOR)throw new Error('real host, fixed runtime generator and private evidence root required');
await fs.mkdir(base,{recursive:true});const work=await fs.mkdtemp(path.join(base,'g2-native-'));
const records=[];
async function run(label,argv,env=process.env){
 const r=spawnSync(argv[0],argv.slice(1),{encoding:'utf8',env,maxBuffer:16*1024*1024});
 records.push({label,argv,rc:r.status,signal:r.signal,stdout:r.stdout,stderr:r.stderr});
 await fs.writeFile(work+'/commands.json',JSON.stringify(records,null,2));return r;
}
const write=async(file,bytes)=>{await fs.mkdir(path.dirname(file),{recursive:true});await fs.writeFile(file,bytes);};
const native=await run('native-runtime-producer',[process.execPath,new URL('../build/test/runtime-archive-source.integration.mjs',import.meta.url).pathname],
 {...process.env,RELEASE_EVIDENCE_TEST_ROOT:work+'/runtime'});
assert.equal(native.status,0,native.stderr);
const input=JSON.parse(await fs.readFile(work+'/runtime/archive-case.json'));
const sdk=input.install,checkout=work+'/checkout',llvm='b'.repeat(40),tuple='linux_x86_64_cjnative';
await fs.mkdir(checkout);
for(const file of ['.gitignore','ci/runtime_pin.env','ci/llvm_pin.env','ci/source_pin.env','ci/cjpm_pin.env',
 'ci/release-evidence/g2-identity.schema.json','ops/design/DRYRUN_EXECUTION_POLICY.md','.github/workflows/release.yml'])
 await write(checkout+'/'+file,await fs.readFile(new URL('../'+file,import.meta.url)));
let pins=await fs.readFile(checkout+'/ci/runtime_pin.env','utf8');
pins=pins.replace(/^RUNTIME_REF=.*$/m,'RUNTIME_REF='+'a'.repeat(40)).replace(/^LOADERLIFE_MIN_REF=.*$/m,'LOADERLIFE_MIN_REF='+input.commit);
await write(checkout+'/ci/runtime_pin.env',pins);
await write(checkout+'/ci/llvm_pin.env',(await fs.readFile(checkout+'/ci/llvm_pin.env','utf8')).replace(/^LLVM_SHA=.*$/m,'LLVM_SHA='+llvm));
await write(checkout+'/scripts/archive_release_evidence.mjs',"if(process.argv[2]!=='verify')process.exit(9);console.log('CONTROLLED_ARCHIVE_BOUNDARY');\n");
for(const args of [['init','-q'],['remote','add','origin','https://github.com/cjcj-dev/cjcj.git'],['add','.'],
 ['-c','user.name=Zxilly','-c','user.email=zxilly@outlook.com','commit','-qm','Finite G2 fixed source boundary']])
 assert.equal((await run('git', ['git','-C',checkout,...args])).status,0);
const head=(await run('head',['git','-C',checkout,'rev-parse','HEAD'])).stdout.trim();
const env={...process.env,GITHUB_WORKSPACE:checkout,GITHUB_ENV:work+'/github.env',GITHUB_PATH:work+'/github.path',
 GITHUB_SHA:head,RUNNER_TEMP:work,CJCJ_SRCBUILD_TARGET:'linux-x64',CJCJ_NATIVE_INPUT_ROOT:host,
 CJCJ_NATIVE_RUNTIME_REF:input.commit,CJCJ_NATIVE_LLVM_REF:llvm,CJCJ_NATIVE_HOST_VERSION:'1.3.0-alpha.20260925001050'};
for(const key of ['RUNTIME_REF','RUNTIME_SRC_URL','CJCJ_RUNTIME_REF_OVERRIDE','CJCJ_BOOTSTRAP_RUNTIME_PIN'])delete env[key];
const prepared=await run('formal-host-freeze',[process.execPath,new URL('./bootstrap/prepare-native-host.mjs',import.meta.url).pathname],env);
assert.equal(prepared.status,0,prepared.stderr);
const exported=Object.fromEntries((await fs.readFile(env.GITHUB_ENV,'utf8')).trim().split('\n').map(line=>{const at=line.indexOf('=');return[line.slice(0,at),line.slice(at+1)];}));
const campaign=exported.G2_CAMPAIGN_DIR,identityFile=exported.G2_IDENTITY;
const compiler='libexec/compiler/cjcj-stage1';
for(const [name,rel,stamp]of [['compiler',compiler,'CJCJ-COMMIT:'+head],
 ['llc','.native-tools/third_party/llvm/bin/llc','CJLLVM-COMMIT:'+llvm],
 ['opt','.native-tools/third_party/llvm/bin/opt','CJLLVM-COMMIT:'+llvm],
 ['std','lib/'+tuple+'/libcangjie-std-core.a','CJSTD-COMMIT:'+'d'.repeat(40)]]){
 const code=work+'/'+name+'.c';await write(code,'const char identity[]="'+stamp+'"; int main(void){return identity[0]==0;}\n');
 await fs.mkdir(path.dirname(sdk+'/'+rel),{recursive:true});
 const args=name==='std'?['cc','-c',code,'-o',work+'/std.o']:['cc',code,'-o',sdk+'/'+rel];
 const built=await run('native-'+name,args);assert.equal(built.status,0,built.stderr);
 if(name==='std')assert.equal((await run('archive-std',['ar','rcs',sdk+'/'+rel,work+'/std.o'])).status,0);
}
await fs.mkdir(sdk+'/bin',{recursive:true});await fs.copyFile('/usr/bin/true',sdk+'/bin/cjcj-stage1');
for(const alias of ['cjc','cjc-frontend'])await fs.symlink('cjcj-stage1',sdk+'/bin/'+alias);
const recipe=rel=>['cjcj-sdk-entry-v1','1',rel,'linux','native-target:x64','runtime/lib/'+tuple,''].join('\n');
await write(sdk+'/bin/cjcj-stage1.entry',recipe(compiler));
for(const name of ['llc','opt']){
 await fs.mkdir(sdk+'/third_party/llvm/bin',{recursive:true});await fs.copyFile('/usr/bin/true',sdk+'/third_party/llvm/bin/'+name);
 await write(sdk+'/third_party/llvm/bin/'+name+'.entry',recipe('.native-tools/third_party/llvm/bin/'+name));
}
await write(sdk+'/STAGE-INPUTS.json',JSON.stringify({platform:'linux_x86_64',compilerFile:compiler,compilerCommit:head,
 runtimeCommit:input.commit,compilerSha256:await fileDigest(sdk+'/'+compiler),compilerEntrySha256:await fileDigest(sdk+'/bin/cjcj-stage1')}));
const capture=[process.execPath,new URL('./capture-g2-identity.mjs',import.meta.url).pathname,'--identity',identityFile,'--sdk',sdk];
const captured=await run('formal-installed-capture',capture);assert.equal(captured.status,0,captured.stderr);
const identity=JSON.parse(await fs.readFile(identityFile));
assert.equal(identity.artifacts.cjcj.artifact_path,sdk+'/'+compiler);
assert.notEqual(identity.artifacts.cjcj.sha256,await fileDigest(sdk+'/bin/cjc'));
assert.equal(identity.artifacts.runtime_dynamic.source_commit,input.commit);
assert.match(identity.artifacts.runtime_dynamic.provenance_stamp,/^CJRT-COMMIT:src-/);
const archive=campaign+'/archive';await fs.mkdir(archive);await write(archive+'/run.json',JSON.stringify({head_sha:head}));
const gate=(name,label)=>run(label,[process.execPath,new URL('./release-gates.mjs',import.meta.url).pathname,name,
 '--repo',checkout,'--runtime-repo',input.repository,'--evidence',archive,'--freeze',campaign+'/FREEZE.json','--json']);
const approval=await gate('G1','approval-control');assert.equal(approval.status,1,approval.stdout);assert.match(JSON.parse(approval.stdout).value,/failures=approval$/);
const normal=await gate('G2','normal');assert.equal(normal.status,0,normal.stdout+normal.stderr);console.log('G2_NATIVE_CAPTURE_SOURCE_ASSERT_REACHED');
const recordFile=campaign+'/RUNTIME-INPUTS.json',original=await fs.readFile(recordFile);
const wrong=JSON.parse(original);wrong.artifacts[0].sha256='f'.repeat(64);
await write(recordFile,JSON.stringify(wrong));identity.inputs.runtime.sha256=await fileDigest(recordFile);await write(identityFile,JSON.stringify(identity));
const rejected=await gate('G2','wrong-paired-record');
assert.equal((await gate('G1','independent-approval-control')).stdout,approval.stdout);
console.log('G2_ORIGINAL_PAIR_REJECTION_ASSERT_REACHED '+JSON.stringify({rc:rejected.status,gate:rejected.stdout,approval:'unchanged'}));
assert.equal(rejected.status,1,rejected.stdout);assert.match(JSON.parse(rejected.stdout).value,/captured runtime differs/);
await write(recordFile,original);identity.inputs.runtime.sha256=await fileDigest(recordFile);await write(identityFile,JSON.stringify(identity));
assert.equal((await gate('G2','restored')).status,0);
const freeze=JSON.parse(await fs.readFile(campaign+'/FREEZE.json'));
freeze.pins.RUNTIME_REF='a'.repeat(40);await write(campaign+'/FREEZE.json',JSON.stringify(freeze));
const wrongPin=await gate('G2','wrong-selected-freeze');assert.equal(wrongPin.status,1);assert.match(JSON.parse(wrongPin.stdout).value,/FREEZE_SELECTED_PIN_VALUES/);
freeze.pins.RUNTIME_REF=input.commit;await write(campaign+'/FREEZE.json',JSON.stringify(freeze));
assert.equal((await gate('G2','freeze-restored')).status,0);
console.log('G2_NATIVE_INPUTS_FINITE_PASS '+work);

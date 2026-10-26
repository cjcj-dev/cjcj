import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs/promises';
import path from 'node:path';
import {spawnSync} from 'node:child_process';
import {hostPlatform} from '../host-toolchain-pin.mjs';
import {load} from '../vendor/js-yaml/js-yaml.mjs';
import {nativeSourceSelection,NATIVE_REPOSITORIES} from './native-source-selection.mjs';
import {FIXED_INPUTS} from './sdk-targets.mjs';
const root=process.env.RELEASE_EVIDENCE_TEST_ROOT;if(!root)throw new Error('RELEASE_EVIDENCE_TEST_ROOT required');
test('source host producer exports one canonical root through first and repeated preparation',async()=>{
 const {buildConfig}=await import('../../build/lib/config.mjs');
 const {baseEnv}=await import('../../build/srcbuild/stages/common.mjs');
 await fs.mkdir(root,{recursive:true});const work=await fs.mkdtemp(path.join(root,'canonical-host-'));
 const bootstrap=work+'/bootstrap',workspace=work+'/workspace',selected=workspace+'/source-host-sdk',consumer=work+'/consumer';
 await fs.mkdir(consumer+'/runtime/lib/linux_x86_64_cjnative',{recursive:true});
 await fs.mkdir(bootstrap+'/runtime/lib/linux_x86_64_cjnative',{recursive:true});
 await fs.mkdir(bootstrap+'/bin',{recursive:true});await fs.writeFile(bootstrap+'/bin/cjc','old fixture compiler');
 await fs.mkdir(workspace+'/cangjie_compiler/output/bin',{recursive:true});
 await fs.writeFile(workspace+'/cangjie_compiler/output/bin/cjc','new fixture compiler');
 await fs.writeFile(work+'/plain.c','int plain_host_fixture(void) { return 0; }\n');
 const records=[];const run=(label,argv,env)=>{
  const r=spawnSync(argv[0],argv.slice(1),{env,encoding:'utf8'});
  records.push({label,argv,rc:r.status,signal:r.signal,stdout:r.stdout,stderr:r.stderr,error:r.error?.message});
  return r;
 };
 try {
  const cc=run('plain-host-library',[process.env.CC||'cc','-shared','-fPIC',work+'/plain.c','-o',bootstrap+'/runtime/lib/linux_x86_64_cjnative/libcangjie-runtime.so'],process.env);
  assert.equal(cc.status,0,cc.stderr);
  for(const phase of ['first','repeat']){
   const output=work+'/'+phase+'.env',env={...process.env,CANGJIE_WORKSPACE:workspace,GITHUB_ENV:output,
    CJCJ_SRCBUILD_TARGET:'linux-x64',CJCJ_SRCBUILD_BOOTSTRAP_SDK:bootstrap,
    CJCJ_OFFICIAL_SDK_ROOT:work+'/stale-canonical',CJCJ_SRCBUILD_HOST_SDK:work+'/removed-alias'};
   const r=run(phase,[process.env.ZX||'zx',new URL('../srcbuild/steps/prepare-source-host-sdk.mjs',import.meta.url).pathname],env);
   assert.equal(r.status,0,r.stderr);
   const exported=Object.fromEntries((await fs.readFile(output,'utf8')).trim().split('\n').map(line=>{
    const at=line.indexOf('=');return[line.slice(0,at),line.slice(at+1)];}));
   assert.equal(exported.CJCJ_OFFICIAL_SDK_ROOT,selected,'HOST_CANONICAL_EXPORT');
   assert.equal(exported.CJCJ_SRCBUILD_HOST_SDK,undefined);
   const config=buildConfig({workspace,consumerSdk:consumer,officialSdkRoot:exported.CJCJ_OFFICIAL_SDK_ROOT});
   const child=baseEnv(config,{...env,...exported});
   assert.equal(child.CJCJ_OFFICIAL_SDK_ROOT,selected);
   assert.equal(child.LD_LIBRARY_PATH.split(path.delimiter)[0],selected+'/runtime/lib/linux_x86_64_cjnative');
   assert.equal(await fs.readFile(selected+'/bin/cjc','utf8'),'new fixture compiler');
   assert.equal(await fs.readFile(bootstrap+'/bin/cjc','utf8'),'old fixture compiler');
  }
 } finally {await fs.writeFile(work+'/commands.json',JSON.stringify(records,null,2));}
});
test('explicit native host is selected before freeze and old host steps retain their default branch',async()=>{
 const workflow=load(await fs.readFile(new URL('../../.github/workflows/srcbuild-target.yml',import.meta.url),'utf8'));
 const steps=workflow.jobs['source-stage0'].steps;
 const at=name=>steps.findIndex(step=>step.name===name);
 const receive=at('Receive selected native inputs before choosing the host'),select=at('Select actual native host and freeze the same inputs');
 assert.ok(receive>=0&&select>receive&&select<at('Bootstrap stage0 compiler'));
 assert.equal(steps[select].run,'node ci/bootstrap/prepare-native-host.mjs');
 assert.equal(steps[select].if,"inputs.native_runtime_artifact != ''");
 for(const name of ['Provision uncoloured host SDK','Freeze G2 identity inputs','Copy host inputs for source handoffs',
   'Resolve bootstrap inputs on this runner','Verify complete official H and repaired host LLVM identities','Record host repair and nightly control symbols'])
   assert.match(steps[at(name)].if,/inputs.native_runtime_artifact == ''/);
 assert.equal(workflow.jobs['fixed-llvm'].with.llvm_ref,'${{ inputs.native_llvm_ref }}');
 assert.equal(workflow.jobs['fixed-llvm'].with.runtime_ref,'${{ inputs.native_runtime_ref }}');
 assert.equal(steps[select].env?.CJCJ_NATIVE_SOURCE_SELECTION,undefined);
 const configure=steps.find(step=>step.name==='Configure native bootstrap from actual repositories and target installations');
 assert.equal(configure.env?.CJCJ_NATIVE_SOURCE_SELECTION,undefined);
 for(const name of ['srcbuild.yml','release.yml','release-matrix.yml','arm-soak.yml']){
  const outer=load(await fs.readFile(new URL('../../.github/workflows/'+name,import.meta.url),'utf8'));
  for(const job of Object.values(outer.jobs))if(job.with?.native_inputs_artifact)
   assert.equal(job.with.native_source_selection,undefined,name);
 }
});
test('explicit native source selection retains default pins and does not relabel the N/R/H pair',()=>{
 const defaults=nativeSourceSelection({},null);
 assert.equal(defaults.explicitAst,false);assert.deepEqual(defaults.selection.ast,{repository:NATIVE_REPOSITORIES.ast,commit:FIXED_INPUTS.compiler});
 const pair={llvm:'a'.repeat(40),runtime:'b'.repeat(40)},ast={repository:'file:///actual/transferred/source.git',commit:'f07c55738c12c154160c313c630a42a73a51025d'};
 const selected=nativeSourceSelection({},pair,{ast});
 assert.deepEqual(selected.selection.ast,ast);assert.equal(selected.explicitAst,true);
 assert.equal(selected.selection.llvm.commit,pair.llvm);assert.equal(selected.selection.runtime.commit,pair.runtime);
 for(const invalid of [{ast:null},{ast:{commit:ast.commit}},{llvm:ast},{unrecognized:ast}])
  assert.throws(()=>nativeSourceSelection({},pair,invalid),/GHA_NATIVE_SOURCE_SELECTION/);
});
test('formal native configure rejects invalid source choices before source transport or SDK preparation',async()=>{
 await fs.mkdir(root,{recursive:true});const work=await fs.mkdtemp(path.join(root,'native-source-rejection-'));
 await fs.mkdir(work+'/inputs');await fs.writeFile(work+'/inputs/locations.json',JSON.stringify({platform:hostPlatform()}));
 const env={...process.env,CANGJIE_WORKSPACE:work+'/workspace',GITHUB_WORKSPACE:work,
  CJCJ_NATIVE_INPUT_ROOT:work+'/inputs',CJCJ_BOOTSTRAP_BASE:work+'/unavailable-host'};
 for(const key of ['CJCJ_NATIVE_LLVM_REF','CJCJ_NATIVE_RUNTIME_REF','CJCJ_NATIVE_RUNTIME_INSTALL'])delete env[key];
 const records=[];
 for(const choice of [{compiler:null},{compiler:{url:'file:///absent',tag:''}},{unknown:{}}]){
  await fs.mkdir(env.CANGJIE_WORKSPACE,{recursive:true});await fs.writeFile(env.CANGJIE_WORKSPACE+'/.source-selection.json',JSON.stringify(choice));
  const argv=[new URL('./configure-gha-inputs.mjs',import.meta.url).pathname];
  const r=spawnSync(process.execPath,argv,{env,encoding:'utf8'});
  records.push({argv,choice,rc:r.status,signal:r.signal,stdout:r.stdout,stderr:r.stderr});
  await fs.writeFile(work+'/commands.json',JSON.stringify(records,null,2));
  assert.equal(r.status,1);assert.match(r.stderr,/invalid .*source-selection/);
  assert.equal(await fs.stat(work+'/workspace/native-sources').then(()=>true,()=>false),false);
 }
});
test('formal native host preparation rejects missing and conflicting host inputs before freeze',async()=>{
 await fs.mkdir(root,{recursive:true});const work=await fs.mkdtemp(path.join(root,'native-host-rejection-'));
 const inputs=path.join(work,'inputs');await fs.mkdir(inputs);
 const version='1.3.0-alpha.20260925001050';
 const env={...process.env,GITHUB_WORKSPACE:work,GITHUB_ENV:work+'/github.env',RUNNER_TEMP:work,
  CJCJ_SRCBUILD_TARGET:'linux-x64',CJCJ_NATIVE_INPUT_ROOT:inputs,CJCJ_NATIVE_RUNTIME_REF:'79b34798d0f4696f9fe5a3708981539466ecd35b',
  CJCJ_NATIVE_LLVM_REF:'db51a4c7ebb6903e9f997d3b35d52f3577810385',CJCJ_NATIVE_HOST_VERSION:version};
 const entry=new URL('./prepare-native-host.mjs',import.meta.url).pathname;
 for(const [label,host]of [['missing',{}],['version',{install:'host',archive:'host.tar.gz',version:'wrong'}],
  ['escape',{install:'../host',archive:'host.tar.gz',version}]]){
  await fs.writeFile(inputs+'/locations.json',JSON.stringify({platform:hostPlatform(),host}));
  const r=spawnSync(process.execPath,[entry],{env,encoding:'utf8'});
  await fs.writeFile(work+'/'+label+'.json',JSON.stringify({rc:r.status,signal:r.signal,stdout:r.stdout,stderr:r.stderr}));
  assert.equal(r.status,1);assert.match(r.stderr,label==='escape'?/NATIVE_HOST_MEMBER_PATH/:/NATIVE_HOST_ORIGINAL_INPUT_REQUIRED/);
  assert.equal(await fs.stat(work+'/.srcbuild/g2-campaigns').then(()=>true,()=>false),false);
 }
});

test('formal host entry freezes the actual complete H and selected target pair, then the loader consumes that R',
 {skip:!process.env.NATIVE_HOST_TEST_INPUT_ROOT,timeout:240000},async()=>{
 await fs.mkdir(root,{recursive:true});const work=await fs.mkdtemp(path.join(root,'native-host-complete-'));
 const checkout=work+'/checkout';await fs.mkdir(checkout);
 const run=(program,args,env=process.env)=>spawnSync(program,args,{env,encoding:'utf8',maxBuffer:2*1024*1024});
 const git=(...args)=>{const r=run('git',['-C',checkout,...args]);assert.equal(r.status,0,r.stderr);return r.stdout.trim();};
 git('init','-q');git('remote','add','origin','https://github.com/cjcj-dev/cjcj.git');
 const source=new URL('../../',import.meta.url);
 for(const file of ['.gitignore','ci/runtime_pin.env','ci/llvm_pin.env','ci/source_pin.env','ci/cjpm_pin.env',
  'ops/design/DRYRUN_EXECUTION_POLICY.md','.github/workflows/release.yml']){
  await fs.mkdir(path.dirname(checkout+'/'+file),{recursive:true});await fs.copyFile(new URL(file,source),checkout+'/'+file);
 }
 git('add','.');git('-c','user.name=Zxilly','-c','user.email=zxilly@outlook.com','commit','-qm','Fixed host entry consumer fixture');
 const head=git('rev-parse','HEAD'),version='1.3.0-alpha.20260925001050';
 const selectedR='79b34798d0f4696f9fe5a3708981539466ecd35b',selectedN='db51a4c7ebb6903e9f997d3b35d52f3577810385';
 const env={...process.env,GITHUB_WORKSPACE:checkout,GITHUB_ENV:work+'/github.env',GITHUB_PATH:work+'/github.path',
  GITHUB_SHA:head,RUNNER_TEMP:work,CJCJ_SRCBUILD_TARGET:'linux-x64',
  CJCJ_NATIVE_INPUT_ROOT:process.env.NATIVE_HOST_TEST_INPUT_ROOT,
  CJCJ_NATIVE_RUNTIME_ARTIFACT:'frozen-runtime-component',CJCJ_NATIVE_RUNTIME_REF:selectedR,
  CJCJ_NATIVE_LLVM_REF:selectedN,CJCJ_NATIVE_HOST_VERSION:version};
 for(const key of ['RUNTIME_REF','RUNTIME_SRC_URL','CJCJ_RUNTIME_REF_OVERRIDE','CJCJ_BOOTSTRAP_RUNTIME_PIN'])delete env[key];
 const r=run(process.execPath,[new URL('./prepare-native-host.mjs',import.meta.url).pathname],env);
 await fs.writeFile(work+'/prepare-command.json',JSON.stringify({rc:r.status,signal:r.signal,stdout:r.stdout,stderr:r.stderr}));
 assert.equal(r.status,0,r.stderr);assert.match(r.stdout,/NATIVE_HOST_SELECTED/);
 const exported=Object.fromEntries((await fs.readFile(env.GITHUB_ENV,'utf8')).trim().split('\n').map(line=>{
  const i=line.indexOf('=');return[line.slice(0,i),line.slice(i+1)];}));
 const freeze=JSON.parse(await fs.readFile(exported.G2_CAMPAIGN_DIR+'/FREEZE.json'));
 assert.equal(freeze.pins.RUNTIME_REF,selectedR);assert.equal(freeze.pins.LLVM_SHA,selectedN);
 assert.equal(freeze.selected_host,exported.CJCJ_BOOTSTRAP_BASE);
 assert.equal(freeze.host_sdk.version,version);
 assert.equal(freeze.BASE_SDK_SHA256,'fde68a5713968f5f875e013355d73aab8bd95bb1fbfd1f1b6a29b1adcf48943b');
 assert.equal(freeze.host_sdk.archive.path,exported.CJCJ_BOOTSTRAP_BASE_ARCHIVE);
 assert.deepEqual(freeze.host_llvm.execution.loaded,[freeze.host_llvm.path]);assert.equal(freeze.host_llvm.execution.rc,0);
 assert.equal(freeze.approval.user_instruction_or_record_id,'');
 assert.equal(JSON.parse(await fs.readFile(exported.G2_IDENTITY)).status,'PENDING');
 const downstream=run(process.execPath,[new URL('../load_runtime_pin.mjs',import.meta.url).pathname],{...env,...exported});
 await fs.writeFile(work+'/loader-command.json',JSON.stringify({rc:downstream.status,signal:downstream.signal,stdout:downstream.stdout,stderr:downstream.stderr}));
 assert.equal(downstream.status,0,downstream.stderr);
 assert.match(await fs.readFile(env.GITHUB_ENV,'utf8'),new RegExp('^CJCJ_NATIVE_RUNTIME_REF='+selectedR+'$','m'));
 assert.doesNotMatch(await fs.readFile(env.GITHUB_ENV,'utf8'),/CJCJ_ALLOW_RUNTIME_OVERRIDE=true/);
});

// Real received inputs only: no executable substitute and no payload inventory.
test('selected host rejects a different real compiler version before consumption',
 {skip:!process.env.NATIVE_HOST_TEST_INPUT_ROOT||!process.env.CJCJ_OFFICIAL_SDK_ROOT},async()=>{
 const {verifyOfficialSdkIdentity}=await import('../../build/lib/official-sdk-identity.mjs');
 const {targetForHost}=await import('../../build/lib/targets.mjs');
 const inputs=process.env.NATIVE_HOST_TEST_INPUT_ROOT;
 const locations=JSON.parse(await fs.readFile(path.join(inputs,'locations.json'),'utf8'));
 await assert.rejects(verifyOfficialSdkIdentity({root:process.env.CJCJ_OFFICIAL_SDK_ROOT,
  archive:path.join(inputs,locations.host.archive),version:'nightly-'+locations.host.version,
  platform:targetForHost().spec.key,selectedHost:true}),/compiler mismatch: requested=.* actual=/);
 console.log('ACTUAL_HOST_VERSION_REJECTION_REACHED');
});

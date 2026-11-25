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
   const r=run(phase,[process.env.ZX||'zx',new URL('../../build/sdk/producers/srcbuild/steps/prepare-source-host-sdk.mjs',import.meta.url).pathname],env);
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
 const workflow=load(await fs.readFile(new URL('../../.github/workflows/sdk-build-target.yml',import.meta.url),'utf8'));
 const steps=workflow.jobs['source-stage0'].steps;
 const at=name=>steps.findIndex(step=>step.name===name);
 const receive=at('Receive selected native inputs before choosing the host'),select=at('Select actual native host and freeze the same inputs');
 assert.ok(receive>=0&&select>receive&&select<at('Bootstrap stage0 compiler'));
 assert.equal(steps[select].run,'node ci/bootstrap/prepare-native-host.mjs');
 assert.equal(steps[select].if,"inputs.native_runtime_artifact != ''");
 for(const name of ['Provision uncoloured host SDK','Freeze G2 identity inputs','Copy host inputs for source handoffs',
   'Resolve bootstrap inputs on this runner','Verify complete official H and repaired host LLVM identities','Record host repair and nightly control symbols'])
   assert.match(steps[at(name)].if,/inputs.native_runtime_artifact == ''/);
 const llvmJob=workflow.jobs['fixed-llvm'];
 const llvmPin=llvmJob.steps.find(step=>step.run==='node ci/native-llvm-inputs.mjs');
 const inherited={...workflow.env,...llvmJob.env,...llvmPin.env};
 assert.equal(inherited.CJCJ_NATIVE_LLVM_REF,'${{ inputs.native_llvm_ref }}');
 assert.equal(inherited.CJCJ_NATIVE_RUNTIME_REF,'${{ inputs.native_runtime_ref }}');
 assert.equal(steps[select].env?.CJCJ_NATIVE_SOURCE_SELECTION,undefined);
 const configure=steps.find(step=>step.name==='Configure native bootstrap from actual repositories and target installations');
 assert.equal(configure.env?.CJCJ_NATIVE_SOURCE_SELECTION,undefined);
 for(const name of ['sdk-build.yml','release.yml']){
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
test('H1 selection changes the source checkout without changing the native pair or AST',()=>{
 const chosen='5a47f0bb15a072b38ff040df961875bb8f741038', env={CJCJ_NATIVE_H1_REF:chosen};
 const base=nativeSourceSelection({}).selection;
 const {selection}=nativeSourceSelection(env);
 assert.deepEqual(selection,{...base,h1:{...base.h1,commit:chosen}});
 assert.throws(()=>nativeSourceSelection({CJCJ_NATIVE_H1_REF:'HEAD'}),/NATIVE_H1_SOURCE_REF/);
 assert.throws(()=>nativeSourceSelection(env,undefined,{h1:base.h1}),/NATIVE_H1_SOURCE_CONFLICT/);
});
test('POSIX GHA H1 uses the verified job checkout unless a different ref was requested', {skip:process.platform==='win32'}, async t=>{
 const {selectGhaH1}=await import('./configure-gha-inputs.mjs');
 const {pathToFileURL}=await import('node:url');
 await fs.mkdir(root,{recursive:true});
 const work=await fs.mkdtemp(path.join(await fs.realpath(root),'gha-h1-'));
 t.after(()=>fs.rm(work,{recursive:true,force:true}));
 const checkout=path.join(work,'checkout'),workspace=path.join(work,'workspace'),inputs=path.join(work,'inputs');
 const git=(cwd,...args)=>{
   const r=spawnSync('git',['-C',cwd,...args],{encoding:'utf8'});
   assert.equal(r.status,0,r.stderr);return r.stdout.trim();
 };
 await fs.mkdir(checkout);git(checkout,'init','-q');
 const repository='https://fixture.invalid/job-fork.git';
 git(checkout,'remote','add','origin',repository);
 const commit=label=>{
   git(checkout,'-c','user.name=Fixture','-c','user.email=fixture@example.invalid','commit','--allow-empty','-qm',label);
   return git(checkout,'rev-parse','HEAD');
 };
 const older=commit('bisect'),head=commit('job');
 const env={GITHUB_SHA:head};
 const select=(overrides={},locations={})=>{
   const job={...env,...overrides};
   return selectGhaH1(checkout,locations,job,false,nativeSourceSelection(job).selection.h1);
 };
 for(const overrides of [{},{CJCJ_NATIVE_H1_REF:head}]){
   const h1=await select(overrides);
   assert.equal(h1.selection.commit,head,'POSIX H1 must equal GITHUB_SHA');
   assert.equal(h1.selection.repository,repository);
   assert.equal(h1.checkout,checkout);
 }
 await assert.rejects(select({GITHUB_SHA:older}),/GHA_BOOTSTRAP_JOB_CHECKOUT/);
 await assert.rejects(select({GITHUB_SHA:undefined}),/GHA_BOOTSTRAP_JOB_CHECKOUT/);
 await assert.rejects(select({},{tools:{privateRoot:'artifact'}}),/NATIVE_TOOLS_PRIVATE_ROOT_RETIRED/);

 // Exercise configure's checkout loop, stopping at bounds, the source after H1.
 const {selection}=nativeSourceSelection({},{llvm:head,runtime:head});
 const sources=path.join(workspace,'native-sources');
 await fs.mkdir(sources,{recursive:true});
 for(const [name,url] of Object.entries({llvm:selection.llvm.repository,runtime:selection.runtime.repository,ast:repository,bounds:repository})){
   git(sources,'clone','-q',checkout,name);
   git(path.join(sources,name),'remote','set-url','origin',url);
 }
 await fs.writeFile(path.join(workspace,'.source-selection.json'),JSON.stringify({compiler:{url:repository,tag:head}}));
 await fs.mkdir(inputs);const platform=hostPlatform(),file='locations.json';
 await fs.writeFile(path.join(inputs,file),JSON.stringify({platform,hleDependencies:'hle.json'}));
 const member=name=>({path:name,source:'fixture',version:'1'});
 await fs.mkdir(path.join(inputs,'modules'));
 await fs.writeFile(path.join(inputs,'hle.json'),JSON.stringify({platform,node:member(file),modules:member('modules'),cjbind:member(file)}));
 const job={...process.env,...env,CANGJIE_WORKSPACE:workspace,GITHUB_WORKSPACE:checkout,CJCJ_NATIVE_INPUT_ROOT:inputs,
   CJCJ_OFFICIAL_SDK_ROOT:work,CJCJ_NATIVE_LLVM_REF:head,CJCJ_NATIVE_RUNTIME_REF:head,CJCJ_NATIVE_PAIR_SELECTION:'explicit',
   GIT_ALLOW_PROTOCOL:'file',GIT_CONFIG_COUNT:'1',GIT_CONFIG_KEY_0:'url.'+pathToFileURL(checkout).href+'.insteadOf',
   GIT_CONFIG_VALUE_0:NATIVE_REPOSITORIES.h1,CJCJ_SRCBUILD_SOURCE_MIRRORS:'',CJCJ_SRCBUILD_REQUIRE_MIRRORS:'0'};
 for(const key of ['CJCJ_NATIVE_H1_REF','CJCJ_NATIVE_RUNTIME_INSTALL','CJCJ_PINNED_RUNTIME_GIT_DIR','GITHUB_ENV'])delete job[key];
 const configure=overrides=>{
   const r=spawnSync(process.execPath,[new URL('./configure-gha-inputs.mjs',import.meta.url).pathname],{env:{...job,...overrides},encoding:'utf8'});
   assert.equal(r.status,1);assert.match(r.stderr,/GHA_NATIVE_SOURCE_REUSE_CHANGED bounds/);
 };
 const h1=path.join(sources,'h1');
 configure({});
 await assert.rejects(fs.stat(h1),{code:'ENOENT'});
 configure({CJCJ_NATIVE_H1_REF:older});
 assert.equal(git(h1,'rev-parse','HEAD'),older);
 assert.equal(git(checkout,'rev-parse','HEAD'),head);
});
test('native configure resolves a pinned runtime install before checking the artifact platform',async()=>{
 const {configureGhaInputs}=await import('./configure-gha-inputs.mjs');
 await fs.mkdir(root,{recursive:true});const work=await fs.mkdtemp(path.join(root,'native-configure-pair-'));
 // The next check after repository selection stops this fixture before any source transport.
 await fs.writeFile(path.join(work,'locations.json'),JSON.stringify({platform:'wrong-platform'}));
 const env={CANGJIE_WORKSPACE:work,GITHUB_WORKSPACE:work,CJCJ_NATIVE_INPUT_ROOT:work,
  CJCJ_OFFICIAL_SDK_ROOT:path.join(work,'host'),CJCJ_NATIVE_RUNTIME_INSTALL:path.join(work,'runtime')};
 const artifact={...env,CJCJ_NATIVE_RUNTIME_ARTIFACT:'native-runtime-install'};
 await assert.rejects(configureGhaInputs(env),{message:'NATIVE_RUNTIME_EXPLICIT_PAIR_REQUIRED'});
 for(const refs of [{CJCJ_NATIVE_RUNTIME_REF:'a'.repeat(40)},
  {CJCJ_NATIVE_LLVM_REF:'invalid',CJCJ_NATIVE_RUNTIME_REF:'a'.repeat(40)}])
  await assert.rejects(configureGhaInputs({...artifact,...refs}),{message:'NATIVE_RUNTIME_EXPLICIT_PAIR_REQUIRED'});
 await assert.rejects(configureGhaInputs({...artifact,CJCJ_NATIVE_LLVM_REF:'a'.repeat(40),
  CJCJ_NATIVE_RUNTIME_REF:'b'.repeat(40)}),{message:'NATIVE_RUNTIME_EXPLICIT_HOST_REQUIRED'});
 await assert.rejects(configureGhaInputs(artifact),{message:'GHA_NATIVE_ARTIFACT_PLATFORM'});
});
test('formal native configure rejects invalid source choices before source transport or SDK preparation',async()=>{
 await fs.mkdir(root,{recursive:true});const work=await fs.mkdtemp(path.join(root,'native-source-rejection-'));
 await fs.mkdir(work+'/inputs');await fs.writeFile(work+'/inputs/locations.json',JSON.stringify({platform:hostPlatform()}));
 const env={...process.env,CANGJIE_WORKSPACE:work+'/workspace',GITHUB_WORKSPACE:work,
  CJCJ_NATIVE_INPUT_ROOT:work+'/inputs',CJCJ_OFFICIAL_SDK_ROOT:work+'/unavailable-host'};
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
 for(const file of ['.gitignore','ci/runtime_pin.env','ci/llvm_pin.env','ci/source_pin.env','ci/source_pin.env',
  'ci/docs/dryrun-execution-policy.md','.github/workflows/release.yml']){
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
 const freeze=JSON.parse(await fs.readFile(path.dirname(exported.G2_IDENTITY)+'/FREEZE.json'));
 assert.equal(freeze.pins.RUNTIME_REF,selectedR);assert.equal(freeze.pins.LLVM_SHA,selectedN);
 assert.equal(freeze.selected_host,exported.CJCJ_OFFICIAL_SDK_ROOT);
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

test('POSIX configured source can be cloned locally at its exact pin', {skip:process.platform==='win32'}, async t=>{
 const {pathToFileURL}=await import('node:url');
 const {prepareSources}=await import('./sdk-flow.mjs');
 const {readSourcePins}=await import('../native-llvm-inputs.mjs');
 await fs.mkdir(root,{recursive:true});
 const work=await fs.mkdtemp(path.join(await fs.realpath(root),'stage0-handoff-'));
 t.after(()=>fs.rm(work,{force:true,recursive:true}));
 const inputs=path.join(work,'inputs'),workspace=path.join(work,'workspace');
 // The next source is deliberately non-reusable, stopping configure after LLVM
 // without needing an SDK. Its repo also serves as our local upstream.
 const upstream=path.join(workspace,'native-sources/runtime');
 await fs.mkdir(upstream,{recursive:true});
 const git=(cwd,...args)=>{
   const r=spawnSync('git',['-C',cwd,...args],{encoding:'utf8'});
   assert.equal(r.status,0,r.stderr);return r.stdout.trim();
 };
 git(upstream,'init','-q');git(upstream,'config','uploadpack.allowFilter','true');
 git(upstream,'remote','add','origin','file:///unused-runtime');
 const commit=async value=>{
   await fs.writeFile(path.join(upstream,'file'),value);
   git(upstream,'add','file');git(upstream,'-c','user.name=Fixture','-c','user.email=fixture@localhost','commit','-qm',value);
   return git(upstream,'rev-parse','HEAD');
 };
 await commit('parent');const pin=await commit('selected');
 await commit('unselected blob'); // advertised branch tip, absent in the old partial clone
 await fs.mkdir(path.join(inputs,'modules'),{recursive:true});
 const platform=hostPlatform();
 await fs.writeFile(path.join(inputs,'locations.json'),JSON.stringify({platform,hleDependencies:'hle.json'}));
 const member=name=>({path:name,source:'fixture',version:'1'});
 await fs.writeFile(path.join(inputs,'hle.json'),JSON.stringify({platform,node:member('locations.json'),modules:member('modules'),cjbind:member('locations.json')}));
 const env={...process.env,CANGJIE_WORKSPACE:workspace,GITHUB_WORKSPACE:upstream,GITHUB_SHA:git(upstream,'rev-parse','HEAD'),CJCJ_NATIVE_INPUT_ROOT:inputs,
   CJCJ_OFFICIAL_SDK_ROOT:work,CJCJ_NATIVE_LLVM_REF:pin,CJCJ_NATIVE_RUNTIME_REF:pin,CJCJ_NATIVE_PAIR_SELECTION:'explicit',
   GIT_ALLOW_PROTOCOL:'file',GIT_CONFIG_COUNT:'1',GIT_CONFIG_KEY_0:'url.'+pathToFileURL(upstream).href+'.insteadOf',
   GIT_CONFIG_VALUE_0:readSourcePins().llvm.LLVM_URL,CJCJ_SRCBUILD_SOURCE_MIRRORS:'',CJCJ_SRCBUILD_REQUIRE_MIRRORS:'0'};
 delete env.GITHUB_ENV;delete env.CJCJ_NATIVE_RUNTIME_INSTALL;delete env.CJCJ_PINNED_RUNTIME_GIT_DIR;
 const configured=spawnSync(process.execPath,[new URL('./configure-gha-inputs.mjs',import.meta.url).pathname],{env,encoding:'utf8'});
 assert.equal(configured.status,1);assert.match(configured.stderr,/GHA_NATIVE_SOURCE_REUSE_CHANGED runtime/);
 const source=path.join(workspace,'native-sources/llvm'),checkout=path.join(work,'private');
 const repo={root:source,checkout,commit:pin,tree:git(source,'rev-parse','HEAD^{tree}')};
 await prepareSources({llvm:repo},[]);
 assert.equal(git(checkout,'rev-parse','HEAD'),pin);
 assert.equal(await fs.readFile(path.join(checkout,'file'),'utf8'),'selected');
 assert.equal(git(source,'rev-parse','--is-shallow-repository'),'true');
 assert.equal(spawnSync('git',['-C',source,'config','--get','remote.origin.promisor']).status,1);
});

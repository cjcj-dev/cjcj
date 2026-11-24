import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import {spawnSync} from 'node:child_process';
import {load} from '../vendor/js-yaml/js-yaml.mjs';
import {getBuildTarget} from '../../build/lib/build-target.mjs';
import {packageConsumption} from '../../build/sdk/producers/srcbuild/lib/package-install.mjs';
import {workflowSourceSelection} from '../../build/sdk/producers/srcbuild/source-selection.mjs';
import {nativeInstallationLocations} from './native-installation-locations.mjs';
import {verifyRelocatedCjdbPython} from './sdk-cjdb-python.mjs';

const repo=path.resolve(import.meta.dirname,'../..');
const inputs={native_runtime_artifact:'finite-declaration-R',native_runtime_run_id:'11',native_llvm_ref:'1'.repeat(40),
 native_runtime_ref:'2'.repeat(40),native_host_version:'1.3.0-alpha.20261009001050',native_inputs_artifact:'finite-declaration-H-tools',
 native_inputs_run_id:'12',native_build_inputs_artifact:'finite-declaration-native-sources',native_build_inputs_run_id:'13',
 source_selection:JSON.stringify({compiler:{url:'https://example.invalid/private-compiler.git',tag:'3'.repeat(40)}})};
const workflow=name=>load(fs.readFileSync(path.join(repo,'.github/workflows',name),'utf8'));
const selectedEnv=wf=>Object.fromEntries(Object.entries(wf.env).map(([k,v])=>[k,v.replace(/\$\{\{ inputs\.(\w+) \}\}/g,(_,name)=>inputs[name]??'')]));
function fixture(t){const root=fs.mkdtempSync(path.join(os.tmpdir(),'native-workflow-'));t.after(()=>fs.rmSync(root,{recursive:true,force:true}));return root;}
function plan(t,target,extra={}) {
 const wf=workflow('sdk-build-target.yml'),root=fixture(t),file=path.join(root,'outputs');
 const step=wf.jobs.plan.steps.find(s=>s.id==='select');
 const r=spawnSync('bash',['-e','-c',step.run],{cwd:repo,encoding:'utf8',env:{...process.env,...selectedEnv(wf),REQUESTED:target,GITHUB_OUTPUT:file,...extra}});
 const output=fs.existsSync(file)?Object.fromEntries(fs.readFileSync(file,'utf8').trim().split('\n').map(l=>{const i=l.indexOf('=');return[l.slice(0,i),l.slice(i+1)];})):{};
 return {...r,output};
}
test('formal native planner routes five host tuples; declarations are not installed SDK qualification',t=>{
 for(const [target,runner,platform] of [['linux-x64','ubuntu-22.04','linux_x86_64'],['linux-aarch64','ubuntu-24.04-arm','linux_aarch64'],
  ['darwin-arm64','macos-15','darwin_aarch64'],['darwin-x64','macos-15-intel','darwin_x86_64'],['windows-x64','windows-2025','windows_x86_64']]) {
  const r=plan(t,target);console.log('NATIVE_SOURCE_ROUTE_ASSERTION_REACHED '+target);assert.equal(r.status,0,r.stderr);
  const [row]=JSON.parse(r.output.matrix).include;
  assert.equal(row.target,target);assert.equal(row.runner,runner);assert.equal(row.llvm_platform,platform);assert.equal(row.input_route,'native-installations');
 }
 console.log('NATIVE_SOURCE_ROUTE_ASSERTION_REACHED');
});
test('formal native planner rejects missing producer event and incomplete pair; default ARM refusal remains',t=>{
 for(const field of ['CJCJ_NATIVE_RUNTIME_RUN_ID','CJCJ_NATIVE_INPUTS_RUN_ID','CJCJ_NATIVE_BUILD_INPUTS_RUN_ID','CJCJ_NATIVE_LLVM_REF']) {
  const r=plan(t,'linux-aarch64',{[field]:''});assert.equal(r.status,1);assert.match(r.stderr,/NATIVE_.*(?:REQUIRED|PAIR)/);
 }
 const blank=Object.fromEntries(Object.keys(selectedEnv(workflow('sdk-build-target.yml'))).map(k=>[k,'']));
 const r=plan(t,'linux-aarch64',blank);assert.equal(r.status,1);assert.match(r.stderr,/issues\/763/);
});
test('native workflow builds N via the existing producer and transports installation before host/configure',()=>{
 const wf=workflow('sdk-build-target.yml'),producer=wf.jobs['native-cjdb'],consumer=wf.jobs['source-stage0'];
 assert.ok(consumer.needs.includes('native-cjdb'));
 const scripts=producer.steps.map(s=>s.run||'').join('\n');
 assert.match(scripts,/node ci\/bootstrap\/native-cjdb-job.mjs build/);
 assert.equal(producer.steps.find(s=>s.uses==='actions/upload-artifact@v7.0.2').with.path,'${{ runner.temp }}/native-cjdb/native-install.tar');
 const unpack=consumer.steps.findIndex(s=>s.run?.includes('native-cjdb-job.mjs unpack'));
 const host=consumer.steps.findIndex(s=>s.run?.includes('prepare-native-host.mjs'));
 const configure=consumer.steps.findIndex(s=>s.run?.includes('configure-gha-inputs.mjs'));
 assert.ok(unpack>=0&&host>unpack&&configure>host);
 assert.match(consumer.env.CJCJ_NATIVE_CJDB_INSTALL,/native-cjdb-install/);
 const release=workflow('release.yml');
 // One source call covers every host cell (windows-x64 included); every package cell waits for it.
 assert.equal(release.jobs.source.with.targets,'all');
 assert.equal(release.jobs.package.needs,'source');
 assert.ok(release.jobs.package.strategy.matrix.include.some(row=>row.release_key==='win32-x64'&&row.platform==='windows-x64'));
});
test('native Windows install/unpack consumer uses native build target; Linux cross remains non-executable',()=>{
 const native=getBuildTarget('windows-x64',{platform:'win32',arch:'x64',env:{}});
 assert.equal(packageConsumption(native).status,'EXECUTED');
 assert.equal(native.spec.loaderEnv,'PATH');
 assert.equal(packageConsumption(getBuildTarget('windows-x64',{platform:'linux',arch:'x64'})).status,'NOT_RUN');
});
test('ordinary stdx source selection preserves distinct full sources and actual native AST/runtime',()=>{
 const env=selectedEnv(workflow('sdk-build-target.yml'));
 const base=workflowSourceSelection(env);assert.equal(base.STDX_REF,(key=>new RegExp(`^${key}=([0-9a-f]{40})$`,'m').exec(fs.readFileSync(new URL('../source_pin.env',import.meta.url),'utf8'))[1])('STDX_REF'));
 const tools=/^TOOLS_REF=([a-f0-9]{40})$/m.exec(fs.readFileSync(path.join(repo,'ci/source_pin.env'),'utf8'))[1];
 assert.equal(base.TOOLS_REF,tools);
 assert.equal(base.CJPM_REF,undefined,'CJPM has no independent source selector');
 console.log('WORKFLOW_PIN_SELECTION_ASSERTION_REACHED',JSON.stringify({tools:base.TOOLS_REF,stdx:base.STDX_REF}));
 const alternative=workflowSourceSelection({...env,CJCJ_SOURCE_SELECTION:JSON.stringify({compiler:JSON.parse(inputs.source_selection).compiler,stdx:{url:'https://example.invalid/stdx.git',tag:'c3066ac097166145765b274d7a4a79e43d70ffc8'}})});
 assert.equal(alternative.STDX_REF,'c3066ac097166145765b274d7a4a79e43d70ffc8');assert.notEqual(alternative.STDX_REF,base.STDX_REF);
 assert.equal(alternative.CANGJIE_COMPILER_SHA,'3'.repeat(40));assert.equal(alternative.CJCJ_NATIVE_RUNTIME_REF,'2'.repeat(40));
 const explicitTools=workflowSourceSelection({...env,CJCJ_SOURCE_SELECTION:JSON.stringify({compiler:JSON.parse(inputs.source_selection).compiler,tools:{tag:'4'.repeat(40)}})});
 assert.equal(explicitTools.TOOLS_REF,'4'.repeat(40));assert.equal(explicitTools.CJPM_REF,undefined);
 assert.throws(()=>workflowSourceSelection({...env,CJCJ_SOURCE_SELECTION:JSON.stringify({cjpm:{tag:'5'.repeat(40)}})}),/WORKFLOW_SOURCE_SELECTION/);
 assert.equal(explicitTools.STDX_REF,base.STDX_REF);assert.equal(explicitTools.CJCJ_NATIVE_RUNTIME_REF,base.CJCJ_NATIVE_RUNTIME_REF);
 assert.equal(workflowSourceSelection(env).TOOLS_REF,tools);assert.equal(workflowSourceSelection(env).CJPM_REF,undefined);
 assert.throws(()=>workflowSourceSelection({...env,CJCJ_SOURCE_SELECTION:JSON.stringify({runtime:{tag:'4'.repeat(40)}})}),/SOURCE_CONFLICT/);
});
test('transport locations select same N/AST installation without overwriting original facts',async t=>{
 const root=fixture(t),install=path.join(root,'install');fs.mkdirSync(install);
 const facts={platform:'linux_x86_64',configuration:{build:'/original/build'},pythonSource:{build:{originalInputs:{sha256:'a'.repeat(64)}}}};
 const bytes=JSON.stringify(facts);fs.writeFileSync(path.join(install,'BUILD-INPUTS.json'),bytes);
 const locations=await nativeInstallationLocations(root,{platform:'linux_x86_64'},{CJCJ_NATIVE_CJDB_INSTALL:install});
 assert.equal(locations.llvm.install,install);assert.equal(locations.ast.install,install);assert.deepEqual(locations.llvm.configuration,facts.configuration);
 assert.equal(fs.readFileSync(path.join(install,'BUILD-INPUTS.json'),'utf8'),bytes);
 await assert.rejects(()=>nativeInstallationLocations(root,{platform:'windows_x86_64'},{CJCJ_NATIVE_CJDB_INSTALL:install}),/PLATFORM/);
});
test('relocated Python refuses changed original configuration before running an installed interpreter',async()=>{
 await assert.rejects(()=>verifyRelocatedCjdbPython({original:{python:{configured:{selected:{suffix:'x'},actual:{suffix:'y'}}}},python:{},platform:'linux_x86_64'}),/original configured/);
});

test('public installation unpack transports original facts and refuses an existing destination',async t=>{
 const root=fixture(t),from=path.join(root,'from'),install=path.join(root,'install'),archive=path.join(root,'native-install.tar');
 fs.mkdirSync(from);const bytes='{"platform":"linux_x86_64","configuration":{"build":"/producer/build"}}\n';
 fs.writeFileSync(path.join(from,'BUILD-INPUTS.json'),bytes);
 fs.writeFileSync(path.join(from,'payload'),'finite transport bytes, not a native SDK\n');fs.symlinkSync('payload',path.join(from,'link'));
 const tar=spawnSync('tar',['-cf',archive,'-C',from,'.'],{encoding:'utf8'});assert.equal(tar.status,0,tar.stderr);
 const entry=path.join(repo,'ci/bootstrap/native-cjdb-job.mjs');
 const first=spawnSync(process.execPath,[entry,'unpack',archive,install],{encoding:'utf8'});assert.equal(first.status,0,first.stderr);
 console.log('NATIVE_INSTALL_TRANSPORT_ASSERTION_REACHED');
 assert.equal(fs.readFileSync(path.join(install,'BUILD-INPUTS.json'),'utf8'),bytes);
 assert.equal(fs.readFileSync(path.join(install,'link'),'utf8'),'finite transport bytes, not a native SDK\n');
 const selected=await nativeInstallationLocations(root,{platform:'linux_x86_64'},{CJCJ_NATIVE_CJDB_INSTALL:install});
 assert.equal(selected.llvm.install,selected.ast.install);assert.equal(selected.llvm.configuration.build,'/producer/build');
 const again=spawnSync(process.execPath,[entry,'unpack',archive,install],{encoding:'utf8'});
 assert.equal(again.status,1);assert.match(again.stderr,/EEXIST/);
});


test('Windows source plan, upload and package receive the same native std for pinned and explicit pairs',t=>{
 const wf=workflow('sdk-package.yml'),job=wf.jobs.package,source=workflow('sdk-build-target.yml');
 const release=workflow('release.yml'),caller={...release.jobs.package.with,...release.jobs.package.strategy.matrix.include.find(row=>row.release_key==='win32-x64')};
 const root=fixture(t),entry=job.steps.find(s=>s.id==='package-inputs');
 const gate=job.steps.find(s=>s.name==='Validate same-platform final std contract');
 const native=source.jobs['native-windows-sdk'];
 assert.equal(native['runs-on'],'${{ matrix.runner }}');
 assert.equal(native.if,"needs.plan.outputs.llvm_platforms == 'windows_x86_64'");
 assert.match(source.jobs['source-stage0'].if,/llvm_platforms != 'windows_x86_64'/);
 const programs=native.steps.map(step=>step.run||'').join('\n');
 assert.doesNotMatch(programs,/job-handoff|native-cjdb-job\.mjs materialize/);
 for(const phase of ['stage0','stage1-initial-std','stage1-std','stage1-compiler'])assert.ok(programs.includes('gha_run.sh '+phase));
 const production=native.steps.filter(step=>step.run);
 let previous=-1;
 for(const name of ['Resolve actual source selection','Download pinned source','Verify source revisions','Configure native bootstrap from actual repositories and target installations','Bootstrap stage0 compiler','Bootstrap stage1-initial-std','Bootstrap stage1-std','Bootstrap stage1 compiler','Build stage 3 compiler and final std','Build stdx from source','Build Windows SDK tools with the installed stage3 frontend','Test and archive installed SDK']){
   const i=production.findIndex(s=>s.name===name);assert.ok(i>previous,name);previous=i;
 }
 const archive=native.steps.find(s=>s.name==='Upload complete native Windows SDK');
 const paths=archive.with.path.trim().split('\n');
 assert.equal(archive.with['if-no-files-found'],'error');
 assert.equal(paths.length,2);assert.match(paths[0],/\/software\/cangjie-sdk-windows-x64-.*-cjcj\.zip$/);
 assert.equal(paths[1],paths[0]+'.sha256');
 const upload=native.steps.find(s=>s.name==='Upload final source-built std install root');
 assert.equal(gate.env.EXPECTED_STD_ARTIFACT,'${{ steps.package-inputs.outputs.std_artifact }}');
 assert.equal(caller.std_artifact,'final-std-native-windows-x64'); // literal matrix row, re-checked at run time by the gate above
 for(const mode of ['default','explicit']){
  const fields={...inputs,...(mode==='default'?{native_llvm_ref:'',native_runtime_ref:'',native_host_version:''}:{})};
  const env={...process.env,RELEASE_PLATFORM:caller.platform,RELEASE_KEY:caller.release_key,
    GITHUB_ENV:path.join(root,mode+'-env'),GITHUB_OUTPUT:path.join(root,mode+'-output')};
  for(const name of ['native_runtime_artifact','native_llvm_ref','native_runtime_ref','native_host_version']){
   const key='CJCJ_'+name.toUpperCase();
   assert.equal(job.env[key],'${{ inputs.'+name+' }}');assert.equal(caller[name],job.env[key]);env[key]=fields[name];
  }
  const sourcePlan=plan(t,'windows-x64',Object.fromEntries(Object.entries(env).filter(([k])=>k.startsWith('CJCJ_NATIVE_'))));
  assert.equal(sourcePlan.status,0,sourcePlan.stderr);
  const selection=native.steps.find(s=>s.name==='Resolve actual source selection'),selectedFile=path.join(root,mode+'-selected');
  const invoke=target=>spawnSync('bash',['-eu','-c',selection.run],{cwd:repo,encoding:'utf8',env:{...selectedEnv(source),...env,WINDOWS_TOOLS_REPOSITORY:'cjcj-dev/cjcj-tools',GITHUB_SERVER_URL:'https://github.com',CJCJ_SRCBUILD_TARGET:target,GITHUB_ENV:selectedFile}});
  const win=invoke('windows-x64'),linux=invoke('linux-x64');
  assert.equal(win.status,0,win.stderr);assert.equal(linux.status,0,linux.stderr);
  const pin=JSON.parse(win.stdout).TOOLS_REF,other=JSON.parse(linux.stdout).TOOLS_REF;
  // Windows now builds the same public product tools commit as every other host.
  assert.equal(pin,(key=>new RegExp(`^${key}=([0-9a-f]{40})$`,'m').exec(fs.readFileSync(new URL('../source_pin.env',import.meta.url),'utf8'))[1])('TOOLS_REF'));assert.equal(other,pin);
  const [cell]=JSON.parse(sourcePlan.output.matrix).include;
  assert.equal(cell.runner,'windows-2025');
  const artifact=cell[upload.with.name.match(/^\$\{\{ matrix\.(\w+) \}\}$/)[1]];
  assert.equal(artifact,'final-std-native-windows-x64');assert.equal(sourcePlan.output.std_artifact,artifact);
  const r=spawnSync('bash',['-eu','-c',entry.run],{cwd:repo,env,encoding:'utf8'});assert.equal(r.status,0,r.stderr);
  const expected=fs.readFileSync(env.GITHUB_OUTPUT,'utf8').trim().slice('std_artifact='.length);
  for(const [selected,rc] of [[artifact,0],['final-std-windows-x64',1]]){
   const checked=spawnSync('bash',['-eu','-c',gate.run],{env:{...env,EXPECTED_STD_ARTIFACT:expected,SELECTED_STD_ARTIFACT:selected}});
   console.log('WINDOWS_STD_SELECTION',mode,artifact,selected,checked.status);assert.equal(checked.status,rc);
  }
 }
});

test('transport preserves optional independent shim location without changing native N',async()=>{
 const root='/fixture/received';
 const selected=await nativeInstallationLocations(root,{installations:{
  llvm:{install:'N',buildResult:'N/BUILD-INPUTS.json'},shim:{install:'compiler-shim'}}},{});
 assert.equal(selected.shim.install,root+'/compiler-shim');
 assert.equal(selected.llvm.install,root+'/N');
 await assert.rejects(()=>nativeInstallationLocations(root,{installations:{shim:{install:'../escape'}}},{}));
 assert.equal((await nativeInstallationLocations(root,{},{})).shim,undefined);
});

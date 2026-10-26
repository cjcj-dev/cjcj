import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import {spawnSync} from 'node:child_process';
import {load} from '../vendor/js-yaml/js-yaml.mjs';
import {getBuildTarget} from '../../build/lib/build-target.mjs';
import {packageConsumption} from '../srcbuild/lib/package-install.mjs';
import {workflowSourceSelection} from '../srcbuild/source-selection.mjs';
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
 const wf=workflow('srcbuild-target.yml'),root=fixture(t),file=path.join(root,'outputs');
 const step=wf.jobs.plan.steps.find(s=>s.id==='select');
 const r=spawnSync('bash',['-e','-c',step.run],{cwd:repo,encoding:'utf8',env:{...process.env,...selectedEnv(wf),REQUESTED:target,GITHUB_OUTPUT:file,...extra}});
 const output=fs.existsSync(file)?Object.fromEntries(fs.readFileSync(file,'utf8').trim().split('\n').map(l=>{const i=l.indexOf('=');return[l.slice(0,i),l.slice(i+1)];})):{};
 return {...r,output};
}
test('formal native planner routes five host tuples; declarations are not installed SDK qualification',t=>{
 for(const [target,runner,platform] of [['linux-x64','ubuntu-22.04','linux_x86_64'],['linux-aarch64','ubuntu-24.04-arm','linux_aarch64'],
  ['darwin-arm64','macos-15','darwin_aarch64'],['darwin-x64','macos-15-intel','darwin_x86_64'],['windows-x64','windows-2022','windows_x86_64']]) {
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
 const blank=Object.fromEntries(Object.keys(selectedEnv(workflow('srcbuild-target.yml'))).map(k=>[k,'']));
 const r=plan(t,'linux-aarch64',blank);assert.equal(r.status,1);assert.match(r.stderr,/issues\/763/);
});
test('native workflow builds N via the existing producer and transports installation before host/configure',()=>{
 const wf=workflow('srcbuild-target.yml'),producer=wf.jobs['native-cjdb'],consumer=wf.jobs['source-stage0'];
 assert.ok(consumer.needs.includes('native-cjdb'));
 const scripts=producer.steps.map(s=>s.run||'').join('\n');
 assert.match(scripts,/node ci\/bootstrap\/native-cjdb-job.mjs build/);
 assert.equal(producer.steps.find(s=>s.uses==='actions/upload-artifact@v7').with.path,'${{ runner.temp }}/native-cjdb/native-install.tar');
 const unpack=consumer.steps.findIndex(s=>s.run?.includes('native-cjdb-job.mjs unpack'));
 const host=consumer.steps.findIndex(s=>s.run?.includes('prepare-native-host.mjs'));
 const configure=consumer.steps.findIndex(s=>s.run?.includes('configure-gha-inputs.mjs'));
 assert.ok(unpack>=0&&host>unpack&&configure>host);
 assert.match(consumer.env.CJCJ_NATIVE_CJDB_INSTALL,/native-cjdb-install/);
 const release=workflow('release.yml');
 assert.equal(release.jobs['source-p3-windows-x64'].with.targets,'windows-x64');
 assert.ok(release.jobs['package-p3-windows-x64'].needs.includes('source-p3-windows-x64'));
});
test('native Windows install/unpack consumer uses native build target; Linux cross remains non-executable',()=>{
 const native=getBuildTarget('windows-x64',{platform:'win32',arch:'x64',env:{}});
 assert.equal(packageConsumption(native).status,'EXECUTED');
 assert.equal(native.spec.loaderEnv,'PATH');
 assert.equal(packageConsumption(getBuildTarget('windows-x64',{platform:'linux',arch:'x64'})).status,'NOT_RUN');
});
test('ordinary stdx source selection preserves distinct full sources and actual native AST/runtime',()=>{
 const env=selectedEnv(workflow('srcbuild-target.yml'));
 const base=workflowSourceSelection(env);assert.equal(base.STDX_REF,'b10784b27a5b3f815c9542d28f3ba02f48db48d5');
 assert.equal(base.TOOLS_REF,'7acd240e273f9e5773611deca29bba3267afd0fd');
 const cjpm=/^CJPM_FORK_REF=([a-f0-9]{40})$/m.exec(fs.readFileSync(path.join(repo,'ci/cjpm_pin.env'),'utf8'))[1];
 assert.equal(base.CJPM_REF,cjpm);
 console.log('WORKFLOW_PIN_SELECTION_ASSERTION_REACHED',JSON.stringify({tools:base.TOOLS_REF,stdx:base.STDX_REF,cjpm:base.CJPM_REF}));
 const alternative=workflowSourceSelection({...env,CJCJ_SOURCE_SELECTION:JSON.stringify({compiler:JSON.parse(inputs.source_selection).compiler,stdx:{url:'https://example.invalid/stdx.git',tag:'c3066ac097166145765b274d7a4a79e43d70ffc8'}})});
 assert.equal(alternative.STDX_REF,'c3066ac097166145765b274d7a4a79e43d70ffc8');assert.notEqual(alternative.STDX_REF,base.STDX_REF);
 assert.equal(alternative.CANGJIE_COMPILER_SHA,'3'.repeat(40));assert.equal(alternative.CJCJ_NATIVE_RUNTIME_REF,'2'.repeat(40));
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

test('formal Windows release package key needs an explicit pair and its native std contract',t=>{
 const root=fixture(t),wf=workflow('build-release-package.yml');
 const entry=wf.jobs.package.steps.find(s=>s.run?.includes('ci/release/package-key.mjs'));
 const env={...process.env,...selectedEnv(workflow('srcbuild-target.yml')),RELEASE_PLATFORM:'windows-x64',RELEASE_KEY:'win32-x64',GITHUB_ENV:path.join(root,'env')};
 const r=spawnSync('bash',['-e','-c',entry.run],{cwd:repo,env,encoding:'utf8'});
 console.log('NATIVE_WINDOWS_PACKAGE_ENTRY_ASSERTION_REACHED');
 assert.equal(r.status,0,r.stderr);assert.equal(fs.readFileSync(env.GITHUB_ENV,'utf8'),'PACKAGE_KEY=windows-x64\n');
 const std=wf.jobs.package.steps.find(s=>s.name==='Validate same-platform final std contract');
 const rows=selectedEnv(workflow('srcbuild-target.yml'));
 assert.ok(rows.CJCJ_NATIVE_LLVM_REF);assert.match(std.env.EXPECTED_STD_ARTIFACT,/final-std-native-windows-x64/);
 const run=selected=>spawnSync('bash',['-e','-c',std.run],{cwd:repo,encoding:'utf8',env:{...env,EXPECTED_STD_ARTIFACT:'final-std-native-windows-x64',SELECTED_STD_ARTIFACT:selected}});
 assert.equal(run('final-std-native-windows-x64').status,0);assert.equal(run('final-std-windows-x64').status,1);
});

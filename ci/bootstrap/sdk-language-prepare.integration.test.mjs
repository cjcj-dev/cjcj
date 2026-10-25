#!/usr/bin/env zx
// Public descriptor/prepare wiring only. Fixed language sources and real Git/C
// fixture artifacts cross the receiver; CPP/N/AST shapes are finite fixtures,
// not qualification of a runtime, AST, compiler, installed SDK or language ABI.
import fs from 'node:fs';
import path from 'node:path';
import assert from 'node:assert/strict';
import test from 'node:test';
import {spawnSync} from 'node:child_process';
import {createHash} from 'node:crypto';
import {directSource,directBuild,write} from '../fixtures/runtime-direct-inputs.mjs';
import {installGcUnitInputs} from '../../build/srcbuild/gc-unit-gate.mjs';
import {buildConfig} from '../../build/lib/config.mjs';
import {hostToolchainFromCjcVersion} from '../host-toolchain-pin.mjs';
const parent=process.env.RELEASE_EVIDENCE_TEST_ROOT,host=process.env.CJCJ_LANGUAGE_PREPARE_HOST;
assert(parent&&host,'RELEASE_EVIDENCE_TEST_ROOT and read-only CJCJ_LANGUAGE_PREPARE_HOST required');
const entry=new URL('./prepare-bootstrap-plans.mjs',import.meta.url).pathname;
const fixed=JSON.parse(fs.readFileSync(new URL('../platform_matrix/fixtures/runtime-language-259.json',import.meta.url)));
const platform='linux_x86_64',tuple=platform+'_cjnative';
function fixture(kind) {
 const root=fs.mkdtempSync(path.join(parent,'descriptor-'+kind+'-')),source=root+'/source',runtime=source+'/runtime',sdk=root+'/runtime-install';
 const calls=[];
 const run=(label,argv,extra={})=>{
  const r=spawnSync(argv[0],argv.slice(1),{encoding:'utf8',maxBuffer:4*1024**2,...extra});
  calls.push({label,argv,rc:r.status,signal:r.signal,error:r.error?.message});
  write(root+'/'+calls.length+'-'+label+'.stdout',r.stdout||'');write(root+'/'+calls.length+'-'+label+'.stderr',r.stderr||'');
  write(root+'/commands.json',JSON.stringify(calls,null,2));return r;
 };
 const ok=r=>{assert.equal(r.status,0,r.stdout+r.stderr);return r.stdout.trim();};
 directSource(runtime);directBuild(runtime);
 if(kind==='legacy') {
  for(const member of ['tests/gc_unit/gate_gc_unit.mjs','tests/gc_unit/language_toolchain.mjs','tests/gc_unit/product_test_configuration.mjs','build/resolve_runtime_headers.mjs'])fs.unlinkSync(runtime+'/'+member);
  for(const [member,contents]of Object.entries(fixed.files))write(runtime+'/'+member,contents);
 }
 write(source+'/packages/macro/src/InvokeUtil.cj',fs.readFileSync(new URL('../../packages/macro/src/InvokeUtil.cj',import.meta.url)));
 write(source+'/probe.c','unsigned long g_cjLoadBadMask=42;\nconst char source_stamp[]="CJRT-COMMIT:" FIXTURE_COMMIT;\n');
 write(source+'/CMakeLists.txt',`cmake_minimum_required(VERSION 3.20)
project(DescriptorFixture C)
set(STD_SUPPORT ON CACHE BOOL "finite AST shape fixture")
add_compile_definitions(FIXTURE_COMMIT="\${FIXTURE_COMMIT}")
foreach(name fixture-runtime fixture-static cangjie-ast-support)
 if(name STREQUAL "fixture-runtime")
  add_library(\${name} SHARED probe.c)
 else()
  add_library(\${name} STATIC probe.c)
 endif()
endforeach()
`);
 for(const args of [['init','-q'],['add','.'],['-c','user.name=Zxilly','-c','user.email=zxilly@outlook.com','commit','-qm','test: bounded descriptor sources']])ok(run('git',['git','-C',source,...args]));
 const commit=ok(run('head',['git','-C',source,'rev-parse','HEAD']));
 ok(run('origin',['git','-C',source,'remote','add','origin','file://'+source]));
 ok(run('configure',['cmake','-S',source,'-B',root+'/build','-G','Ninja','-DFIXTURE_COMMIT='+commit]));
 ok(run('build',['cmake','--build',root+'/build','--parallel','2']));
 const copy=(from,to)=>{fs.mkdirSync(path.dirname(to),{recursive:true});fs.copyFileSync(from,to);};
 copy(root+'/build/libfixture-runtime.so',sdk+'/runtime/lib/'+tuple+'/libcangjie-runtime.so');
 copy(root+'/build/libfixture-runtime.so',sdk+'/runtime/lib/'+tuple+'/libboundscheck.so');
 copy(root+'/build/libfixture-static.a',sdk+'/lib/'+tuple+'/libcangjie-runtime.a');
 installGcUnitInputs(buildConfig({targetKey:'linux-x64'}),runtime,sdk);
 const carried=sdk+'/share/runtime-build/runtime';
 assert.equal(fs.existsSync(carried+'/tests/gc_unit/language_toolchain.mjs'),kind==='modern');
 const observed=ok(run('host-version',[host+'/bin/cjc','--version']));
 const version=hostToolchainFromCjcVersion(observed).replace(/^nightly-/,'');
 write(sdk+'/SOURCE_SHA',commit+'\n');
 write(sdk+'/NATIVE-INPUTS.json',JSON.stringify({runtime_sha:commit,paired_llvm_sha:commit,platform,version,build_type:'release',language_test_mode:'defer',finiteFixture:true}));
 const native=root+'/native-shapes';
 for(const member of ['third_party/llvm/bin/llc','third_party/llvm/bin/llvm-as','third_party/llvm/bin/llvm-dis','third_party/llvm/lib/libLLVM-15.so','third_party/llvm/fixed-llc/cjselfhost_llvmshim.o','tools/bin/cjdb',
 'schema/StdAstFormat.fbs','include/flatbuffers/StdAstFormat_generated.h','third_party/flatbuffers/bin/flatc'])write(native+'/'+member,'Unexecuted finite component shape; not a native SDK.\n');
 const library='lib/'+tuple+'/libcangjie-ast-support.a';copy(root+'/build/libcangjie-ast-support.a',native+'/'+library);
 const files={};for(const member of [library,'schema/StdAstFormat.fbs','include/flatbuffers/StdAstFormat_generated.h','third_party/flatbuffers/bin/flatc']){
  const bytes=fs.readFileSync(native+'/'+member);files[member]={bytes:bytes.length,sha256:createHash('sha256').update(bytes).digest('hex')};
 }
 const nativeFacts=native+'/finite-build.json';write(nativeFacts,JSON.stringify({finiteFixture:true,platform,commits:{compiler:commit,llvm:commit},
  astInstallation:{platform,source:{commit},library,files,build:{target:'cangjie-ast-support',configuration:{stdSupport:'ON',finiteFixture:true}}}}));
 for(const member of ['cjcj-stage1.mjs','stage1-transform.mjs'])write(root+'/private/ts/src/sharedbuild/'+member,'// unexecuted finite stage boundary\n');
 const descriptor={platform,work:root+'/work',install:root+'/sdk-not-built',host:{install:host,version},tools:{privateRoot:root+'/private'},
  sources:Object.fromEntries(['compiler','h1','ast','llvm','runtime'].map(name=>[name,source])),
  ...Object.fromEntries(['compiler','h1','ast','llvm','runtime'].map(name=>[name+'Commit',commit])),
  nativePair:{llvm:commit,runtime:commit,hostVersion:version},
  installations:{llvm:{install:native,buildResult:nativeFacts,configuration:{finiteFixture:true}},ast:{install:native,buildResult:nativeFacts,configuration:{finiteFixture:true}},
   runtime:{install:sdk,sourceRoot:sdk+'/share/runtime-build',buildResult:sdk+'/NATIVE-INPUTS.json',configuration:{buildType:'release',version,hostVersion:version,pairedLlvmCommit:commit}}}};
 const prepare=(label,{paired=true}={})=>{
  const d=structuredClone(descriptor);d.work=root+'/'+label+'-work';d.install=root+'/'+label+'-sdk-not-built';if(!paired)delete d.nativePair;
  const file=root+'/'+label+'.descriptor.json',workspace=root+'/'+label+'-workspace';write(file,JSON.stringify(d));
  const env={...process.env,CJCJ_NATIVE_INPUTS:file,CJCJ_SDK_INPUTS:'',CJCJ_SDK_TARGETS:'',CANGJIE_WORKSPACE:workspace,GITHUB_ENV:''};
  const r=run(label,[process.execPath,entry],{env});return {...r,workspace,descriptor:d};
 };
 return {root,sdk,carried,prepare};
}
for(const kind of ['legacy','modern']) {
 test('formal descriptor accepts '+kind+' through native receiver and upper preparation',()=>{
  const f=fixture(kind);
  for(const paired of [true,false]) {
   const r=f.prepare(paired?'received':'supplied',{paired});
   console.log('LANGUAGE_DESCRIPTOR_ACCEPT_TARGET '+kind+' paired='+paired+' rc='+r.status);
   assert.equal(r.status,0,r.stdout+r.stderr);
   if(paired)assert.match(r.stdout,/NATIVE_RUNTIME_COMPONENT_ACCEPTED/);
   const plan=JSON.parse(fs.readFileSync(r.workspace+'/build-targets.json'));
   assert.equal(plan.bootstrapInputs.runtime.sourceRoot,path.dirname(f.carried));
   const command=plan.stages.find(stage=>stage.id==='stage3').test.commands[0].argv;
   assert.equal(command[command.indexOf('--runtime-source')+1],path.dirname(f.carried));
   assert.equal(fs.existsSync(r.descriptor.install),false,'prepare must not install a complete SDK');
  }
 });
 test('formal supplied descriptor rejects exact missing '+kind+' language inputs and restores',()=>{
  const f=fixture(kind);
  const members=['tests/gc_unit/'+(kind==='legacy'?'language_toolchain.sh':'language_toolchain.mjs'),
   'tests/gc_unit/run_finalizer_trigger.sh','build/resolve_runtime_headers.py',
   ...(kind==='legacy'?['tests/gc_unit/installed-language-entry.mjs']:['tests/gc_unit/product_test_configuration.mjs']),
   'CMakebuild/compile_commands.json','CMakebuild/gc-unit.status'];
  for(const [index,member]of members.entries()) {
   const file=f.carried+'/'+member;fs.renameSync(file,file+'.held');
   try {
    const r=f.prepare('missing-'+index,{paired:false});
    console.log('LANGUAGE_DESCRIPTOR_MISSING_TARGET '+kind+' '+member+' rc='+r.status);
    assert.equal(r.status,1,r.stdout+r.stderr);assert.ok(r.stderr.includes(member),r.stderr);
   } finally {fs.renameSync(file+'.held',file);}
  }
  const r=f.prepare('restored',{paired:false});assert.equal(r.status,0,r.stdout+r.stderr);
 });
}

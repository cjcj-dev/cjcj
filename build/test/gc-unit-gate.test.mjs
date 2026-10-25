import fs from 'node:fs';import os from 'node:os';import path from 'node:path';
import {spawnSync} from 'node:child_process';
import test from 'node:test';import assert from 'node:assert/strict';
import {buildConfig} from '../lib/config.mjs';
import {directSource,directBuild,write} from '../../ci/fixtures/runtime-direct-inputs.mjs';
import {languageInputEnvironment,gcUnitLanguageGateEnabled,gcUnitRuntimeBuildEnv,gcUnitBuildStatus,gcUnitStatusPath,beginGcUnitLanguageDeferral,finishGcUnitLanguageDeferral,assertGcUnitLanguageDeferred,assertGcUnitLanguageDone} from '../srcbuild/gc-unit-gate.mjs';
test('normal source build carries only this invocation defer and normal inputs',()=>{
 const root=fs.mkdtempSync(path.join(process.env.RELEASE_EVIDENCE_TEST_ROOT||os.tmpdir(),'direct-deferral-'));
 const config=buildConfig({workspace:root,targetKey:'linux-x64'}),runtime=path.join(config.repoPath('runtime'),'runtime'),sdk=root+'/sdk',env={CJCJ_SRCBUILD_HOST_SDK:root+'/host'};
 directSource(runtime);directBuild(runtime);
 assert.deepEqual(gcUnitRuntimeBuildEnv(config,env),{GC_UNIT_GATE_LANGUAGE_TESTS:'defer',GC_UNIT_GATE_STATUS:gcUnitBuildStatus(runtime)});
 beginGcUnitLanguageDeferral(config,runtime,sdk,{env});assert.equal(fs.existsSync(gcUnitBuildStatus(runtime)),false);
 assert.throws(()=>finishGcUnitLanguageDeferral(config,runtime,sdk,{env}),/gc-unit.status/);
 directBuild(runtime);finishGcUnitLanguageDeferral(config,runtime,sdk,{env});assertGcUnitLanguageDeferred(config,sdk,{env});
 assert.throws(()=>assertGcUnitLanguageDone(config,sdk,{env}),/LANGUAGE_DONE/);
 assert.ok(fs.existsSync(sdk+'/share/runtime-build/runtime/tests/gc_unit/language_toolchain.mjs'));
 const status=gcUnitStatusPath(config,sdk);write(status,'GATE=PASS\nGATE_RC=0\nLANGUAGE_TESTS=LANGUAGE_DONE\nLANGUAGE_TESTS=LANGUAGE_DEFERRED\n');assert.throws(()=>assertGcUnitLanguageDone(config,sdk,{env}),/duplicate status field/);
});
test('defer remains limited to selected native Linux and leaves unsupported targets untouched',()=>{
 const env={CJCJ_SRCBUILD_HOST_SDK:'/host'};
 for(const key of ['windows-x64','darwin-x64'])assert.equal(gcUnitRuntimeBuildEnv(buildConfig({targetKey:key}),env),undefined);
 assert.equal(gcUnitRuntimeBuildEnv(buildConfig({targetKey:'linux-x64',officialSdkRoot:null}),{}),undefined);
});

test('a delegating source entry cannot select shell compatibility when its mjs dependency is missing',()=>{
 const root=fs.mkdtempSync(path.join(process.env.RELEASE_EVIDENCE_TEST_ROOT||os.tmpdir(),'direct-missing-gate-'));
 const config=buildConfig({workspace:root,targetKey:'linux-x64'}),runtime=path.join(config.repoPath('runtime'),'runtime'),sdk=root+'/sdk',env={CJCJ_SRCBUILD_HOST_SDK:root+'/host'};
 directSource(runtime);directBuild(runtime);fs.renameSync(runtime+'/tests/gc_unit/gate_gc_unit.mjs',runtime+'/tests/gc_unit/gate_gc_unit.mjs.saved');
 assert.throws(()=>finishGcUnitLanguageDeferral(config,runtime,sdk,{env}),/gate_gc_unit.mjs/);
 fs.renameSync(runtime+'/tests/gc_unit/gate_gc_unit.mjs.saved',runtime+'/tests/gc_unit/gate_gc_unit.mjs');
 finishGcUnitLanguageDeferral(config,runtime,sdk,{env});assertGcUnitLanguageDeferred(config,sdk,{env});
});

test('cross target keeps the actual Linux compiler host and does not enable native language execution',()=>{
 const root=fs.mkdtempSync(path.join(process.env.RELEASE_EVIDENCE_TEST_ROOT||os.tmpdir(),'direct-cross-'));
 const config=buildConfig({workspace:root,targetKey:'windows-x64'}),sdk=root+'/sdk',host=root+'/host',runtime=root+'/source/runtime';
 directSource(runtime);
 write(sdk+'/bin/cjc','#!'+process.execPath+'\n',0o755);
 write(host+'/runtime/lib/linux_x86_64_cjnative/libcangjie-runtime.so','host');
 write(sdk+'/runtime/lib/windows_x86_64_cjnative/libcangjie-runtime.dll','target');
 write(sdk+'/runtime/lib/windows_x86_64_cjnative/libboundscheck.dll','target bounds');
 write(sdk+'/lib/windows_x86_64_cjnative/libcangjie-std-core.a','target std');
 const env=languageInputEnvironment(config,sdk,{...process.env,CJCJ_SRCBUILD_HOST_SDK:host});
 assert.equal(env.GC_UNIT_CJC_RUNTIME_TUPLE,'linux_x86_64_cjnative');assert.equal(env.GC_UNIT_RUNTIME_TUPLE,'windows_x86_64_cjnative');
 assert.equal(gcUnitLanguageGateEnabled(config,env),false);
 const argv=[runtime+'/tests/gc_unit/language_toolchain.mjs'],r=spawnSync(process.execPath,argv,{env,encoding:'utf8'});
 write(root+'/reader-result.json',JSON.stringify({argv:[process.execPath,...argv],rc:r.status,signal:r.signal,stdout:r.stdout,stderr:r.stderr}));
 assert.equal(r.status,0,r.stderr);const result=JSON.parse(r.stdout);
 assert.equal(result.compiler_host_tuple,'linux_x86_64_cjnative');assert.equal(result.runtime_tuple,'windows_x86_64_cjnative');
 assert.equal(result.cjc,sdk+'/bin/cjc');assert.equal(result.std_core,sdk+'/lib/windows_x86_64_cjnative/libcangjie-std-core.a');
 console.log('CROSS_LAYOUT_HOST_TARGET_READER_TARGET');
});

test('explicit source plan controls language gating and child host without changing caller environment',async()=>{
 const {baseEnv}=await import('../srcbuild/stages/common.mjs');
 const root=fs.mkdtempSync(path.join(process.env.RELEASE_EVIDENCE_TEST_ROOT||os.tmpdir(),'selected-host-'));
 const chosen=root+'/chosen',stale=root+'/stale',macro=root+'/macro';fs.mkdirSync(chosen);
 const config={...buildConfig({workspace:root,officialSdkRoot:stale}),selection:{bootstrapHost:{install:chosen}}};
 for(const env of [{PATH:process.env.PATH},{PATH:process.env.PATH,CJCJ_SRCBUILD_HOST_SDK:stale,STDX_HOST_CANGJIE_HOME:macro}]){
  const before={...env};assert.equal(gcUnitLanguageGateEnabled(config,env),true);
  const child=baseEnv(config,env);assert.equal(child.CJCJ_SRCBUILD_HOST_SDK,chosen);assert.equal(child.STDX_HOST_CANGJIE_HOME,env.STDX_HOST_CANGJIE_HOME);assert.deepEqual(env,before);
 }
 for(const targetKey of ['windows-x64','darwin-x64'])assert.equal(gcUnitLanguageGateEnabled({...buildConfig({targetKey}),selection:config.selection},{}),false);
});

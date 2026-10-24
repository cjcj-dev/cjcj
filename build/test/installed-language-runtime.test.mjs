// Public installed entry with fixed runtime gate/readers. Native compilation and
// language payloads are finite recorders; this is not an SDK qualification.
import fs from 'node:fs';import path from 'node:path';import os from 'node:os';
import test from 'node:test';import assert from 'node:assert/strict';import {spawnSync} from 'node:child_process';
import {directSource,directBuild,write} from '../../ci/fixtures/runtime-direct-inputs.mjs';
import {buildConfig} from '../lib/config.mjs';
import {installGcUnitInputs} from '../srcbuild/gc-unit-gate.mjs';
const tuple='linux_x86_64_cjnative',entry=new URL('../../ci/bootstrap/sdk-installed-language.mjs',import.meta.url).pathname;
function fixture(name,recipe=null,platform='linux_x86_64') {
 const tuple=platform+'_cjnative',targetKey=platform==='linux_aarch64'?'linux-aarch64':'linux-x64';
 const root=fs.mkdtempSync(path.join(process.env.RELEASE_EVIDENCE_TEST_ROOT||os.tmpdir(),'direct-'+name+'-'));
 const source=path.join(root,'source'),runtime=source+'/runtime',sdk=root+'/sdk',host=root+'/host';
 directSource(runtime);directBuild(runtime);
 const compiler='#!'+process.execPath+'\nconsole.log("finite compiler recorder");\n';
 write(sdk+'/bin/cjc',compiler,0o755);write(host+'/bin/cjc',compiler,0o755);
 for(const prefix of [sdk,host,sdk+'/.host'])write(prefix+'/runtime/lib/'+tuple+'/libcangjie-runtime.so','finite runtime '+prefix);
 write(sdk+'/runtime/lib/'+tuple+'/libboundscheck.so','finite bounds');write(sdk+'/lib/'+tuple+'/libcangjie-std-core.a','finite std');
 if(recipe){fs.unlinkSync(sdk+'/bin/cjc');write(sdk+'/libexec/compiler/cjcj-stage1',compiler,0o755);write(sdk+'/bin/cjcj-stage1',compiler,0o755);fs.symlinkSync('cjcj-stage1',sdk+'/bin/cjc');write(sdk+'/bin/cjcj-stage1.entry',['cjcj-sdk-entry-v1','1','libexec/compiler/cjcj-stage1','linux','native-target',recipe].join('\n')+'\n');}
 if(name==='defer') {
  fs.unlinkSync(runtime+'/CMakebuild/gc-unit.status');
  const argv=['bash',runtime+'/tests/gc_unit/gate_gc_unit.sh'],env={...process.env,GC_UNIT_GATE_CONTRACT_SELFTEST:'1',GC_UNIT_GATE_SKIP:'0',GC_UNIT_GATE_LANGUAGE_TESTS:'defer',MRT_TESTABLE_INTERNALS:'0',GCV2_RUNTIME_LIB_DIR:sdk+'/runtime/lib/'+tuple,GCV2_RUNTIME_BUILD_DIR:runtime+'/CMakebuild',GCV2_RUNTIME_OUTPUT_ROOT:runtime+'/CMakebuild/runtime-staging',GC_UNIT_GATE_STATUS:runtime+'/CMakebuild/gc-unit.status',GC_UNIT_OUT:root+'/defer'};
  const r=spawnSync(argv[0],argv.slice(1),{env,encoding:'utf8'});write(root+'/defer-command.json',JSON.stringify({argv,rc:r.status,signal:r.signal}));write(root+'/defer.stdout',r.stdout);write(root+'/defer.stderr',r.stderr);assert.equal(r.status,0,r.stderr);
  assert.match(fs.readFileSync(runtime+'/CMakebuild/gc-unit.status','utf8'),/CPP_SUITE=PASS/);
 }
 write(sdk+'/share/runtime-build/retired-publication','stale old installation');
 installGcUnitInputs(buildConfig({targetKey}),runtime,sdk);
 assert.equal(fs.existsSync(sdk+'/share/runtime-build/retired-publication'),false);
 const trace=root+'/trace.jsonl';let count=0;
 // Layout-only apparatus: preserve the product native-host check. No ARM ELF
 // runs; only this public Node caller gets an ARM host, child readers retain the
 // real machine arch and must consume the explicit tuple from the caller.
 const layoutHost=platform==='linux_aarch64'?root+'/layout-host.mjs':null;
 if(layoutHost){
  const dependency=buildConfig({targetKey}).target.spec.opensslLibDir,layoutDependency=root+'/layout-platform-dependency';fs.mkdirSync(layoutDependency);
  write(layoutHost,`import fs from 'node:fs';console.error('CONTROLLED_LAYOUT_HOST arch='+process.arch+' -> arm64; dependency directory stat only; no ARM program execution');Object.defineProperty(process,'arch',{value:'arm64'});const stat=fs.statSync;fs.statSync=(file,...args)=>stat(file===${JSON.stringify(dependency)}?${JSON.stringify(layoutDependency)}:file,...args);\n`);
 }

 function run({extra={},explicit=false}={}) {
  const log=root+'/command-'+(++count),argv=[...(layoutHost?['--import',layoutHost]:[]),entry,'--sdk',sdk,'--platform',platform,'--host',host,'--work',root+'/work',...(explicit?['--runtime-source',sdk+'/share/runtime-build']:[])];
  const out=fs.openSync(log+'.stdout','wx'),err=fs.openSync(log+'.stderr','wx');
  const r=spawnSync(process.execPath,argv,{env:{...process.env,GC_UNIT_GATE_CONTRACT_SELFTEST:'1',GC_UNIT_GATE_SKIP:'0',MRT_TESTABLE_INTERNALS:'0',DIRECT_TRACE:trace,...extra},stdio:['ignore',out,err]});fs.closeSync(out);fs.closeSync(err);
  write(log+'.json',JSON.stringify({argv:[process.execPath,...argv],rc:r.status,signal:r.signal,error:r.error?.message}));
  return {...r,stderr:fs.readFileSync(log+'.stderr','utf8'),stdout:fs.readFileSync(log+'.stdout','utf8')};
 }
 return {root,source,runtime,sdk,host,trace,run,tuple,platform,rows:()=>fs.existsSync(trace)?fs.readFileSync(trace,'utf8').trim().split('\n').map(JSON.parse):[]};
}
test('public direct language defaults and explicit inputs execute again after completed status',()=>{
 const f=fixture('reentry');for(const explicit of [false,true,false]){const r=f.run({explicit});assert.equal(r.status,0,r.stderr);}
 assert.deepEqual(f.rows().map(x=>x.kind),['FINALIZER','PHASE','FINALIZER','PHASE','FINALIZER','PHASE']);
 const r=f.run({extra:{DIRECT_PHASE_FAIL:'7'}});assert.notEqual(r.status,0);assert.match(r.stderr,/PHASE_ENTRY_FAILURE rc=7/);
 assert.match(fs.readFileSync(f.sdk+'/runtime/lib/'+tuple+'/gc_unit_gate.status','utf8'),/GATE=FAIL/);
 const restored=f.run();assert.equal(restored.status,0,restored.stderr);console.log('DIRECT_REENTRY_LANGUAGE_ASSERTION_REACHED');
});
for(const [label,recipe,selected]of [['source',null,'host'],['transitional','.host/runtime/lib/'+tuple,'sdk/.host'],['final','runtime/lib/'+tuple,'sdk']])
 test('public direct language uses the '+label+' compiler runtime domain',()=>{
 const f=fixture(label,recipe),r=f.run();assert.equal(r.status,0,r.stderr);
 const env=f.rows()[0].env;assert.equal(env.GC_UNIT_CJC_RUNTIME_LIB_DIR,f.root+'/'+selected+'/runtime/lib/'+tuple);
 assert.equal(env.GCV2_RUNTIME_LIB_DIR,f.sdk+'/runtime/lib/'+tuple);
 assert.equal(env.GCV2_RUNTIME_OUTPUT_ROOT,f.sdk+'/runtime');assert.equal(env.GC_UNIT_GATE_LANGUAGE_TESTS,'only');
 });
test('public direct language consumes a relocated installed input without its producer tree',()=>{
 const f=fixture('relocated');const archive=f.root+'/sdk.tar',moved=f.root+'/moved';fs.mkdirSync(moved);
 for(const args of [['-cf',archive,'-C',f.sdk,'.'],['-xf',archive,'-C',moved]])assert.equal(spawnSync('tar',args).status,0);
 fs.renameSync(f.source,f.source+'.unavailable');fs.renameSync(f.sdk,f.sdk+'.old');fs.renameSync(moved,f.sdk);
 const before=fs.readFileSync(f.sdk+'/runtime/lib/'+tuple+'/libcangjie-runtime.so');
 const r=f.run();assert.equal(r.status,0,r.stderr);assert.deepEqual(fs.readFileSync(f.sdk+'/runtime/lib/'+tuple+'/libcangjie-runtime.so'),before);
 assert.equal(fs.existsSync(f.sdk+'/share/runtime-build/runtime/tests/gc_unit/language_toolchain.mjs'),true);
 console.log('DIRECT_RELOCATED_LANGUAGE_ASSERTION_REACHED');
});
for(const [name,member]of [['native-result','share/runtime-build/runtime/CMakebuild/gc-unit.status'],['generated-header','runtime/include/schedule.h'],['configuration','share/runtime-build/runtime/CMakebuild/compile_commands.json'],['mjs-reader','share/runtime-build/runtime/tests/gc_unit/language_toolchain.mjs'],['std-core','lib/'+tuple+'/libcangjie-std-core.a'],['bounds','runtime/lib/'+tuple+'/libboundscheck.so']])
 test('public direct language rejects missing '+name,()=>{
 const f=fixture(name);fs.renameSync(f.sdk+'/'+member,f.sdk+'/'+member+'.saved');const r=f.run();assert.notEqual(r.status,0,r.stderr);assert.equal(f.rows().length,0);console.log('DIRECT_MISSING_INPUT_ASSERTION_REACHED '+name);
 });
test('public direct language rejects a failed native CPP result independently',()=>{
 const f=fixture('cpp-control');const file=f.sdk+'/share/runtime-build/runtime/CMakebuild/gc-unit.status';write(file,fs.readFileSync(file,'utf8').replace('CPP_SUITE=PASS','CPP_SUITE=FAIL'));
 const r=f.run();assert.notEqual(r.status,0);assert.match(r.stderr,/native CPP result required/);assert.equal(f.rows().length,0);console.log('DIRECT_CPP_CONTROL_ASSERTION_REACHED');
});

test('public normal defer runs before installed only-language',()=>{const f=fixture('defer');const r=f.run();assert.equal(r.status,0,r.stderr);assert.deepEqual(f.rows().map(row=>row.kind),['FINALIZER','PHASE']);console.log('DIRECT_DEFER_ONLY_ASSERTION_REACHED');});

for(const recipe of [null,'.host/runtime/lib/linux_aarch64_cjnative','runtime/lib/linux_aarch64_cjnative'])
 test('public AArch64 language keeps target std and compiler host '+(recipe||'source'),()=>{
 const f=fixture('arm',recipe,'linux_aarch64');
 assert.equal(fs.existsSync(f.sdk+'/lib/linux_x86_64_cjnative'),false);
 for(const explicit of [false,true]){const r=f.run({explicit});assert.equal(r.status,0,'ARM_SELECTED_INPUT_TARGET '+r.stderr);}
 for(const row of f.rows()){
  assert.equal(row.env.GC_UNIT_RUNTIME_TUPLE,f.tuple);assert.equal(row.env.GC_UNIT_CJC_RUNTIME_TUPLE,f.tuple);
  assert.ok(row.env.GC_UNIT_CJC_RUNTIME_LIB_DIR.endsWith('/'+f.tuple));
 }
 assert.deepEqual(f.rows().map(x=>x.kind),['FINALIZER','PHASE','FINALIZER','PHASE']);
 console.log('ARM_SELECTED_INPUT_TARGET');
 });
test('public AArch64 language relocation keeps selection and refuses an x86 std substitute',()=>{
 const f=fixture('arm-moved',null,'linux_aarch64'),archive=f.root+'/sdk.tar',moved=f.root+'/unpacked';fs.mkdirSync(moved);
 for(const args of [['-cf',archive,'-C',f.sdk,'.'],['-xf',archive,'-C',moved]])assert.equal(spawnSync('tar',args).status,0);
 fs.renameSync(f.source,f.source+'.unavailable');fs.renameSync(f.sdk,f.sdk+'.old');fs.renameSync(moved,f.sdk);
 for(const explicit of [false,true]){const r=f.run({explicit});assert.equal(r.status,0,r.stderr);}
 const std=f.sdk+'/lib/'+f.tuple+'/libcangjie-std-core.a';fs.renameSync(std,std+'.saved');
 write(f.sdk+'/lib/linux_x86_64_cjnative/libcangjie-std-core.a','wrong architecture substitute');
 const count=f.rows().length,bad=f.run();assert.notEqual(bad.status,0);assert.match(bad.stderr,/linux_aarch64_cjnative.*libcangjie-std-core/);assert.equal(f.rows().length,count);
 fs.renameSync(std+'.saved',std);const restored=f.run();assert.equal(restored.status,0,restored.stderr);
 console.log('ARM_RELOCATED_STD_CONTROL_TARGET');
});
test('public native language wrong host tuple stays rejected independently',()=>{
 const f=fixture('wrong-host'),dir=f.host+'/runtime/lib/'+tuple,wrong=f.host+'/runtime/lib/linux_aarch64_cjnative';
 fs.renameSync(dir,wrong);fs.symlinkSync('linux_aarch64_cjnative',dir);
 const bad=f.run();assert.notEqual(bad.status,0);assert.match(bad.stderr,/runtime directory tuple mismatch/);assert.equal(f.rows().length,0);
 console.log('WRONG_HOST_TUPLE_CONTROL_TARGET');
});
for(const platform of ['linux_x86_64','linux_aarch64'])test('public release gate uses fixed reader for '+platform,()=>{
 const f=fixture('release-reader',null,platform),active=f.root+'/release';
 const args=[new URL('../../ci/release/gate_colour_runtime.mjs',import.meta.url).pathname,f.source,f.sdk,active,f.sdk];
 const out=fs.openSync(f.root+'/release.stdout','wx'),err=fs.openSync(f.root+'/release.stderr','wx');
 const r=spawnSync(process.env.ZX||'zx',args,{env:{...process.env,PLATFORM_TUPLE:platform,GC_UNIT_GATE_CONTRACT_SELFTEST:'1',GC_UNIT_GATE_SKIP:'0',MRT_TESTABLE_INTERNALS:'0',DIRECT_TRACE:f.trace},stdio:['ignore',out,err]});fs.closeSync(out);fs.closeSync(err);
 write(f.root+'/release-command.json',JSON.stringify({argv:[process.env.ZX||'zx',...args],rc:r.status,signal:r.signal}));
 assert.equal(r.status,0,fs.readFileSync(f.root+'/release.stderr','utf8'));
 assert.match(fs.readFileSync(active+'/gate.status','utf8'),/LANGUAGE_TESTS=LANGUAGE_DONE/);
 assert.ok(f.rows().some(x=>x.kind==='FINALIZER'));assert.ok(f.rows().some(x=>x.kind==='PHASE'));
 for(const row of f.rows().filter(x=>x.kind==='FINALIZER'||x.kind==='PHASE')){assert.equal(row.env.GC_UNIT_RUNTIME_TUPLE,f.tuple);assert.equal(row.env.GC_UNIT_CJC_RUNTIME_TUPLE,f.tuple);}
 console.log('RELEASE_FIXED_READER_TARGET '+platform);
});

test('public installed language explicit host overrides stale outer source-build selections',()=>{
 const f=fixture('explicit-host');const r=f.run({extra:{CJCJ_OFFICIAL_SDK_ROOT:f.root+'/stale-official',CJCJ_SRCBUILD_HOST_SDK:f.root+'/stale-source'}});
 assert.equal(r.status,0,r.stderr);assert.deepEqual(f.rows().map(row=>row.kind),['FINALIZER','PHASE']);
 for(const row of f.rows())assert.equal(row.env.GC_UNIT_CJC_RUNTIME_LIB_DIR,f.host+'/runtime/lib/'+tuple);
 console.log('INSTALLED_EXPLICIT_HOST_ASSERTION_REACHED');
});

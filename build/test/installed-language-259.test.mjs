// Fixed 259 installation/CLI wiring. Small native symbol fixtures and compiler
// recorders are explicit boundaries, not R/S or language ABI qualification.
import fs from 'node:fs';import path from 'node:path';import os from 'node:os';
import test from 'node:test';import assert from 'node:assert/strict';import {spawnSync} from 'node:child_process';
import {directSource,directBuild,write} from '../../ci/fixtures/runtime-direct-inputs.mjs';
import {buildConfig} from '../lib/config.mjs';
import {installGcUnitInputs} from '../srcbuild/gc-unit-gate.mjs';
import {languageSourceInputs} from '../srcbuild/installed-language-source.mjs';
const fixed=JSON.parse(fs.readFileSync(new URL('../../ci/platform_matrix/fixtures/runtime-language-259.json',import.meta.url)));
const tuple='linux_x86_64_cjnative',entry=new URL('../../ci/bootstrap/sdk-installed-language.mjs',import.meta.url).pathname;
function fixture(label,{payloads=true,testable=false,reentry=false}={}) {
  const root=fs.mkdtempSync(path.join(process.env.RELEASE_EVIDENCE_TEST_ROOT||os.tmpdir(),'language259-'+label+'-'));
  const runtime=root+'/source/runtime',sdk=root+'/sdk',host=root+'/host',unit=runtime+'/tests/gc_unit';
  directSource(runtime);directBuild(runtime);
  for(const member of ['tests/gc_unit/gate_gc_unit.mjs','tests/gc_unit/language_toolchain.mjs',
    'tests/gc_unit/product_test_configuration.mjs','build/resolve_runtime_headers.mjs'])fs.unlinkSync(runtime+'/'+member);
  for(const [member,text] of Object.entries(fixed.files))write(runtime+'/'+member,text);
  const hooks=`typedef decltype(sizeof(0)) size_t;\nnamespace MapleRuntime { struct Probe {static void One();static void Two();static void Three();static void Four();};\n#ifdef MRT_TESTABLE_INTERNALS\nvoid Probe::One() {}\nvoid Probe::Two() {}\nvoid Probe::Three() {}\nvoid Probe::Four() {}\nsize_t ZFailLargerCommits=0;\n#endif\n}\n`;
  write(runtime+'/src/hooks.cpp',hooks);
  const source=hooks+(reentry?'extern "C" {void CJ_CJThreadStackGuardExpand(){} void CJ_CJThreadStackGuardRecover(){} void CJ_CJThreadStackGuardGet(){}}':'');
  const library=root+'/libfixture.so';const cc=spawnSync('c++',['-shared','-fPIC',...(testable?['-DMRT_TESTABLE_INTERNALS']:[]),'-x','c++','-','-o',library],{input:source,encoding:'utf8'});
  write(root+'/fixture-compile.json',JSON.stringify({rc:cc.status,signal:cc.signal,stderr:cc.stderr}));assert.equal(cc.status,0,cc.stderr);
  for(const base of [sdk,host]){const dir=base+'/runtime/lib/'+tuple;fs.mkdirSync(dir,{recursive:true});fs.copyFileSync(library,dir+'/libcangjie-runtime.so');}
  write(sdk+'/runtime/lib/'+tuple+'/libboundscheck.so','finite bounds');write(sdk+'/lib/'+tuple+'/libcangjie-std-core.a','finite std');
  const compiler='#!'+process.execPath+'\nif(process.env.DIRECT_COMPILER_FAIL)process.exit(Number(process.env.DIRECT_COMPILER_FAIL));\n';
  write(sdk+'/bin/cjc',compiler,0o755);write(host+'/bin/cjc',compiler,0o755);
  write(runtime+'/CMakebuild/compile_commands.json',JSON.stringify([{file:'/selected/runtime/src/Heap/z/zGeneration.cpp',arguments:['clang++',...(testable?['-DMRT_TESTABLE_INTERNALS']:[])]}]));
  write(runtime+'/CMakebuild/gc-unit.status','GATE=PASS\nGATE_RC=0\nCPP_SUITE=PASS\nLANGUAGE_TESTS=LANGUAGE_DEFERRED\nSEGMENTED_ARRAY_MANAGED_CAN_RUN='+(testable?'1':'0')+'\nEVIDENCE_DIR='+root+'/native-cpp\n');
  if(testable)write(root+'/native-cpp/cj_gc_unit','#!'+process.execPath+'\nconsole.log("finite original CPP ELF boundary");\n',0o755);
  if(payloads) {
    write(unit+'/payload.mjs',`import fs from 'node:fs';fs.appendFileSync(process.env.DIRECT_TRACE,JSON.stringify({kind:process.argv[2],args:process.argv.slice(3)})+'\\n');if(process.argv[2]==='PHASE'&&process.env.DIRECT_PHASE_FAIL)process.exit(Number(process.env.DIRECT_PHASE_FAIL));\n`);
    for(const [member,kind,calls] of [['run_finalizer_trigger.sh','FINALIZER',1],['run_phase_entry_trigger.sh','PHASE',2],['run_segmented_array_managed.sh','SEGMENTED',1]]) {
      write(unit+'/'+member,'#!/usr/bin/env bash\nset -euo pipefail\nsource "$(dirname "$0")/language_toolchain.sh"\ngc_unit_language_admit\ngc_unit_language_environment\nSDK_RUNTIME="${CANGJIE_HOME:-}/runtime/lib/linux_x86_64_cjnative"\n'+
        'gc_unit_language_compile finite-input\n'.repeat(calls)+'exec '+JSON.stringify(process.execPath)+' "$(dirname "$0")/payload.mjs" '+kind+' "$@"\n',0o755);
    }
    write(unit+'/run_so_reentry_bounded.sh','#!/usr/bin/env bash\nexec '+JSON.stringify(process.execPath)+' "$(dirname "$0")/payload.mjs" SO\n',0o755);
  }
  const config=buildConfig({targetKey:'linux-x64'}),trace=root+'/trace.jsonl';let count=0;
  function install(){return installGcUnitInputs(config,runtime,sdk);}
  function run(extra={}) {
    const args=[entry,'--sdk',sdk,'--host',host,'--platform','linux_x86_64','--work',root+'/work'];
    const r=spawnSync(process.execPath,args,{env:{...process.env,DIRECT_TRACE:trace,...extra},encoding:'utf8'}),log=root+'/run-'+(++count);
    write(log+'.stdout',r.stdout);write(log+'.stderr',r.stderr);write(log+'.json',JSON.stringify({argv:[process.execPath,...args],rc:r.status,signal:r.signal}));return r;
  }
  return {root,runtime,sdk,host,unit,install,run,rows:()=>fs.existsSync(trace)?fs.readFileSync(trace,'utf8').trim().split('\n').map(JSON.parse):[]};
}
test('fixed 259 scripts are installed with only reader/compiler wiring substitutions',()=>{
  const f=fixture('source',{payloads:false});const originals=Object.fromEntries(Object.keys(fixed.files).map(member=>[member,fs.readFileSync(f.runtime+'/'+member,'utf8')]));
  f.install();const carried=f.sdk+'/share/runtime-build/runtime';
  assert.equal(fs.existsSync(carried+'/tests/gc_unit/gate_gc_unit.mjs'),false);
  languageSourceInputs(carried,{installed:true});
  for(const [member,text] of Object.entries(originals))assert.equal(fs.readFileSync(f.runtime+'/'+member,'utf8'),text,'producer changed '+member);
  for(const member of ['run_finalizer_trigger.sh','run_phase_entry_trigger.sh','run_segmented_array_managed.sh']) {
    const before=originals['tests/gc_unit/'+member],after=fs.readFileSync(carried+'/tests/gc_unit/'+member,'utf8');
    assert.ok(after.includes('installed-language-inputs.mjs'));
    // Every line after preparation, except compiler invocation and tuple input,
    // must remain the selected source's original assertion/command body.
    const body=text=>text.split(/gc_unit_language_environment\n|eval "\$LANGUAGE_INPUT_SHELL"\n/)[1]
      .replaceAll('zx "$(dirname "$0")/installed-language-inputs.mjs" --compile','gc_unit_language_compile')
      .replace('SDK_RUNTIME="${GC_UNIT_SDK_RUNTIME_DIR:?}"','SDK_RUNTIME="${CANGJIE_HOME:-}/runtime/lib/linux_x86_64_cjnative"');
    assert.equal(body(after),body(before));
  }
  assert.equal(fs.readFileSync(carried+'/tests/gc_unit/run_so_reentry_bounded.sh','utf8'),originals['tests/gc_unit/run_so_reentry_bounded.sh']);
});
test('259 public installed CLI reaches both mandatory payloads and preserves compiler/phase failure and recovery',()=>{
  const f=fixture('public');f.install();const first=f.run();assert.equal(first.status,0,first.stderr);
  assert.deepEqual(f.rows().map(row=>row.kind),['FINALIZER','PHASE'],'INSTALLED_259_PHASE_DISPATCH_TARGET');
  const compiler=f.run({DIRECT_COMPILER_FAIL:'9'});assert.equal(compiler.status,9,compiler.stderr);assert.match(compiler.stderr,/FINALIZER_FAILURE rc=9/);
  const phase=f.run({DIRECT_PHASE_FAIL:'7'});assert.equal(phase.status,7,phase.stderr);assert.match(phase.stderr,/PHASE_ENTRY_FAILURE rc=7/);
  const restored=f.run();assert.equal(restored.status,0,restored.stderr);
});
test('259 installed archive runs without producer and refuses missing std independently',()=>{
  const f=fixture('relocated');f.install();const archive=f.root+'/sdk.tar',moved=f.root+'/moved';fs.mkdirSync(moved);
  for(const argv of [['-cf',archive,'-C',f.sdk,'.'],['-xf',archive,'-C',moved]])assert.equal(spawnSync('tar',argv).status,0);
  fs.renameSync(f.runtime,f.runtime+'.unavailable');fs.renameSync(f.sdk,f.sdk+'.old');fs.renameSync(moved,f.sdk);
  const good=f.run();assert.equal(good.status,0,good.stderr);
  const std=f.sdk+'/lib/'+tuple+'/libcangjie-std-core.a';fs.renameSync(std,std+'.saved');
  const bad=f.run();assert.notEqual(bad.status,0);assert.match(bad.stderr,/libcangjie-std-core/);assert.equal(f.rows().length,2);
  fs.renameSync(std+'.saved',std);assert.equal(f.run().status,0);
});
test('259 symbol-selected consumers retain SO and both segmented windows and the actual CPP producer input',()=>{
  const f=fixture('symbols',{testable:true,reentry:true});f.install();const elf=f.sdk+'/share/runtime-build/runtime/CMakebuild/cj_gc_unit';
  assert.deepEqual(fs.readFileSync(elf),fs.readFileSync(f.root+'/native-cpp/cj_gc_unit'));
  const r=f.run();assert.equal(r.status,0,r.stderr);assert.deepEqual(f.rows().map(row=>[row.kind,...row.args]),[['FINALIZER'],['PHASE'],['SO'],['SEGMENTED','both']]);
  fs.renameSync(elf,elf+'.saved');const missing=f.run();assert.notEqual(missing.status,0);assert.match(missing.stderr,/cj_gc_unit/);
  fs.renameSync(elf+'.saved',elf);assert.equal(f.run().status,0);
});

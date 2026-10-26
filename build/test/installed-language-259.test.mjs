// Fixed 259 installation/CLI wiring. Small native symbol fixtures and compiler
// recorders are explicit boundaries, not R/S or language ABI qualification.
import fs from 'node:fs';import path from 'node:path';import os from 'node:os';
import test from 'node:test';import assert from 'node:assert/strict';import {spawnSync} from 'node:child_process';
import {directSource,directBuild,write} from '../../ci/fixtures/runtime-direct-inputs.mjs';
import {buildConfig} from '../lib/config.mjs';
import {installGcUnitInputs,assertGcUnitLanguageDone,assertGcUnitLanguageDeferred,gcUnitStatusPath} from '../srcbuild/gc-unit-gate.mjs';
import {completedGcUnitGate} from '../srcbuild/installed-language-inputs.mjs';
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
  // The symbol fixture has its own five hooks; it does not claim the real GC
  // source/ELF pairing represented by the separate modern-source fixture.
  fs.rmSync(runtime+'/src',{recursive:true});
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
  directBuild(runtime);
  const nativeStatus=runtime+'/CMakebuild/gc-unit.status';
  write(nativeStatus,fs.readFileSync(nativeStatus,'utf8').replace('SEGMENTED_ARRAY_MANAGED_CAN_RUN=0','SEGMENTED_ARRAY_MANAGED_CAN_RUN='+(testable?'1':'0'))+'EVIDENCE_DIR='+root+'/native-cpp\n');
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
  return {root,runtime,sdk,host,unit,config,trace,install,run,rows:()=>fs.existsSync(trace)?fs.readFileSync(trace,'utf8').trim().split('\n').map(JSON.parse):[]};
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

test('legacy installed entry refuses missing or failed CPP exit and unknown status schema',()=>{
 const f=fixture('status');const file=f.runtime+'/CMakebuild/gc-unit.status',original=fs.readFileSync(file,'utf8');
 for(const [label,text] of [['missing',original.replace('CPP_RUNNER_RC=0\n','')],['failed',original.replace('CPP_RUNNER_RC=0','CPP_RUNNER_RC=1')],['schema',original.replace('SCHEMA_VERSION=1','SCHEMA_VERSION=9')],['contradiction',original+'GATE_RC=1\n']]){
  write(file,text);assert.throws(()=>f.install(),/current native gate did not complete/,label);
 }
 write(file,original);f.install();
 const carried=f.sdk+'/share/runtime-build/runtime/CMakebuild/gc-unit.status';
 write(carried,original.replace('CPP_RUNNER_RC=0','CPP_RUNNER_RC=1'));
 const bad=f.run();assert.equal(bad.status,1);assert.match(bad.stderr,/native CPP result required/);assert.equal(f.rows().length,0);
 write(carried,original);const restored=f.run();assert.equal(restored.status,0,restored.stderr);
 console.log('LEGACY_INSTALLED_STATUS_RECOVERY_TARGET_REACHED');
});


// The retained 259 gate is byte-identical to R5ca1's gate_gc_unit.sh. Execute
// that producer unchanged; only native/language payloads and prerequisite
// discovery are finite, explicit process fixtures. Its write_status is real.
function legacyProducer(f,mode,{testable=false,reentry=false}={}) {
 const saved=Object.fromEntries(['language_toolchain.sh','run_standalone.sh','run_finalizer_trigger.sh','run_phase_entry_trigger.sh','run_so_reentry_bounded.sh','run_segmented_array_managed.sh']
  .map(name=>[name,fs.readFileSync(f.unit+'/'+name)]));
 const bridge=f.unit+'/producer-prerequisites.mjs';
 write(bridge,`import fs from 'node:fs';const [kind,...args]=process.argv.slice(2);fs.appendFileSync(process.env.PRODUCER_TRACE,JSON.stringify({kind,args})+'\\n');if(kind==='configuration')console.log(${JSON.stringify((testable?'1':'0')+' 1 0 1')});\n`);
 for(const [file,kind] of [['gate_evidence.py','evidence'],['product_test_configuration.py','configuration']])
  write(f.unit+'/'+file,`import os,sys\nos.execv(${JSON.stringify(process.execPath)},[${JSON.stringify(process.execPath)},${JSON.stringify(bridge)},${JSON.stringify(kind)}]+sys.argv[1:])\n`);
 write(f.unit+'/language_toolchain.sh',`gc_unit_language_admit(){ export GC_UNIT_LANGUAGE_SDK="$FINITE_SDK"; export GC_UNIT_LANGUAGE_IDENTITY=finite-language-payload; return 0; }\ngc_unit_language_environment(){ :; }\n`);
 write(f.unit+'/producer-payload.mjs',`import fs from 'node:fs';const kind=process.argv[2];fs.appendFileSync(process.env.PRODUCER_TRACE,JSON.stringify({kind})+'\\n');if(kind==='CPP')fs.writeFileSync(process.env.GC_UNIT_TALLY_FILE,'[========] 1 tests: 1 passed, 0 failed\\n');\n`);
 for(const [name,kind] of [['run_standalone.sh','CPP'],['run_finalizer_trigger.sh','FINALIZER'],['run_phase_entry_trigger.sh','PHASE'],['run_so_reentry_bounded.sh','SO'],['run_segmented_array_managed.sh','SEGMENTED']])
  write(f.unit+'/'+name,'#!/usr/bin/env bash\n# test_x.cpp\nexec '+JSON.stringify(process.execPath)+' "$(dirname "$0")/producer-payload.mjs" '+kind+'\n',0o755);
 const status=f.runtime+'/CMakebuild/gc-unit.status',env={...process.env,GC_UNIT_GATE_CONTRACT_SELFTEST:'1',GC_UNIT_GATE_SKIP:'0',MRT_TESTABLE_INTERNALS:testable?'1':'0',
  GCV2_RUNTIME_LIB_DIR:f.sdk+'/runtime/lib/'+tuple,GCV2_RUNTIME_OUTPUT_ROOT:f.runtime+'/CMakebuild/runtime-staging',GC_UNIT_GATE_STATUS:status,
  GC_UNIT_OUT:f.root+'/producer',FINITE_SDK:f.sdk,PRODUCER_TRACE:f.root+'/producer-processes.jsonl'};
 delete env.GCV2_RUNTIME_CONFIG;delete env.GC_UNIT_GATE_LANGUAGE_TESTS;
 if(mode!==undefined)env.GC_UNIT_GATE_LANGUAGE_TESTS=mode;
 const argv=['bash',f.unit+'/gate_gc_unit.sh'],r=spawnSync(argv[0],argv.slice(1),{env,encoding:'utf8'});
 write(f.root+'/producer.stdout',r.stdout);write(f.root+'/producer.stderr',r.stderr);
 write(f.root+'/producer-command.json',JSON.stringify({argv,mode:mode??'default',rc:r.status,signal:r.signal,error:r.error?.message}));
 for(const [name,bytes]of Object.entries(saved))fs.writeFileSync(f.unit+'/'+name,bytes);
 assert.equal(r.status,0,'SCHEMA1_REAL_PRODUCER '+r.stderr+'\n'+r.stdout);
 assert.equal(fs.readFileSync(f.unit+'/gate_gc_unit.sh','utf8'),fixed.files['tests/gc_unit/gate_gc_unit.sh']);
 return fs.readFileSync(status,'utf8');
}
for(const [label,mode,capabilities] of [['default-all',undefined,false],['explicit-all','all',true],['only','only',true],['defer','defer',true]])
 test('schema1 real producer '+label+' reaches complete consumers and rejects missing or contradictory obligations',()=>{
 const f=fixture('producer-'+label,{testable:capabilities,reentry:capabilities});
 const original=legacyProducer(f,mode,{testable:capabilities,reentry:capabilities});
 const parse=text=>new Map(text.trim().split('\n').map(line=>{const i=line.indexOf('=');return [line.slice(0,i),line.slice(i+1)];}));
 const selected=parse(original),format=fields=>[...fields].map(([key,value])=>key+'='+value).join('\n')+'\n';
 const status=gcUnitStatusPath(f.config,f.sdk),native=f.runtime+'/CMakebuild/gc-unit.status',env={CJCJ_SRCBUILD_HOST_SDK:f.host};
 const assertState=mode==='defer'?assertGcUnitLanguageDeferred:assertGcUnitLanguageDone;
 const consume=text=>{write(status,text);return assertState(f.config,f.sdk,{env});};
 assert.equal(completedGcUnitGate(selected),true,'SCHEMA1_VALID_'+label);consume(original);
 if(mode!=='only')f.install();else assert.throws(()=>f.install(),/current native gate did not complete/,'ONLY_IS_NOT_CPP');
 if(mode==='defer')assert.throws(()=>assertGcUnitLanguageDone(f.config,f.sdk,{env}),/LANGUAGE_DONE/,'DEFER_IS_NOT_LANGUAGE');
 const required=['SCHEMA_VERSION','GATE','PHASE','LANGUAGE_TEST_MODE','LANGUAGE_TESTS','CPP_SUITE','CPP_SUITE_SOURCE','CPP_RUNNER_RC',
  'OHOS_HOST','OHOS_HOST_SOURCE','OHOS_RUNNER_RC','OHOS_HOST_FILTERS','FINALIZER_TRIGGER','FINALIZER_TRIGGER_SOURCE','FINALIZER_RUNNER_RC',
  'PHASE_ENTRY_TRIGGER','PHASE_ENTRY_TRIGGER_SOURCE','PHASE_ENTRY_RUNNER_RC','SO_REENTRY_BOUNDED','SO_REENTRY_BOUNDED_SOURCE','SO_REENTRY_RUNNER_RC','SO_REENTRY_BOUNDED_CAN_RUN',
  'SEGMENTED_ARRAY_MANAGED','SEGMENTED_ARRAY_MANAGED_SOURCE','SEGMENTED_RUNNER_RC','SEGMENTED_ARRAY_MANAGED_CAN_RUN'];
 for(const key of required)for(const mutation of ['missing','failed']){
  const fields=new Map(selected);if(mutation==='missing')fields.delete(key);else fields.set(key,key.endsWith('_RC')?'1':'FAIL');
  const text=format(fields);assert.equal(completedGcUnitGate(fields),false,'SCHEMA1_OBLIGATION_TARGET '+label+' '+key+' '+mutation);
  assert.throws(()=>consume(text),/gate is not one exact PASS/,key+' '+mutation);
  if(mode!=='only'){write(native,text);assert.throws(()=>f.install(),/current native gate did not complete/,key+' '+mutation);}
 }
 for(const [key,value] of [['PHASE',mode==='defer'?'language':'cpp'],['LANGUAGE_TEST_MODE',mode==='defer'?'all':'defer'],['LANGUAGE_TESTS',mode==='defer'?'LANGUAGE_DONE':'LANGUAGE_DEFERRED'],['GATE_RC','1']]){
  const fields=new Map(selected);fields.set(key,value);assert.throws(()=>consume(format(fields)),/gate is not one exact PASS/,'SCHEMA1_CONTRADICTION '+key);
 }
 // The installed-only public entry must reject the same forged source record
 // before any language payload, rather than just relying on a direct predicate.
 if(mode!==undefined&&mode!=='only') {
  write(native,original);f.install();const carried=f.sdk+'/share/runtime-build/runtime/CMakebuild/gc-unit.status';
  const fields=new Map(selected);fields.set('FINALIZER_TRIGGER','FAIL');fields.set('FINALIZER_RUNNER_RC','1');write(carried,format(fields));
  const bad=f.run();assert.equal(bad.status,1);assert.match(bad.stderr,/native CPP result required/);assert.equal(f.rows().length,0);
  write(carried,original);const restored=f.run();assert.equal(restored.status,0,restored.stderr);
 }
 write(native,original);consume(original);if(mode!=='only')f.install();
 console.log('SCHEMA1_PRODUCER_OBLIGATIONS_RECOVERY_TARGET '+label+' conditional='+Number(capabilities));
 });

// Fixed runtime readers/gate; compilation and language payloads below are finite
// recorders, never runtime/SDK qualification. Retain originals in the test root.
import fs from 'node:fs';import path from 'node:path';
const legacyInputs=JSON.parse(fs.readFileSync(new URL('../platform_matrix/fixtures/runtime-language-259.json',import.meta.url)));
const inputs=JSON.parse(fs.readFileSync(new URL('../platform_matrix/fixtures/runtime-direct-inputs.json',import.meta.url)));
export const write=(file,text,mode)=>{fs.mkdirSync(path.dirname(file),{recursive:true});fs.writeFileSync(file,text,mode?{mode}:undefined);};
export function directSource(runtime,{legacy=false}={}) {
 for(const [name,text]of Object.entries(inputs.files))write(path.join(runtime,name),text);
 for(const directory of ['include','third_party/third_party_bounds_checking_function/include','tests/perf_vs_official'])write(path.join(runtime,directory,'fixture.h'),'// limited source transport\n');
 write(path.join(runtime,'CMakeLists.txt'),'# limited producer\n');
 const unit=path.join(runtime,'tests/gc_unit');
 for(const file of ['finalizer_trigger.cj','phase_entry_trigger.cj','phase_entry_major.cj','segmented_array_managed.cj','so_reentry_probe.cpp','test_defect_regressions.cpp'])write(path.join(unit,file),'// bounded language wiring payload\n');
 write(path.join(unit,'payload.mjs'),`import fs from 'node:fs';\nconst e=process.env,kind=process.argv[2];\nif(e.DIRECT_TRACE)fs.appendFileSync(e.DIRECT_TRACE,JSON.stringify({kind,env:Object.fromEntries(['GC_UNIT_RUNTIME_TUPLE','GC_UNIT_CJC_RUNTIME_TUPLE','GC_UNIT_CJC_RUNTIME_LIB_DIR','GCV2_RUNTIME_LIB_DIR','GCV2_RUNTIME_OUTPUT_ROOT','GCV2_RUNTIME_BUILD_DIR','GC_UNIT_GATE_LANGUAGE_TESTS','CANGJIE_HOME','CJC','PATH','LD_LIBRARY_PATH'].map(k=>[k,e[k]]))})+'\\n');\nif(kind==='CPP'){fs.writeFileSync(e.GC_UNIT_TALLY_FILE,'[========] 1 tests: 1 passed, 0 failed\\n');}\nif(kind==='PHASE'&&e.DIRECT_PHASE_FAIL)process.exit(Number(e.DIRECT_PHASE_FAIL));\n`);
 for(const [name,kind]of [['run_finalizer_trigger.sh','FINALIZER'],['run_phase_entry_trigger.sh','PHASE'],['run_so_reentry_bounded.sh','SO'],['run_segmented_array_managed.sh','SEGMENTED'],['run_standalone.sh','CPP'],['test_parallel_runner.sh','PARALLEL']])
  write(path.join(unit,name),'#!/usr/bin/env bash\n# test_x.cpp\nexec '+JSON.stringify(process.execPath)+' "$(dirname "$0")/payload.mjs" '+kind+'\n',0o755);
 if(legacy){
  for(const member of ['tests/gc_unit/gate_gc_unit.mjs','tests/gc_unit/language_toolchain.mjs','tests/gc_unit/product_test_configuration.mjs','build/resolve_runtime_headers.mjs'])fs.unlinkSync(path.join(runtime,member));
  for(const [member,text] of Object.entries(legacyInputs.files))write(path.join(runtime,member),text);
 }
 write(path.join(unit,'CMakeLists.txt'),'test_x.cpp\n');write(path.join(unit,'known_failures.txt'),'');
}
export function directBuild(runtime,{noStatus=false,cppFail=false}={}) {
 write(path.join(runtime,'CMakebuild/compile_commands.json'),JSON.stringify([{file:'/selected/runtime/src/Heap/z/zGeneration.cpp',arguments:['clang++','-DNDEBUG']}])+'\n');
 write(path.join(runtime,'CMakebuild/runtime-staging/include/schedule.h'),'// actual normal header location in limited producer\n');
 const legacy='SCHEMA_VERSION=1\nPHASE=cpp\nGATE=PASS\nCPP_RUNNER_RC=0\nCPP_SUITE_SOURCE=FRESH\nLANGUAGE_TEST_MODE=defer\n'
   +'OHOS_HOST=NOT_RUN\nOHOS_HOST_SOURCE=NOT_RUN\nOHOS_RUNNER_RC=NOT_RUN\nOHOS_HOST_FILTERS=0\n'
   +[['FINALIZER_TRIGGER','FINALIZER'],['PHASE_ENTRY_TRIGGER','PHASE_ENTRY'],['SO_REENTRY_BOUNDED','SO_REENTRY'],['SEGMENTED_ARRAY_MANAGED','SEGMENTED']]
     .map(([state,runner])=>state+'=NOT_RUN\n'+state+'_SOURCE=NOT_RUN\n'+runner+'_RUNNER_RC=NOT_RUN\n').join('')
   +'SO_REENTRY_BOUNDED_CAN_RUN=0\nSEGMENTED_ARRAY_MANAGED_CAN_RUN=0\n';
 if(!noStatus)write(path.join(runtime,'CMakebuild/gc-unit.status'),(fs.existsSync(path.join(runtime,'tests/gc_unit/gate_gc_unit.mjs'))?'GATE=PASS\nGATE_RC=0\n':legacy)+'CPP_SUITE='+(cppFail?'FAIL':'PASS')+'\nLANGUAGE_TESTS=LANGUAGE_DEFERRED\n');
}

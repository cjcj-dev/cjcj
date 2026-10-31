#!/usr/bin/env zx
// Installed-only continuation of the selected runtime's completed CPP gate.
// The four payload scripts and their assertions come from that runtime source.
import fs from 'node:fs';
import path from 'node:path';
import {fileURLToPath} from 'node:url';
import {spawnSync} from 'node:child_process';
import {languageInputs,completedGcUnitGate} from './installed-language-inputs.mjs';

const unit=path.dirname(fileURLToPath(import.meta.url)),runtime=path.resolve(unit,'../..');
const env={...process.env},root=env.GC_UNIT_OUT;
if(!root||!env.GC_UNIT_GATE_STATUS)throw Error('installed language output/status required');
fs.mkdirSync(root,{recursive:true});const out=fs.mkdtempSync(path.join(root,'language-'));
env.GC_UNIT_OUT=out;env.SIGNAL_TEST_OUTPUT=path.join(out,'so-reentry');
const result={GATE:'FAIL',GATE_RC:'NOT_RUN',LANGUAGE_TEST_MODE:'only',LANGUAGE_TESTS:'NOT_RUN',
  CPP_SUITE:'NOT_RUN',CPP_RUNNER_RC:'NOT_RUN',FINALIZER_RUNNER_RC:'NOT_RUN',PHASE_ENTRY_RUNNER_RC:'NOT_RUN',
  SO_REENTRY_RUNNER_RC:'NOT_RUN',SEGMENTED_RUNNER_RC:'NOT_RUN',EVIDENCE_DIR:out};
const records=[];
function fail(message,rc=2){throw Object.assign(Error(message),{rc});}
function file(name){if(!fs.statSync(name).isFile())fail('missing language input '+name);return name;}
function fields(name){const rows=new Map();for(const line of fs.readFileSync(name,'utf8').split(/\r?\n/)){
  const at=line.indexOf('=');if(at<1)continue;const key=line.slice(0,at);if(rows.has(key))fail('duplicate status '+key);rows.set(key,line.slice(at+1));}return rows;}
function run(name,argv) {
  const stdout=path.join(out,name+'.stdout'),stderr=path.join(out,name+'.stderr');
  const a=fs.openSync(stdout,'wx'),b=fs.openSync(stderr,'wx'),start=new Date().toISOString();let child;
  try{child=spawnSync(argv[0],argv.slice(1),{env,stdio:['ignore',a,b]});}finally{fs.closeSync(a);fs.closeSync(b);}
  const rc=child.status??(child.signal==='SIGTERM'?143:child.signal==='SIGKILL'?137:127);
  records.push({name,argv,start,end:new Date().toISOString(),rc:child.status,signal:child.signal,error:child.error?.message});
  fs.writeFileSync(path.join(out,'commands.json'),JSON.stringify(records,null,2)+'\n');
  return {rc,signal:child.signal,stdout:fs.readFileSync(stdout,'utf8'),stderr:fs.readFileSync(stderr,'utf8')};
}
function payload(name,member,args=[]) {
  const r=run(name,['bash',file(path.join(unit,member)),...args]);result[name+'_RUNNER_RC']=r.rc;
  if(r.rc)fail(name+'_FAILURE rc='+r.rc+' '+r.stderr,r.rc);
}
try {
  if(env.GC_UNIT_GATE_LANGUAGE_TESTS!=='only'||env.GC_UNIT_GATE_SKIP==='1')fail('installed language requires fresh only mode');
  const previous=fields(path.join(runtime,'CMakebuild/gc-unit.status'));
  if(!completedGcUnitGate(previous)||previous.get('CPP_SUITE')!=='PASS')fail('native CPP result required');
  result.CPP_SUITE='PASS';result.CPP_SUITE_SOURCE='NATIVE_PRODUCER';
  const inputs=languageInputs(env);env.CANGJIE_HOME=inputs.sdk;env.CJC=inputs.cjc;
  const headers=env.GCV2_RUNTIME_OUTPUT_ROOT;file(path.join(headers,'include/schedule.h'));
  const commands=JSON.parse(fs.readFileSync(path.join(runtime,'CMakebuild/compile_commands.json'),'utf8'));
  const rows=commands.filter(row=>row.file.replaceAll('\\','/').endsWith('/Heap/z/zGeneration.cpp'));
  if(rows.length!==1)fail('expected one zGeneration.cpp command');
  let args=rows[0].arguments;
  if(!args){const parsed=run('compile-arguments',['python3','-c','import json,shlex,sys; print(json.dumps(shlex.split(sys.argv[1])))',rows[0].command]);if(parsed.rc)fail(parsed.stderr,parsed.rc);args=JSON.parse(parsed.stdout);}
  const defined=name=>args.includes('-D'+name)||args.includes('-D'+name+'=1');
  if(defined('MRT_GC_UNIT_OHOS_HOST'))fail('installed native language cannot consume OHOS host configuration');
  const library=path.join(inputs.runtime_lib_dir,'libcangjie-runtime.so');
  const hooks=run('testable-hooks',['python3',file(path.join(unit,'testable_product_hooks.py')),'--source',path.join(runtime,'src'),'--so',library]);
  // A malformed source/checker is not the normal non-testable product case.
  if(hooks.rc&&(!hooks.stderr.includes('TESTABLE_PRODUCT_HOOK_MISSING=')||hooks.stderr.includes('TESTABLE_PRODUCT_HOOK_FAIL=')))fail(hooks.stderr,hooks.rc);
  if(hooks.rc&&(defined('MRT_TESTABLE_INTERNALS')||env.MRT_TESTABLE_INTERNALS==='1'))fail('testable product hooks missing');
  const symbols=run('runtime-symbols',['nm','--defined-only',library]);if(symbols.rc)fail(symbols.stderr,symbols.rc);
  const reentry=['CJ_CJThreadStackGuardExpand','CJ_CJThreadStackGuardRecover','CJ_CJThreadStackGuardGet']
    .every(name=>new RegExp('\\s'+name+'(?:@@?\\S+)?$','m').test(symbols.stdout));
  const segmented=hooks.rc===0;
  result.SO_REENTRY_BOUNDED_CAN_RUN=Number(reentry);result.SEGMENTED_ARRAY_MANAGED_CAN_RUN=Number(segmented);
  for(const member of ['run_finalizer_trigger.sh','finalizer_trigger.cj','run_phase_entry_trigger.sh','phase_entry_trigger.cj',
    'phase_entry_major.cj','run_so_reentry_bounded.sh','so_reentry_probe.cpp'])file(path.join(unit,member));
  if(segmented){file(path.join(unit,'segmented_array_managed.cj'));const elf=file(path.join(runtime,'CMakebuild/cj_gc_unit'));
    fs.accessSync(elf,fs.constants.X_OK);fs.copyFileSync(elf,path.join(out,'cj_gc_unit'));}
  result.LANGUAGE_TESTS='LANGUAGE_RUNNING';
  payload('FINALIZER','run_finalizer_trigger.sh');payload('PHASE_ENTRY','run_phase_entry_trigger.sh');
  if(reentry)payload('SO_REENTRY','run_so_reentry_bounded.sh');
  if(segmented)payload('SEGMENTED','run_segmented_array_managed.sh',['both']);
  result.LANGUAGE_TESTS='LANGUAGE_DONE';result.GATE='PASS';result.GATE_RC=0;
  console.log('GC_UNIT_GATE_LANGUAGE_OK mode=only status='+env.GC_UNIT_GATE_STATUS);
}catch(error){result.GATE_RC=error.rc||1;result.REASON=error.message.replaceAll('\n',' ');console.error(error.message);process.exitCode=result.GATE_RC;}
finally {
  fs.mkdirSync(path.dirname(env.GC_UNIT_GATE_STATUS),{recursive:true});
  const status=Object.entries(result).map(([key,value])=>key+'='+value).join('\n')+'\n';
  fs.writeFileSync(path.join(out,'gate.status'),status);fs.writeFileSync(env.GC_UNIT_GATE_STATUS,status);
}

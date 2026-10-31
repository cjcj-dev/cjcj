#!/usr/bin/env zx
// Read ordinary installed compiler/std/runtime inputs; no qualification receipt.
import fs from 'node:fs';
import path from 'node:path';
import {fileURLToPath} from 'node:url';
import {spawnSync} from 'node:child_process';

// gate_gc_unit.sh schema 1 records each phase separately: only does not run
// CPP, defer does not run language, and a cache hit has no fresh runner rc.
// The modern/installed producer instead publishes its aggregate GATE_RC.
export function completedGcUnitGate(fields) {
  if(fields.get('GATE')!=='PASS')return false;
  if(!fields.has('SCHEMA_VERSION'))return fields.get('GATE_RC')==='0';
  if(fields.get('SCHEMA_VERSION')!=='1'||(fields.has('GATE_RC')&&fields.get('GATE_RC')!=='0'))return false;
  const get=key=>fields.get(key), mode=get('LANGUAGE_TEST_MODE'), phase=get('PHASE');
  if(!['all','only','defer'].includes(mode))return false;
  const notRun=(state,source,rc)=>get(state)==='NOT_RUN'&&get(source)==='NOT_RUN'&&get(rc)==='NOT_RUN';
  const passed=(state,source,rc)=>get(state)==='PASS'
    && (get(source)==='FRESH'?get(rc)==='0':get(source)==='CACHE'&&get(rc)==='NOT_RUN');
  // The separate OHOS-host gate is not a native CPP/language completion.
  if(!notRun('OHOS_HOST','OHOS_HOST_SOURCE','OHOS_RUNNER_RC')||get('OHOS_HOST_FILTERS')!=='0')return false;
  if(mode==='only') {
    if(!notRun('CPP_SUITE','CPP_SUITE_SOURCE','CPP_RUNNER_RC'))return false;
  } else if(!passed('CPP_SUITE','CPP_SUITE_SOURCE','CPP_RUNNER_RC'))return false;
  const language=[['FINALIZER_TRIGGER','FINALIZER_TRIGGER_SOURCE','FINALIZER_RUNNER_RC'],
    ['PHASE_ENTRY_TRIGGER','PHASE_ENTRY_TRIGGER_SOURCE','PHASE_ENTRY_RUNNER_RC'],
    ['SO_REENTRY_BOUNDED','SO_REENTRY_BOUNDED_SOURCE','SO_REENTRY_RUNNER_RC','SO_REENTRY_BOUNDED_CAN_RUN'],
    ['SEGMENTED_ARRAY_MANAGED','SEGMENTED_ARRAY_MANAGED_SOURCE','SEGMENTED_RUNNER_RC','SEGMENTED_ARRAY_MANAGED_CAN_RUN']];
  if(language.some(([, , ,capability])=>capability&&!['0','1'].includes(get(capability))))return false;
  if(mode==='defer')return get('LANGUAGE_TESTS')==='LANGUAGE_DEFERRED'
    && language.every(([state,source,rc])=>notRun(state,source,rc))
    && (get('CPP_SUITE_SOURCE')==='FRESH'?phase==='cpp':['entry','contract'].includes(phase));
  if(get('LANGUAGE_TESTS')!=='LANGUAGE_DONE')return false;
  const languageSource=get('FINALIZER_TRIGGER_SOURCE');
  if(mode==='only'&&languageSource!=='FRESH')return false;
  if(!language.every(([state,source,rc,capability])=>capability&&get(capability)==='0'
    ?notRun(state,source,rc):passed(state,source,rc)&&get(source)===languageSource))return false;
  return languageSource==='FRESH'?phase==='language'
    :get('CPP_SUITE_SOURCE')==='CACHE'&&['entry','contract'].includes(phase);
}

function file(name, executable=false) {
  fs.accessSync(name, executable ? fs.constants.X_OK : fs.constants.R_OK);
  if (!fs.statSync(name).isFile()) throw Error('LANGUAGE_INPUT_NOT_FILE '+name);
  return name;
}
const platforms = {linux_x86_64_cjnative:['','.so'],linux_aarch64_cjnative:['','.so'],
  darwin_x86_64_cjnative:['','.dylib'],darwin_aarch64_cjnative:['','.dylib'],windows_x86_64_cjnative:['.exe','.dll']};
export function languageInputs(env=process.env) {
  const required = key => {if(!env[key])throw Error('set '+key);return fs.realpathSync(env[key]);};
  const sdk=required('GC_UNIT_LANGUAGE_SDK'),host=required('GC_UNIT_CJC_RUNTIME_LIB_DIR'),target=required('GCV2_RUNTIME_LIB_DIR');
  const native=`${{linux:'linux',darwin:'darwin',win32:'windows'}[process.platform]}_${{x64:'x86_64',arm64:'aarch64'}[process.arch]}_cjnative`;
  const compilerTuple=env.GC_UNIT_CJC_RUNTIME_TUPLE||native,tuple=env.GC_UNIT_RUNTIME_TUPLE||compilerTuple;
  if(!Object.hasOwn(platforms,tuple)||!Object.hasOwn(platforms,compilerTuple))throw Error('unsupported language runtime tuple');
  for(const [dir,expected] of [[host,compilerTuple],[target,tuple]])
    if(path.basename(dir).endsWith('_cjnative')&&path.basename(dir)!==expected)throw Error('runtime directory tuple mismatch: '+dir+' != '+expected);
  const [exe,hostShared]=platforms[compilerTuple],[,shared]=platforms[tuple];
  const cjc=file(path.join(sdk,'bin/cjc'+exe),true);
  if(env.CJC&&fs.realpathSync(env.CJC)!==fs.realpathSync(cjc))throw Error('CJC conflicts with '+cjc);
  const std=file(path.join(sdk,'lib',tuple,'libcangjie-std-core.a'));
  file(path.join(host,'libcangjie-runtime'+hostShared));
  file(path.join(target,'libcangjie-runtime'+shared));file(path.join(target,'libboundscheck'+shared));
  return {sdk,cjc,compiler_host_dir:host,runtime_lib_dir:target,compiler_host_tuple:compilerTuple,runtime_tuple:tuple,
    std_core:std,sdk_runtime_dir:path.join(sdk,'runtime/lib',tuple)};
}
const index=process.argv.findIndex((arg,i)=>i>0&&path.resolve(arg)===fileURLToPath(import.meta.url));
if(index>0) {
  try {
    const args=process.argv.slice(index+1),inputs=languageInputs();
    if(!args.length)console.log(JSON.stringify(inputs));
    else if(args.length===1&&args[0]==='--shell') {
      const quote=value=>"'"+value.replaceAll("'","'\\''")+"'";
      for(const [key,value] of Object.entries({CANGJIE_HOME:inputs.sdk,CJC:inputs.cjc,CJC_BIN:inputs.cjc,
        GC_UNIT_SDK_RUNTIME_DIR:inputs.sdk_runtime_dir}))console.log(`export ${key}=${quote(value)}`);
    } else if(args[0]==='--compile') {
      const result=spawnSync(inputs.cjc,args.slice(1),{stdio:'inherit'});
      const rc=result.status??(result.signal==='SIGTERM'?143:result.signal==='SIGKILL'?137:127);
      fs.appendFileSync(path.join(process.env.GC_UNIT_OUT,'compile.rc'),String(rc)+'\n');
      if(result.error)console.error(result.error.message);
      if(result.signal)process.kill(process.pid,result.signal);else process.exitCode=rc;
    } else throw Error('usage: installed-language-inputs.mjs [--shell|--compile ARGS...]');
  } catch(error) {console.error('LANGUAGE_INPUT_NOT_RUN: '+error.message);process.exitCode=2;}
}

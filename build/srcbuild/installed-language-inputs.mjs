#!/usr/bin/env zx
// Read ordinary installed compiler/std/runtime inputs; no qualification receipt.
import fs from 'node:fs';
import path from 'node:path';
import {fileURLToPath} from 'node:url';
import {spawnSync} from 'node:child_process';

// The original shell gate declares schema 1 and publishes its CPP exit code.
// The modern/installed language gate publishes GATE_RC. Do not synthesize a
// missing exit code or accept an unknown schema as a successful producer.
export function completedGcUnitGate(fields) {
  if(fields.get('GATE')!=='PASS')return false;
  if(fields.has('SCHEMA_VERSION'))return fields.get('SCHEMA_VERSION')==='1'
    && fields.get('CPP_SUITE')==='PASS' && fields.get('CPP_RUNNER_RC')==='0'
    && (!fields.has('GATE_RC')||fields.get('GATE_RC')==='0');
  return fields.get('GATE_RC')==='0';
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

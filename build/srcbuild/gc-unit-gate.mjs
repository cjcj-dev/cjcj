import fs from 'node:fs';
import path from 'node:path';
import {BuildError} from '../lib/errors.mjs';
import {compilerRuntimeDirectory} from '../lib/runtime-split.mjs';
import {run as runCommand} from '../lib/runner.mjs';
import {bootstrapHostSdk, envFrom, requireDir, requireFile} from './stages/common.mjs';
import {languageSourceInputs,prepareInstalledLanguage,installedLanguageCommand} from './installed-language-source.mjs';
import {completedGcUnitGate} from './installed-language-inputs.mjs';

export const GC_UNIT_LANGUAGE_DONE = 'LANGUAGE_TESTS=LANGUAGE_DONE';
export const GC_UNIT_LANGUAGE_DEFERRED = 'LANGUAGE_TESTS=LANGUAGE_DEFERRED';
export function gcUnitLanguageGateEnabled(config, env=process.env) {
  return Boolean(bootstrapHostSdk(config,env)) && config.target.spec.os==='linux' && !config.target.spec.crossCompile;
}
export function gcUnitStatusPath(config,sdk) {
  return path.join(sdk,'runtime/lib',config.target.runtimeLibSubdir(config.buildType),'gc_unit_gate.status');
}
export const gcUnitBuildStatus = runtime => path.join(runtime,'CMakebuild/gc-unit.status');
export function gcUnitRuntimeBuildEnv(config,env=process.env) {
  if(!gcUnitLanguageGateEnabled(config,env))return undefined;
  return {GC_UNIT_GATE_LANGUAGE_TESTS:'defer',GC_UNIT_GATE_STATUS:gcUnitBuildStatus(path.join(config.repoPath('runtime'),'runtime'))};
}
function statusFields(file,stage) {
  requireFile(file,{stage});const fields=new Map();
  for(const line of fs.readFileSync(file,'utf8').split(/\r?\n/)) {
    const at=line.indexOf('=');if(at<1)continue;
    const key=line.slice(0,at);if(fields.has(key))throw new BuildError(stage,`duplicate status field: ${key}`);
    fields.set(key,line.slice(at+1));
  }
  return fields;
}
export function assertLanguageState(file,expected,stage) {
  const fields=statusFields(file,stage);
  if(!completedGcUnitGate(fields))throw new BuildError(stage,`gc_unit gate is not one exact PASS/rc0 in ${file}`);
  if(fields.get('LANGUAGE_TESTS')!==expected.slice('LANGUAGE_TESTS='.length))
    throw new BuildError(stage,`${expected} missing in ${file}`);
  return fields;
}
export function assertGcUnitLanguageDeferred(config,sdk,{env=process.env,stage='stdlib.gc_unit_language'}={}) {
  if(gcUnitLanguageGateEnabled(config,env))assertLanguageState(gcUnitStatusPath(config,sdk),GC_UNIT_LANGUAGE_DEFERRED,stage);
}
export function assertGcUnitLanguageDone(config,sdk,{env=process.env,stage='verify.gc_unit_language'}={}) {
  if(gcUnitLanguageGateEnabled(config,env))assertLanguageState(gcUnitStatusPath(config,sdk),GC_UNIT_LANGUAGE_DONE,stage);
}
export function beginGcUnitLanguageDeferral(config,runtime,sdk,{env=process.env}={}) {
  if(!gcUnitLanguageGateEnabled(config,env))return;
  for(const file of [gcUnitBuildStatus(runtime),gcUnitStatusPath(config,sdk)])fs.rmSync(file,{force:true});
}
// These are normal source/build inputs for the installed language consumer,
// not a publication or an alternative runtime installation. Never copy SOs
// over the CMake installation or turn a prior language PASS into a new run.
export function installGcUnitInputs(config,runtime,sdk,{gateStatus=gcUnitBuildStatus(runtime)}={}) {
  const stage='runtime.gc_unit_language',status=gateStatus;
  const fields=statusFields(status,stage);
  if(!completedGcUnitGate(fields)||fields.get('CPP_SUITE')!=='PASS'
    ||!['LANGUAGE_DEFERRED','LANGUAGE_DONE'].includes(fields.get('LANGUAGE_TESTS')))
    throw new BuildError(stage,`current native gate did not complete: ${status}`);
  const {modern}=languageSourceInputs(runtime);
  const carried=path.join(sdk,'share/runtime-build'),to=path.join(carried,'runtime');
  if(path.resolve(runtime)===path.resolve(to)||path.resolve(runtime).startsWith(path.resolve(carried)+path.sep))throw new BuildError(stage,'runtime source overlaps carried destination');
  const members=['tests/gc_unit','tests/perf_vs_official','src','include','third_party/third_party_bounds_checking_function/include',
    'build/resolve_runtime_headers.py',...(modern?['build/resolve_runtime_headers.mjs']:[]),'CMakeLists.txt',
    'CMakebuild/compile_commands.json'];
  for(const member of members)if(!fs.existsSync(path.join(runtime,member)))throw new BuildError(stage,`missing normal runtime input: ${member}`);
  const headers=requireDir(path.join(runtime,'CMakebuild/runtime-staging/include'),{stage});
  const segmented=fields.get('SEGMENTED_ARRAY_MANAGED_CAN_RUN')==='1';
  const cppElf=segmented?requireFile(path.join(fields.get('EVIDENCE_DIR')||'', 'cj_gc_unit'),{stage}):null;
  fs.rmSync(carried,{recursive:true,force:true});
  for(const member of members) {
    const from=path.join(runtime,member),destination=path.join(to,member);
    if(!fs.existsSync(from))throw new BuildError(stage,`missing normal runtime input: ${from}`);
    fs.mkdirSync(path.dirname(destination),{recursive:true});
    fs.cpSync(from,destination,{recursive:true,dereference:true,filter:file=>!['.git','__pycache__','build_standalone'].includes(path.basename(file))});
  }
  prepareInstalledLanguage(to);
  if(cppElf)fs.copyFileSync(cppElf,path.join(to,'CMakebuild/cj_gc_unit'));
  fs.cpSync(headers,path.join(sdk,'runtime/include'),{recursive:true,dereference:true});
  fs.copyFileSync(status,path.join(to,'CMakebuild/gc-unit.status'));
  const installed=gcUnitStatusPath(config,sdk);fs.mkdirSync(path.dirname(installed),{recursive:true});fs.copyFileSync(status,installed);
  return carried;
}
export function finishGcUnitLanguageDeferral(config,runtime,sdk,{env=process.env}={}) {
  if(!gcUnitLanguageGateEnabled(config,env))return;
  assertLanguageState(gcUnitBuildStatus(runtime),GC_UNIT_LANGUAGE_DEFERRED,'runtime.gc_unit_language');
  installGcUnitInputs(config,runtime,sdk);
}
export function languageInputEnvironment(config,sdk,env=process.env) {
  const compiler=path.join(sdk,'bin/cjc'),hostSdk=bootstrapHostSdk(config,env);
  return {...env,CJCJ_OFFICIAL_SDK_ROOT:hostSdk,CANGJIE_HOME:sdk,CJC:compiler,GC_UNIT_LANGUAGE_SDK:sdk,
    GC_UNIT_RUNTIME_TUPLE:config.target.runtimeLibSubdir(config.buildType),
    GC_UNIT_CJC_RUNTIME_TUPLE:config.target.spec.hostRuntimeTuple||config.target.spec.runtimeTuple,
    GCV2_RUNTIME_LIB_DIR:path.join(sdk,'runtime/lib',config.target.runtimeLibSubdir(config.buildType)),
    GC_UNIT_CJC_RUNTIME_LIB_DIR:compilerRuntimeDirectory({sdk,hostSdk,target:config.target,compiler}),
    GC_UNIT_COLOUR_HOST_RUNTIME:path.join(hostSdk,'runtime/lib',
      config.target.spec.hostRuntimeTuple||config.target.spec.runtimeTuple,
      config.target.spec.hostRuntimeLibrary||config.target.spec.runtimeLibrary)};
}
export async function runGcUnitLanguageTests(config,sdk,{env=process.env,source=null}={}) {
  if(!gcUnitLanguageGateEnabled(config,env))return;
  const stage='stdlib.gc_unit_language';
  // source is the explicitly selected native producer's carried source/build
  // inputs. The std checkout is not the producer of these runtime tests.
  const root=source||path.join(sdk,'share/runtime-build'),runtime=path.join(root,'runtime');
  const native=statusFields(gcUnitBuildStatus(runtime),stage);
  if(!completedGcUnitGate(native)||native.get('CPP_SUITE')!=='PASS')
    throw new BuildError(stage,'native CPP result required before only-language');
  const command=installedLanguageCommand(runtime);
  requireFile(path.join(runtime,'CMakebuild/compile_commands.json'),{stage});
  const headers=requireDir(path.join(sdk,'runtime'),{stage});
  requireFile(path.join(headers,'include/schedule.h'),{stage});
  const status=gcUnitStatusPath(config,sdk);
  // Remove the previous result before entering the real language gate. A
  // successful process that fails to produce this invocation's status fails.
  fs.rmSync(status,{force:true});
  const deleted=Object.fromEntries(Object.keys(process.env).filter(key=>!(key in env)).map(key=>[key,null]));
  await runCommand(command,{stage,envOverlay:{...deleted,...envFrom(config,languageInputEnvironment(config,sdk,env),{
    GC_UNIT_SOURCE_ROOT:root,GCV2_RUNTIME_CONFIG:null,GCV2_RUNTIME_OUTPUT_ROOT:headers,
    GCV2_RUNTIME_BUILD_DIR:path.join(runtime,'CMakebuild'),GC_UNIT_GATE_STATUS:status,GC_UNIT_GATE_LANGUAGE_TESTS:'only',
  })}});
  assertGcUnitLanguageDone(config,sdk,{env,stage});
}

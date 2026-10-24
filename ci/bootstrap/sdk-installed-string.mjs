#!/usr/bin/env zx
// Finite installed String consumer. Fixed producer responsibility is reviewed
// separately; neither a report nor a previous PASS authorizes this execution.
import fs from 'node:fs/promises';
import path from 'node:path';
import {fileURLToPath} from 'node:url';
import {parseArgs} from 'node:util';
import {sdkPlatform,sdkEnvironment} from './sdk-platform.mjs';
import {atomicJson,fileDigest,privateRoot,relative,withProcessCancellation} from './sdk-flow.mjs';
import {streamStdProcess} from '../srcbuild/lib/assert-std-barriers.mjs';

export function stringEnvironment({sdk,std,runtime,platform,work}) {
 // Use an allowlist, not sdkEnvironment(process.env): it retains old loader paths.
 const base={PATH:'/usr/bin:/bin',LANG:'C.UTF-8',LC_ALL:'C.UTF-8',TZ:'UTC',TMPDIR:path.join(work,'tmp'),cjHeapSize:'8GB'};
 const native=sdkPlatform(platform),env=sdkEnvironment(sdk,platform,base,runtime);
 env.CANGJIE_PATH=path.join(std,'modules',native.tuple);
 env.LIBRARY_PATH=[path.join(std,'lib',native.tuple),path.join(runtime,'runtime/lib',native.tuple),path.join(runtime,'lib',native.tuple)].join(':');
 return env;
}
const methods={index:'_CNat6String7indexOfHRNatY0_E',array:'_CNat6String7toArrayHv'};
const consumers={heapReceiver:methods.index,heapArgument:methods.index,heapBoth:methods.index,
 heapArray:methods.array,plainIndex:methods.index,plainArray:methods.array};
export async function stringInstall({sdk,std,runtime,platform,work,signal}) {
 if(platform!=='linux_x86_64'||process.platform!=='linux'||process.arch!=='x64')throw new Error('STRING_PLATFORM_UNSUPPORTED');
 for(const [name,value] of Object.entries({sdk,std,runtime,work}))
  if(typeof value!=='string'||!path.isAbsolute(value))throw new Error('STRING_INPUT_PATH '+name);
 signal?.throwIfAborted();
 [sdk,std,runtime]=await Promise.all([sdk,std,runtime].map(p=>fs.realpath(p)));
 work=await privateRoot(work);
 if([sdk,std,runtime].some(p=>work===p||work.startsWith(p+path.sep)))throw new Error('STRING_WORK_INSIDE_INPUT');
 const native=sdkPlatform(platform),tuple=native.tuple;
 const core=path.join(std,'lib',tuple,'libcangjie-std-core.a');
 const module=path.join(std,'modules',tuple,'std/std.core.cjo');
 const runtimeFile=path.join(runtime,'runtime/lib',tuple,'libcangjie-runtime.so');
 for(const file of [path.join(sdk,'bin/cjc'),core,module,runtimeFile])
  if(!(await fs.stat(file)).isFile())throw new Error('STRING_INPUT_FILE '+file);
 // Observe the actual pair used by this execution; status from another
 // language invocation is not an input credential.
 const boundsFile=path.join(runtime,'runtime/lib',tuple,'libboundscheck.so');
 const pair={runtime:await fileDigest(runtimeFile),boundscheck:await fileDigest(boundsFile)};
 await fs.mkdir(work,{recursive:true});work=await fs.mkdtemp(path.join(work,'string-'));
 await fs.mkdir(path.join(work,'tmp'));
 const env=stringEnvironment({sdk,std,runtime,platform,work}),commands=[];
 const result={scope:'installed-String-functional-consumer',status:'WIP',sdk,std,runtime,platform,work,commands,pair,
  environment:env,gcLanguageQualification:'SEPARATE_GATE_REQUIRED'};
 const save=()=>atomicJson(path.join(work,'string-result.json'),result);
 const identify=async file=>({file,realpath:await fs.realpath(file),bytes:(await fs.stat(file)).size,sha256:await fileDigest(file)});
 async function invoke(name,argv,environment=env) {
  signal?.throwIfAborted();
  const row={name,argv,cwd:work,started:new Date().toISOString()};commands.push(row);
  console.log(JSON.stringify({event:'installed-string-command',...row}));
  try {
   const r=await streamStdProcess(argv,{cwd:work,env:environment,signal});
   Object.assign(row,{rc:r.code,signal:r.signal,processGroup:r.processGroup,cleanupComplete:r.cleanupComplete});
   await fs.writeFile(path.join(work,name+'.stdout'),r.stdout);await fs.writeFile(path.join(work,name+'.stderr'),r.stderr);
   if(r.code!==0||r.signal)throw Object.assign(new Error('STRING_COMMAND '+name+' rc='+r.code+' signal='+r.signal),{rc:r.code||1,signal:r.signal});
   return r;
  } catch(error) {
   if(error.childRc!==undefined)row.rc=error.childRc;
   else if(!Object.hasOwn(row,'rc'))row.rc=null;
   row.wrapperRc=error.rc??1;row.signal=error.signal??null;row.error=error.message;
   if(error.childRc!==undefined)row.childRc=error.childRc;
   if(error.processGroup!==undefined)row.processGroup=error.processGroup;
   if(error.cleanupComplete!==undefined)row.cleanupComplete=error.cleanupComplete;
   for(const key of ['stdout','stderr'])if(typeof error[key]==='string')await fs.writeFile(path.join(work,name+'.'+key),error[key]);
   throw error;
  } finally {row.ended=new Date().toISOString();await save();console.log(JSON.stringify({event:'installed-string-result',...row}));}
 }
 function marker(output,name){if(!output.stdout.split(/\r?\n/).includes(name))throw new Error('STRING_OBSERVATION_MISSING '+name);}
 try {
  const entry=await fs.realpath(path.join(sdk,'bin/cjc'));
  const recipe=(await fs.readFile(entry+'.entry','utf8')).trimEnd().split('\n');
  if(recipe[0]!=='cjcj-sdk-entry-v1')throw new Error('STRING_COMPILER_ENTRY');
  const compiler=path.join(sdk,relative(recipe[2]));
  if(!(await fs.realpath(compiler)).startsWith(sdk+path.sep))throw new Error('STRING_COMPILER_ESCAPE');
  result.inputs={compiler:await identify(compiler),entry:await identify(entry),module:await identify(module),
   core:await identify(core),runtime:await identify(runtimeFile)};
  result.compilerInputs=JSON.parse(await fs.readFile(path.join(sdk,'compiler-inputs.json'),'utf8'));
  if(result.compilerInputs.compilerSha256!==result.inputs.compiler.sha256)throw new Error('STRING_COMPILER_INPUT_MISMATCH');
  await save();
  const input=path.join(work,'installed-string.cj'),binary=path.join(work,'string-consumer'),map=path.join(work,'link.map');
  await fs.copyFile(new URL('./fixtures/installed-string.cj',import.meta.url),input);
  const compiled=await invoke('compile',[path.join(sdk,'bin/cjc'),'-V','-O0','-j1','--apc=1','--static-std',
   '--import-path',path.dirname(path.dirname(module)),'-L',path.dirname(core),'-L',path.dirname(runtimeFile),
   '--link-option','-t','--link-option','-Map='+map,input,'-o',binary]);
  if((await fs.stat(map)).size>16*1024*1024)throw new Error('STRING_LINK_MAP_LIMIT');
  const linkMap=await fs.readFile(map,'utf8');
  if(!linkMap.includes(core+'(')||!(compiled.stdout+compiled.stderr).includes(core))throw new Error('STRING_CURRENT_CORE_NOT_LINKED');
  const linkedCore=[...new Set(linkMap.match(/\S*libcangjie-std-core\.(?:a|so)/g)||[])];
  if(linkedCore.length!==1||linkedCore[0]!==core)throw new Error('STRING_FOREIGN_CORE '+linkedCore.join(','));
  result.linkedCore=linkedCore;result.binary=await identify(binary);
  // Confirm public wrapper calls and the exact two installed definitions. This
  // is linkage/target evidence, not an instruction semantics interpreter.
  const symbols=await invoke('symbols',['/usr/bin/nm','--defined-only',binary]);
  const names=symbols.stdout.trim().split('\n').map(l=>l.trim().split(/\s+/).at(-1));
  for(const method of Object.values(methods))if(names.filter(n=>n===method).length!==1)throw new Error('STRING_METHOD_DEFINITION '+method);
  result.calls={};
  for(const [name,target] of Object.entries(consumers)) {
   const matches=names.filter(n=>n.includes(name)&&n.startsWith('_C'));
   if(matches.length!==1)throw new Error('STRING_WRAPPER_DEFINITION '+name);
   const output=await invoke('call-'+name,['/usr/bin/objdump','-drw','--disassemble='+matches[0],binary]);
   if(!output.stdout.split('\n').some(line=>/\b(?:callq?|jmpq?)\b/.test(line)&&line.includes('<'+target+'>')))
    throw new Error('STRING_CALL_NOT_REACHED '+name);
   result.calls[name]={symbol:matches[0],target};
  }
  const runEnv={...env,LD_LIBRARY_PATH:[path.dirname(runtimeFile),path.join(runtime,'lib',tuple),
   path.join(std,'runtime/lib',tuple),path.join(std,'lib',tuple),path.join(std,'lib')].join(':'),LD_DEBUG:'libs'};
  const args=['xxabcabczz','bc','仓颉'];
  const plain=await invoke('run-plain',[binary,...args,'plain'],runEnv);marker(plain,'STRING_PLAIN_PASS');
  const functional=await invoke('run-values',[binary,...args,'values'],runEnv);marker(functional,'STRING_VALUES_PASS');
  const loaded=[];
  for(const text of [plain.stderr,functional.stderr])for(const line of text.split('\n')) {
   const found=line.match(/calling init:\s+(\/.*)$/);if(found)loaded.push(found[1].trim());
  }
  const wanted=await fs.realpath(runtimeFile),observed=[];
  for(const file of [...new Set(loaded)])if(/libcangjie|libboundscheck|libstdFFI/.test(path.basename(file))) {
   const resolved=await fs.realpath(file);
   if(![runtime,std].some(root=>resolved.startsWith(root+path.sep)))throw new Error('STRING_FOREIGN_LOADED_LIBRARY '+resolved);
   if(/libcangjie-std-/.test(path.basename(file)))throw new Error('STRING_DYNAMIC_STD_UNEXPECTED '+file);
   observed.push(await identify(file));
  }
  if(!observed.some(row=>row.realpath===wanted))throw new Error('STRING_RUNTIME_LOAD_UNOBSERVED');
  if(!observed.some(row=>path.basename(row.file)==='libboundscheck.so'&&row.sha256===pair.boundscheck))
   throw new Error('STRING_BOUNDSCHECK_LOAD_UNOBSERVED');
  result.loaded=observed;
  signal?.throwIfAborted();result.status='PASS';await save();
  console.log('INSTALLED_STRING_PASS scope=fixed-functional-cases gc-language=separate');
  return result;
 } catch(error) {result.status='FAILED';result.error=error.message;result.rc=error.rc||1;await save();throw error;}
}
if(process.argv[1]&&path.resolve(process.argv[1])===fileURLToPath(import.meta.url)) {
 try {
  const {values}=parseArgs({options:Object.fromEntries(['sdk','std','runtime','platform','work'].map(key=>[key,{type:'string'}]))});
  await withProcessCancellation(signal=>stringInstall({...values,signal}));
 }catch(error){console.error(error.stack);process.exitCode=error.rc||1;}
}

#!/usr/bin/env zx
// Resource transport through public consumers; H remains a reference compiler.
import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs/promises';
import path from 'node:path';
import os from 'node:os';
import {spawnSync} from 'node:child_process';
import {sdkEnvironment} from './sdk-platform.mjs';
const host=process.env.RESOURCE_CONSUMER_HOST,base=process.env.RESOURCE_CONSUMER_EVIDENCE;
if(!host||!base)throw Error('RESOURCE_CONSUMER_HOST and RESOURCE_CONSUMER_EVIDENCE required');
await fs.mkdir(base,{recursive:true});
const root=await fs.mkdtemp(path.join(base,'consumers-'));
const repo=path.resolve(import.meta.dirname,'../..');
const env=sdkEnvironment(host,'linux_x86_64',{...process.env,HOME:process.env.HOME||os.userInfo().homedir,CJPM_CONFIG:root+'/cjpm-cache',cjHeapSize:'2GB'});
await fs.mkdir(env.CJPM_CONFIG,{recursive:true});
for(const key of ['CANGJIE_BUILD_JOBS','KKK2_JOBS','CMAKE_BUILD_PARALLEL_LEVEL','CJ_HEAP'])delete env[key];
const records=[];
async function run(label,argv,extra={}) {
 const r=spawnSync(argv[0],argv.slice(1),{cwd:repo,env:{...env,...extra},encoding:'utf8',timeout:180000,maxBuffer:1024*1024});
 await fs.writeFile(root+'/'+label+'.log',(r.stdout||'')+(r.stderr||''));
 records.push({label,argv,rc:r.status,signal:r.signal,error:r.error?.message});await fs.writeFile(root+'/commands.json',JSON.stringify(records,null,2));
 assert.ifError(r.error);assert.equal(r.signal,null);return {...r,text:r.stdout+r.stderr};
}
test('public hello uses parent jobs with actual reference compiler and cjpm',async()=>{
 const work=root+'/hello';
 await fs.mkdir(work+'/cjpm',{recursive:true});
 await fs.writeFile(work+'/cjpm/cangjie-repo.toml','[repository.cache]\npath = '+JSON.stringify(env.CJPM_CONFIG)+'\n');
 const r=await run('hello',[process.execPath,repo+'/ci/bootstrap/sdk-hello.mjs','--sdk',host,'--work',work,'--platform','linux_x86_64'],{CANGJIE_BUILD_JOBS:'1'});
 assert.equal(r.status,0,r.text);
 const result=JSON.parse(await fs.readFile(work+'/hello-result.json'));
 assert.equal(result.compiled.stdout.trim(),'Hello, Cangjie');assert.equal(result.packaged.stdout.trim(),'Hello, Cangjie');
 const build=result.commands.find(row=>row.argv[0].endsWith('/cjpm'));
 assert.ok(build,'actual cjpm result recorded');assert.equal(build.rc,0);
 assert.deepEqual(build.argv.slice(-2),['-j','1']);
 console.log('REFERENCE_HELLO_JOBS_ASSERTION_REACHED '+JSON.stringify(build.argv));
});
test('public override resolver shares budget across actual compiler invocations',async()=>{
 const out=root+'/override';
 const r=await run('override',[process.execPath,repo+'/scripts/override_resolver_gate.mjs','--compiler',host+'/bin/cjc','--out',out,'--jobs','2']);
 const result=JSON.parse(await fs.readFile(out+'/result.json'));
 assert.equal(result.workers,2);assert.equal(result.perCompiler,1);
 for(const row of result.cases){assert.equal(row.assertion_executed,true);assert.equal(row.command[row.command.indexOf('--jobs')+1],'1');}
 assert.equal(r.status,0,r.text);assert.ok(result.cases.every(row=>row.target_ok));
 console.log('REAL_OVERRIDE_TARGET_ASSERTION_REACHED '+JSON.stringify(result.cases.map(row=>({name:row.name,rc:row.rc,calls:row.calls}))));
});
async function bchirFixture(label) {
 assert.ok(process.env.RESOURCE_CONSUMER_CORES,'supply an assigned child CPU subset');
 const childJobs=process.env.RESOURCE_CONSUMER_CORES.split(',').reduce((n,part)=>{const [first,last=first]=part.split('-').map(Number);return n+last-first+1;},0);
 const directory=root+'/'+label,source=directory+'/source',sdk=directory+'/sdk',evidence=directory+'/evidence';
 const files=['packages/chir/cjpm.toml','packages/chir/src/BCHIRLinker.cj','packages/chir/src/BCHIR.cj','packages/chir/src/BCHIRLinker_test.cj','runtime_shim/cjselfhost_llvmshim.o'];
 for(const rel of files){await fs.mkdir(path.dirname(source+'/'+rel),{recursive:true});await fs.writeFile(source+'/'+rel,'Explicit argument transport fixture; no CHIR compilation.\n');}
 const manifest='  link-option = "runtime_shim/cjselfhost_llvmshim.o ${CANGJIE_HOME}/third_party/llvm/lib/libLLVM-15.so -lstdc++"\n';
 await fs.writeFile(source+'/packages/chir/cjpm.toml',manifest);
 for(const rel of ['bin/cjc','runtime/lib/linux_x86_64_cjnative/libcangjie-runtime.so','runtime/lib/linux_x86_64_cjnative/libboundscheck.so','third_party/llvm/lib/libLLVM-15.so']){
  await fs.mkdir(path.dirname(sdk+'/'+rel),{recursive:true});await fs.writeFile(sdk+'/'+rel,'Boundary fixture only.\n');
 }
 await fs.mkdir(sdk+'/tools/bin',{recursive:true});
 await fs.writeFile(sdk+'/tools/bin/cjpm','#!'+process.execPath+'\nconsole.log("BCHIR_BOUNDARY "+JSON.stringify({argv:process.argv.slice(2),heap:process.env.cjHeapSize}));process.exit(23);\n',{mode:0o755});
 const callerBin=directory+'/caller node bin',trace=directory+'/node.jsonl';
 await fs.mkdir(callerBin,{recursive:true});
 const observedNode=callerBin+'/node';
 // This selected tool observes/delegates to the real Node resource CLI.
 // The 37 control models an explicit tool failure with syntactically valid output.
 await fs.writeFile(observedNode,'#!'+process.execPath+'\n'+
  "import fs from 'node:fs';import {spawnSync} from 'node:child_process';\n"+
  'const argv=process.argv.slice(2),failed=process.env.BCHIR_TOOL_FAILURE==="37";\n'+
  'const result=failed?{status:37,signal:null}:spawnSync('+JSON.stringify(process.execPath)+',argv,{stdio:"inherit"});\n'+
  'fs.appendFileSync('+JSON.stringify(trace)+',JSON.stringify({argv,rc:result.status,signal:result.signal})+"\\n");\n'+
  'if(failed){console.log("STD_BUILD_HEAP=4MB\\nSTD_BUILD_JOBS=1");console.error("BCHIR_RESOURCE_CHILD_RC=37");}\n'+
  'process.exit(result.status??1);\n',{mode:0o755});
 await fs.symlink('node',callerBin+'/selected-node');
 const invoke=extra=>run(label,['/bin/bash',repo+'/scripts/bchir_linker_test.sh',source,directory+'/target',evidence],{
  CANGJIE_HOME:sdk,BCHIR_TEST_CORES:process.env.RESOURCE_CONSUMER_CORES,NODE:process.execPath,
  PATH:callerBin+path.delimiter+env.PATH,cjHeapSize:'4MB',STD_BUILD_HEAP:undefined,STD_BUILD_JOBS:undefined,...extra});
 const restored=async rc=>{
  assert.equal(await fs.readFile(source+'/packages/chir/cjpm.toml','utf8'),manifest);
  assert.equal((await fs.readFile(evidence+'/harness.rc','utf8')).trim(),String(rc));
  assert.equal((await fs.readFile(evidence+'/manifest.restore.log','utf8')).trim(),'');
 };
 const selected=async rc=>{
  const text=await fs.readFile(trace,'utf8').catch(error=>{if(error.code==='ENOENT')return null;throw error;});
  console.log('BCHIR_NODE_SELECTION_ASSERTION_REACHED '+JSON.stringify({selectedToolRan:text!==null}));
  assert.notEqual(text,null,'resource selector must execute the Node selected from the original caller PATH');
  const rows=text.trim().split('\n').map(JSON.parse);
  assert.equal(rows.length,1);assert.equal(rows[0].rc,rc);assert.equal(rows[0].signal,null);
  assert.equal(path.resolve(rows[0].argv[0]),repo+'/ci/build-resources.mjs');
  console.log('BCHIR_SELECTED_NODE_ASSERTION_REACHED '+JSON.stringify(rows[0]));
 };
 const reached=async r=>{
  assert.equal(r.status,23,r.text);
  const log=await fs.readFile(evidence+'/test.log','utf8');
  const observed=JSON.parse(log.match(/BCHIR_BOUNDARY (.+)/)?.[1]||'null');
  assert.equal(observed.argv[observed.argv.indexOf('-j')+1],String(childJobs));assert.equal(observed.heap,'4MB');
  assert.equal((await fs.readFile(evidence+'/test.rc','utf8')).trim(),'23');
  await restored(23);console.log('BCHIR_RESOURCE_BOUNDARY_ASSERTION_REACHED '+JSON.stringify(observed));
 };
 const notReached=async()=>{
  assert.equal(await fs.stat(evidence+'/test.log').catch(()=>null),null,'cjpm must not execute after resource failure');
  assert.equal(await fs.stat(evidence+'/test.rc').catch(()=>null),null);
 };
 return {invoke,restored,selected,reached,notReached,observedNode};
}
test('public bchir runner chooses jobs after entering its requested CPU domain',async()=>{
 const f=await bchirFixture('bchir-explicit');await f.reached(await f.invoke({}));
});
test('public bchir default selects Node from the original caller PATH',async()=>{
 const f=await bchirFixture('bchir-default');
 const r=await f.invoke({NODE:undefined});await f.selected(0);await f.reached(r);
});
test('public bchir named explicit Node resolves before narrowing PATH',async()=>{
 const f=await bchirFixture('bchir-named');
 const r=await f.invoke({NODE:'selected-node'});await f.selected(0);await f.reached(r);
});
test('public bchir preserves actual invalid resource rc and restores the manifest',async()=>{
 const f=await bchirFixture('bchir-invalid');
 const r=await f.invoke({NODE:f.observedNode,CANGJIE_BUILD_JOBS:'0',STD_BUILD_HEAP:'4MB',STD_BUILD_JOBS:'1'});
 await f.selected(1);assert.equal(r.status,1,r.text);assert.match(r.text,/BUILD_JOBS invalid/);
 await f.notReached();await f.restored(1);
});
test('public bchir preserves resource child rc37 before evaluating its output',async()=>{
 const f=await bchirFixture('bchir-rc37');
 const r=await f.invoke({NODE:f.observedNode,BCHIR_TOOL_FAILURE:'37'});
 await f.selected(37);console.log('BCHIR_RESOURCE_RC_ASSERTION_REACHED '+JSON.stringify({expected:37,actual:r.status}));
 assert.equal(r.status,37,r.text);assert.match(r.text,/BCHIR_RESOURCE_CHILD_RC=37/);
 await f.notReached();await f.restored(37);
});

test('explicit virtual maximum above observed memory can run a small real reference program',async()=>{
 const maximum=Math.floor((process.constrainedMemory()||os.totalmem())/1024**3)+1+'GB';
 const selection=await run('large-maximum-selection',[process.execPath,repo+'/ci/build-resources.mjs','--json',maximum]);
 assert.equal(selection.status,0,selection.text);
 assert.equal(JSON.parse(selection.stdout).heap,maximum);
 assert.match(selection.stderr,/above observed memory/);
 const r=await run('large-maximum-hello',[process.execPath,repo+'/ci/bootstrap/sdk-hello.mjs','--sdk',host,'--work',root+'/large-maximum','--platform','linux_x86_64','--compiler-only'],{cjHeapSize:maximum});
 assert.equal(r.status,0,r.text);assert.match(r.stdout,/Hello, Cangjie/);
 console.log('REAL_MAXIMUM_HEAP_NOT_RSS_ASSERTION_REACHED '+maximum);
});

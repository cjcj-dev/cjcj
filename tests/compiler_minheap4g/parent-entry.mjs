#!/usr/bin/env zx
import fs from 'node:fs';
import path from 'node:path';
import {spawn,spawnSync} from 'node:child_process';
import {createHash} from 'node:crypto';
const source=path.resolve(import.meta.dirname,'../..'),root=path.dirname(source),out=root+'/parent-attempt3';
const host='/mnt/cjcj-nvme/impl_full_sdk_sol_1108/inputs/official-host/host-sdk-dQJL56/cangjie';
const seed='/root/collect_ten_v2_sol_1113/matrix-fixed-1114/install';
const native='/mnt/cjcj-data/impl_full_sdk_sol_1108/main-pair-1114/native/install';
const cache='/root/impl_managed_output_sol_1113/merge-matrix-type-fallback/cjcj-source/target';
const ref=globalThis.argv?._?.[0] ?? process.argv[2],zx=root+'/r1-tools/node_modules/.bin/zx';
fs.mkdirSync(out);for(const d of ['home','tmp','native','hashmap'])fs.mkdirSync(out+'/'+d);
const env={PATH:'/usr/local/bin:/usr/bin:/bin',HOME:out+'/home',TMPDIR:out+'/tmp',LANG:'C.UTF-8',LC_ALL:'C.UTF-8'};
const record={ref,source,out,host,seed,native,cache,start:new Date().toISOString(),steps:[],claims:[]};
const save=()=>fs.writeFileSync(out+'/result.json',JSON.stringify(record,null,2));
const read=p=>fs.readFileSync(p,'utf8').trim();
const hash=p=>createHash('sha256').update(fs.readFileSync(p)).digest('hex');
async function run(name,argv,{cwd=out,environment=env,expected=0,timeout=0}={}){
 const fd=fs.openSync(out+'/'+name+'.log','wx'); const row={name,argv,cwd,env:environment,start:new Date().toISOString()};record.steps.push(row);save();
 const child=spawn(argv[0],argv.slice(1),{cwd,env:environment,stdio:['ignore',fd,fd]});
 const deadline=timeout?setTimeout(()=>{row.timedOut=true;child.kill('SIGKILL');},timeout):null;
 const seen=new Map(); const timer=setInterval(()=>{const todo=[child.pid];for(let i=0;i<todo.length;i++){const pid=todo[i];try{
  if(!seen.has(pid))seen.set(pid,{pid,exe:fs.readlinkSync(`/proc/${pid}/exe`),cmd:read(`/proc/${pid}/cmdline`).split('\0'),maps:read(`/proc/${pid}/maps`)});
  for(const t of fs.readdirSync(`/proc/${pid}/task`))for(const c of read(`/proc/${pid}/task/${t}/children`).split(/\s+/).filter(Boolean).map(Number))if(!todo.includes(c))todo.push(c);
 }catch{}}},200);
 Object.assign(row,await new Promise((resolve,reject)=>{child.once('error',reject);child.once('close',(rc,signal)=>resolve({rc,signal}));}));
 if(deadline)clearTimeout(deadline);clearInterval(timer);fs.closeSync(fd);row.end=new Date().toISOString();row.processes=[...seen.values()];save();console.log(name+' rc='+row.rc+' signal='+row.signal);
 if(row.timedOut||(expected!==null&&(row.rc!==expected||row.signal)))throw Error(name+' expected '+expected);return row;
}
const acquired=[];let rc=1;
try{
 for(const [suffix,cpus] of [['cpu','32-39'],['smt','128-135']]){
  const key='backport_compiler_astra_1112-h1-parent-'+suffix;
  const r=spawnSync('bash',['/root/cjtools/measure_claim.sh','claim',key,cpus,'compiler minimum managed heap production'],{encoding:'utf8',env:{...env,MEASURE_OWNER_PID:String(process.pid)}});
  record.claims.push({key,cpus,rc:r.status,stdout:r.stdout,stderr:r.stderr});save();if(r.status!==0)throw Error('claim');acquired.push(key);
 }
 const cg='/sys/fs/cgroup'+read('/proc/self/cgroup').split('::').at(-1);
 record.resources=Object.fromEntries(['cpuset.cpus.effective','memory.max','memory.swap.max','cpu.max'].map(k=>[k,read(cg+'/'+k)]));record.limits=read('/proc/self/limits');
 record.topology=Object.fromEntries([32,39].map(c=>[c,read(`/sys/devices/system/cpu/cpu${c}/topology/thread_siblings_list`)]));save();
 if(record.resources['memory.swap.max']!=='0'||!record.limits.match(/Max core file size\s+0\s+0/))throw Error('resources');
 const git=spawnSync('git',['-C',source,'rev-parse','HEAD'],{encoding:'utf8'});record.sourceCheck={rc:git.status,stdout:git.stdout,stderr:git.stderr,ref};save();if(git.status!==0||git.stdout.trim()!==ref)throw Error('source ref');


 const producerRef='5a47f0bb15a072b38ff040df961875bb8f741038';
 record.compilerRef=producerRef;record.assemblerRef=ref;save();
 record.graphTestsReuse=root+'/parent-attempt1/graph-tests.log';save();
 record.descriptorTestsReuse=root+'/parent-attempt2/descriptor-fixture-tests.log';save();
 const original='/mnt/cjcj-nvme/impl_full_sdk_sol_1108/main-pair-1114/sdk-descriptor.json';
 const descriptor=JSON.parse(read(original));
 descriptor.sources.compiler=source;descriptor.sources.h1=source;
 descriptor.compilerCommit=producerRef;descriptor.h1Commit=producerRef;
 delete descriptor.archive;delete descriptor.tools.privateRoot;
 // This bounded public traversal stops at stage0-run: it does not build std.
 // The old descriptor's pcre2 source failed verification; retain that failure,
 // do not claim it repaired or weaken stdDependencyInputs validation.
 record.unusedStdDependencies=descriptor.stdDependencies;delete descriptor.stdDependencies;
 record.originalDescriptor=original;save();
 const prepare=async(label,reuse=false,extraTools={})=>{
  const d=structuredClone(descriptor);d.work=out+'/'+label+'/work';d.install=out+'/'+label+'/final-sdk';Object.assign(d.tools,extraTools);
  if(reuse)d.installations.h1={product:root+'/attempt6-r1/compiler/bin/cjcj-stage1',buildInputs:root+'/attempt6-r1/compiler/bin/build-inputs.json',buildResult:root+'/attempt6-r1/compiler.commands.json'};
  fs.mkdirSync(out+'/'+label,{recursive:true});fs.writeFileSync(out+'/'+label+'/descriptor.json',JSON.stringify(d,null,2));
  const e={...env,CJCJ_NATIVE_INPUTS:out+'/'+label+'/descriptor.json',CANGJIE_WORKSPACE:out+'/'+label+'/configuration',GITHUB_ENV:''};
  return {d,e,argv:[process.execPath,source+'/ci/bootstrap/prepare-bootstrap-plans.mjs']};
 };
 const fresh=await prepare('fresh');await run('fresh-parent',fresh.argv,{environment:fresh.e});
 const freshGraph=JSON.parse(read(out+'/fresh/configuration/build-targets.json'));
 const h1=freshGraph.stages.find(s=>s.id==='stage0').commands[0].argv;
 if(h1.includes('--private-tools')||h1.some(x=>x===undefined||x===null))throw Error('retired producer remained');
 record.freshH1Command=h1;save();
 // Cut the actual upper preparation guard back to the old requirement, while
 // leaving real inputs and the downstream graph intact. Restore before build.
 const inputFile=source+'/ci/bootstrap/sdk-inputs.mjs',before=fs.readFileSync(inputFile,'utf8');
 const cut=before.replace('if (!sources || !installations)', 'if (!sources || !installations || !tools?.privateRoot)');
 if(before===cut)throw Error('cut anchor');
 fs.writeFileSync(inputFile,cut);
 const diff=spawnSync('git',['-C',source,'diff','--','ci/bootstrap/sdk-inputs.mjs'],{encoding:'utf8'});
 fs.writeFileSync(out+'/cut.diff',diff.stdout);if(diff.status!==0){fs.writeFileSync(inputFile,before);throw Error('cut diff');}
 try{
  const c=await prepare('cut-missing-private');await run('cut-parent',c.argv,{environment:c.e,expected:1});
  if(!read(out+'/cut-parent.log').includes('NATIVE_INPUT_LOCATIONS_REQUIRED'))throw Error('cut missed target');
  const control=await prepare('cut-control',false,{privateRoot:source});await run('cut-independent-control',control.argv,{environment:control.e});
 }finally{fs.writeFileSync(inputFile,before);}
 const reused=await prepare('reuse',true);await run('reuse-parent',reused.argv,{environment:reused.e});
 const graph=JSON.parse(read(out+'/reuse/configuration/build-targets.json'));
 if(graph.stages.find(s=>s.id==='stage0').commands)throw Error('H1 should reuse real producer');
 for(const id of ['stage0-run','stage1-initial','stage1-std']){
  const stage=graph.stages.find(s=>s.id===id),execution=stage.metadata.selection.compilerExecution;
  if(execution.runtime.install!==descriptor.host.install||execution.std.install!==descriptor.host.install||execution.llvm.install!==descriptor.installations.llvm.install||execution.role!=='separate')throw Error('H1 execution pairing');
 }
 await run('public-stage0-install',[process.execPath,source+'/ci/bootstrap/sdk-build.mjs','--config',out+'/reuse/configuration/build-targets.json','--through','stage0-run','--no-package'],{environment:{...env,CANGJIE_BUILD_JOBS:'8',CMAKE_BUILD_PARALLEL_LEVEL:'8'}});
 const install=out+'/reuse/work/sdk-stage0-run';
 record.install={path:install,entry:read(install+'/bin/cjcj-stage1.entry'),compiler:hash(install+'/libexec/compiler/cjcj-stage1')};save();
 fs.writeFileSync(out+'/hello.cj','main(): Int64 { println("h1-parent-ok"); return 0 }\n');
 await run('installed-compile',[install+'/bin/cjc','--static-std','-O2',out+'/hello.cj','-o',out+'/hello']);
 await run('hello',[out+'/hello'],{environment:{...env,LD_LIBRARY_PATH:install+'/runtime/lib/linux_x86_64_cjnative:'+install+'/lib/linux_x86_64_cjnative'}});
 if(!read(out+'/hello.log').includes('h1-parent-ok'))throw Error('hello oracle');
 const maps=record.steps.find(s=>s.name==='installed-compile').processes.filter(p=>p.exe===install+'/libexec/compiler/cjcj-stage1');
 if(!maps.some(p=>p.maps.includes(install+'/.compiler-exec/runtime/')&&p.maps.includes(install+'/.compiler-exec/third_party/llvm/')))throw Error('actual execution maps missing');
 record.executionLibraries={runtime:hash(install+'/.compiler-exec/runtime/lib/linux_x86_64_cjnative/libcangjie-runtime.so'),llvm:hash(install+'/.compiler-exec/third_party/llvm/lib/libLLVM-15.so')};save();
 await run('source-final-clean',['git','diff','--exit-code'],{cwd:source});rc=0;
}catch(e){record.error=e.stack;console.error(e);}finally{
 for(const key of acquired){const r=spawnSync('bash',['/root/cjtools/measure_claim.sh','release',key],{encoding:'utf8'});record.claims.push({key,releaseRc:r.status,stdout:r.stdout,stderr:r.stderr});}
 record.rc=rc;record.end=new Date().toISOString();save();
}
process.exit(rc);

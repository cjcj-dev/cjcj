#!/usr/bin/env zx
import fs from 'node:fs';
import path from 'node:path';
import {spawn,spawnSync} from 'node:child_process';
import {createHash} from 'node:crypto';
const source=path.resolve(import.meta.dirname,'../..'),root=path.dirname(source),out=root+'/attempt4';
const host='/mnt/cjcj-nvme/impl_full_sdk_sol_1108/inputs/official-host/host-sdk-dQJL56/cangjie';
const seed='/root/collect_ten_v2_sol_1113/matrix-fixed-1114/install';
const native='/mnt/cjcj-data/impl_full_sdk_sol_1108/main-pair-1114/native/install';
const cache='/root/impl_managed_output_sol_1113/merge-matrix-type-fallback/cjcj-source/target';
const ref=process.argv[2];
fs.mkdirSync(out);for(const d of ['home','tmp','native','hashmap'])fs.mkdirSync(out+'/'+d);
const env={PATH:'/usr/local/bin:/usr/bin:/bin',HOME:out+'/home',TMPDIR:out+'/tmp',LANG:'C.UTF-8',LC_ALL:'C.UTF-8'};
const record={ref,source,out,host,seed,native,cache,start:new Date().toISOString(),steps:[],claims:[]};
const save=()=>fs.writeFileSync(out+'/result.json',JSON.stringify(record,null,2));
const read=p=>fs.readFileSync(p,'utf8').trim();
const hash=p=>createHash('sha256').update(fs.readFileSync(p)).digest('hex');
async function run(name,argv,{cwd=out,environment=env,expected=0}={}){
 const fd=fs.openSync(out+'/'+name+'.log','wx'); const row={name,argv,cwd,env:environment,start:new Date().toISOString()};record.steps.push(row);save();
 const child=spawn(argv[0],argv.slice(1),{cwd,env:environment,stdio:['ignore',fd,fd]});
 const seen=new Map(); const timer=setInterval(()=>{const todo=[child.pid];for(let i=0;i<todo.length;i++){const pid=todo[i];try{
  if(!seen.has(pid))seen.set(pid,{pid,exe:fs.readlinkSync(`/proc/${pid}/exe`),cmd:read(`/proc/${pid}/cmdline`).split('\0'),maps:read(`/proc/${pid}/maps`)});
  for(const t of fs.readdirSync(`/proc/${pid}/task`))for(const c of read(`/proc/${pid}/task/${t}/children`).split(/\s+/).filter(Boolean).map(Number))if(!todo.includes(c))todo.push(c);
 }catch{}}},200);
 Object.assign(row,await new Promise((resolve,reject)=>{child.once('error',reject);child.once('close',(rc,signal)=>resolve({rc,signal}));}));
 clearInterval(timer);fs.closeSync(fd);row.end=new Date().toISOString();row.processes=[...seen.values()];save();console.log(name+' rc='+row.rc+' signal='+row.signal);
 if(row.rc!==expected||row.signal)throw Error(name+' expected '+expected);return row;
}
const acquired=[];let rc=1;
try{
 for(const [suffix,cpus] of [['cpu','32-47'],['smt','128-143']]){
  const key='backport_compiler_astra_1112-minheap-'+suffix;
  const r=spawnSync('bash',['/root/cjtools/measure_claim.sh','claim',key,cpus,'compiler minimum managed heap production'],{encoding:'utf8',env:{...env,MEASURE_OWNER_PID:String(process.pid)}});
  record.claims.push({key,cpus,rc:r.status,stdout:r.stdout,stderr:r.stderr});save();if(r.status!==0)throw Error('claim');acquired.push(key);
 }
 const cg='/sys/fs/cgroup'+read('/proc/self/cgroup').split('::').at(-1);
 record.resources=Object.fromEntries(['cpuset.cpus.effective','memory.max','memory.swap.max','cpu.max'].map(k=>[k,read(cg+'/'+k)]));record.limits=read('/proc/self/limits');
 record.topology=Object.fromEntries([32,47].map(c=>[c,read(`/sys/devices/system/cpu/cpu${c}/topology/thread_siblings_list`)]));save();
 if(record.resources['memory.swap.max']!=='0'||!record.limits.match(/Max core file size\s+0\s+0/))throw Error('resources');
 const git=spawnSync('git',['-C',source,'rev-parse','HEAD'],{encoding:'utf8'});if(git.status!==0||git.stdout.trim()!==ref)throw Error('source ref');
 record.adapterRegressionReuse=root+'/attempt1/adapter-regression.log';save();
 const cc='/usr/lib/llvm-15/bin/clang',shim=source+'/runtime_shim',n=out+'/native';
 record.productionReuse=root+'/attempt3/result.json';save();
 await run('private-install',['cp','-a','--reflink=auto',root+'/attempt3/install',out+'/install']);
 const stage=[process.execPath,source+'/ci/bootstrap/sdk-native-stage.mjs','--kind','h1','--source',source,'--sdk',native,'--runtime',host,'--host',host,'--platform','linux_x86_64','--commit',ref,'--jobs','16','--heap','16GB','--cc',cc];
 // Use a genuine generated Cangjie entry/start/finalization lifecycle for
 // target-runtime coverage. The earlier native-only target init cannot stop a
 // scheduler that it never started (attempt2 Fini=-4 is retained).
 await run('target-config-object',[cc,'-std=c11','-O2','-D_POSIX_C_SOURCE=200809L','-c',shim+'/cjc_runtime_config.c','-o',n+'/config.o']);
 await run('target-adapter-object',[cc,'-std=c11','-O2','-c',shim+'/cjc_heap_defaults.c','-o',n+'/target.o']);
 await run('target-observer-object',[cc,'-std=c11','-O2','-c',source+'/tests/compiler_minheap4g/target_probe.c','-o',n+'/target_probe.o']);
 const testLink=[n+'/config.o',n+'/target_probe.o'];
 const adapterLink=[...testLink,n+'/target.o','--wrap=CJ_MRT_CjRuntimeInit','--wrap=CJ_MRT_CjRuntimeInitWithConfigV1'];
 await run('target-cj-compile',[out+'/install/bin/cjc','--static-std','-O2',...adapterLink.flatMap(x=>['--link-option',x]),source+'/tests/compiler_minheap4g/target.cj','-o',n+'/target-cj']);
 await run('target-cj-cut-compile',[out+'/install/bin/cjc','--static-std','-O2',...testLink.flatMap(x=>['--link-option',x]),source+'/tests/compiler_minheap4g/target.cj','-o',n+'/target-cj-cut']);
 for(const [name,request,bytes] of [['default',null,4294967296],['small','256MB',4294967296],['large','6GB',6442450944]]){
  const e={...env,LD_LIBRARY_PATH:out+'/install/runtime/lib/linux_x86_64_cjnative:'+out+'/install/lib/linux_x86_64_cjnative',CJCJ_TEST_HEAP_BYTES:String(bytes),CJCJ_TEST_HEAP_ENV:request??'<unset>'};if(request!==null)e.cjHeapSize=request;
  await run('target-cj-'+name,['timeout','60',n+'/target-cj'],{environment:e});
  if(name!=='default')await run('target-cj-cut-'+name,['timeout','60',n+'/target-cj-cut'],{environment:e,expected:name==='small'?4:0});
 }
 // Instrument only runtime-start observation, then use exactly the same public
 // installed launcher for all three real compiler configurations. No init mock.
 await run('heap-probe-object',[cc,'-std=c11','-O2','-c',source+'/tests/compiler_minheap4g/heap_probe.c','-o',n+'/heap_probe.o']);
 const manifest=source+'/packages/cjc/cjpm.toml',before=fs.readFileSync(manifest,'utf8');
 const instrumented=before.replace('link-option = "--export-dynamic ', 'link-option = "--wrap=CJ_MRT_CjRuntimeStart '+n+'/heap_probe.o --export-dynamic ');
 if(instrumented===before)throw Error('observer insertion');
 fs.writeFileSync(out+'/probe-manifest-before.toml',before);fs.writeFileSync(out+'/probe-manifest.toml',instrumented);
 fs.writeFileSync(manifest,instrumented);
 try{await run('observed-h1-build',[...stage,'--output',out+'/observed-compiler']);}finally{fs.writeFileSync(manifest,before);}
 await run('observed-private-install',['cp','-a','--reflink=auto',out+'/install',out+'/observed-install']);
 fs.copyFileSync(out+'/observed-compiler/bin/cjcj-stage1',out+'/observed-install/libexec/compiler/cjcj-stage1');
 record.observedELF=hash(out+'/observed-install/libexec/compiler/cjcj-stage1');save();
 fs.writeFileSync(out+'/hello.cj','main(): Int64 { return 0 }\n');
 for(const [name,request,bytes] of [['default',null,4294967296],['small','256MB',4294967296],['large','6GB',6442450944]]){
  const e={...env,CJCJ_TEST_HEAP_BYTES:String(bytes)};if(request!==null)e.cjHeapSize=request;
  await run('installed-'+name,[out+'/observed-install/bin/cjc','--static-std','-O2',out+'/hello.cj','-o',out+'/hello-'+name],{environment:e});
  if(!read(out+'/installed-'+name+'.log').includes('COMPILER_HEAP_ACTUAL bytes='+bytes+' env='+(request??'<unset>')))throw Error('actual heap observation');
 }
 rc=0;
}catch(e){record.error=e.stack;console.error(e);}finally{
 for(const key of acquired){const r=spawnSync('bash',['/root/cjtools/measure_claim.sh','release',key],{encoding:'utf8'});record.claims.push({key,releaseRc:r.status,stdout:r.stdout,stderr:r.stderr});}
 record.rc=rc;record.end=new Date().toISOString();save();
}
process.exit(rc);

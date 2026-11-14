#!/usr/bin/env zx
import fs from 'node:fs';
import path from 'node:path';
import {spawn,spawnSync} from 'node:child_process';
import {createHash} from 'node:crypto';
const source=path.resolve(import.meta.dirname,'../..'),root=path.dirname(source),out=root+'/attempt5-r1';
const host='/mnt/cjcj-nvme/impl_full_sdk_sol_1108/inputs/official-host/host-sdk-dQJL56/cangjie';
const seed='/root/collect_ten_v2_sol_1113/matrix-fixed-1114/install';
const native='/mnt/cjcj-data/impl_full_sdk_sol_1108/main-pair-1114/native/install';
const cache='/root/impl_managed_output_sol_1113/merge-matrix-type-fallback/cjcj-source/target';
const ref=process.argv[2],zx=root+'/r1-tools/node_modules/.bin/zx';
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

 const cc='/usr/lib/llvm-15/bin/clang',shim=source+'/runtime_shim',n=out+'/native';
 await run('source-clean',['git','diff','--exit-code'],{cwd:source});
 await run('adapter-regression',[zx,shim+'/tests/compiler_heap_defaults.test.mjs'],
   {environment:{...env,CJCJ_NATIVE_TEST_DIR:out+'/native'}});
 record.reusedEvidence=[root+'/attempt2/result.json',root+'/attempt4/result.json',root+'/entry-control/result.json'];save();
 // Same generated entry and target runtime as the reviewed test. Old candidate
 // succeeds incorrectly; the assertion is rejection before the user main.
 const targetEnv={...env,LD_LIBRARY_PATH:root+'/attempt3/install/runtime/lib/linux_x86_64_cjnative:'+root+'/attempt3/install/lib/linux_x86_64_cjnative'};
 const requests=[['zero','0GB'],['wrap','17592186044416GB'],['base0-zero','08GB']];
 async function rejection(name,exe,request,wantRejected){
  const row=await run(name,[exe],{environment:{...targetEnv,cjHeapSize:request,CJCJ_TEST_HEAP_BYTES:'4294967296',CJCJ_TEST_HEAP_ENV:request},expected:null,timeout:60000});
  const log=read(out+'/'+name+'.log');
  row.rejectionAssertion=!!((row.rc!==0||row.signal)&&log.includes('Invalid cjHeapSize')&&!log.includes('TARGET_HEAP_ACTUAL'));
  row.expectedAssertion=wantRejected;save();
  if(row.rejectionAssertion!==wantRejected)throw Error(name+' rejection assertion');
  if(!wantRejected&&(row.rc!==0||row.signal||!log.includes('TARGET_HEAP_ACTUAL bytes=4294967296')))throw Error(name+' old failure not reproduced');
 }
 for(const [label,request] of requests){
  await rejection('old-'+label,root+'/attempt4/native/target-cj',request,false);
  await rejection('runtime-control-'+label,root+'/attempt4/native/target-cj-cut',request,true);
 }
 const stage=[zx,source+'/ci/bootstrap/sdk-native-stage.mjs','--kind','h1','--source',source,'--sdk',native,'--runtime',host,'--host',host,'--platform','linux_x86_64','--commit',ref,'--jobs','16','--heap','16GB','--cc',cc];
 await run('normal-h1-build',[...stage,'--output',out+'/compiler']);
 record.product={path:out+'/compiler/bin/cjcj-stage1',sha256:hash(out+'/compiler/bin/cjcj-stage1')};save();
 await run('private-install',['cp','-a','--reflink=auto',root+'/attempt3/install',out+'/install']);
 fs.copyFileSync(out+'/compiler/bin/cjcj-stage1',out+'/install/libexec/compiler/cjcj-stage1');
 record.install={path:out+'/install',entry:read(out+'/install/bin/cjcj-stage1.entry'),compiler:hash(out+'/install/libexec/compiler/cjcj-stage1')};save();
 await run('target-config-object',[cc,'-std=c11','-O2','-D_POSIX_C_SOURCE=200809L','-c',shim+'/cjc_runtime_config.c','-o',n+'/config.o']);
 await run('target-adapter-object',[cc,'-std=c11','-O2','-c',shim+'/cjc_heap_defaults.c','-o',n+'/target.o']);
 await run('target-observer-object',[cc,'-std=c11','-O2','-c',source+'/tests/compiler_minheap4g/target_probe.c','-o',n+'/target_probe.o']);
 const link=[n+'/config.o',n+'/target_probe.o',n+'/target.o','--wrap=CJ_MRT_CjRuntimeInit','--wrap=CJ_MRT_CjRuntimeInitWithConfigV1'];
 await run('target-cj-compile',[out+'/install/bin/cjc','--static-std','-O2',...link.flatMap(x=>['--link-option',x]),source+'/tests/compiler_minheap4g/target.cj','-o',n+'/target-cj']);
 record.targetELF=hash(n+'/target-cj');save();
 for(const [label,request] of requests)await rejection('fixed-'+label,n+'/target-cj',request,true);
 const app='/root/collect_ten_v2_sol_1113/matrix-fixed-1114/src-v2/hashmap_count.cj';
 record.hashmapSource={path:app,sha256:hash(app)};save();
 await run('hashmap-compile',[out+'/install/bin/cjc','--static-std','-O2','--link-option','-Map='+out+'/hashmap/link.map',app,'-o',out+'/hashmap/hashmap_count']);
 record.hashmapELF=hash(out+'/hashmap/hashmap_count');save();
 await run('source-final-clean',['git','diff','--exit-code'],{cwd:source});
 rc=0;
}catch(e){record.error=e.stack;console.error(e);}finally{
 for(const key of acquired){const r=spawnSync('bash',['/root/cjtools/measure_claim.sh','release',key],{encoding:'utf8'});record.claims.push({key,releaseRc:r.status,stdout:r.stdout,stderr:r.stderr});}
 record.rc=rc;record.end=new Date().toISOString();save();
}
process.exit(rc);

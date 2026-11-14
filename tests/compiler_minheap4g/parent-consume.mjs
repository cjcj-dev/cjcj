#!/usr/bin/env zx
import fs from 'node:fs';
import path from 'node:path';
import {spawn,spawnSync} from 'node:child_process';
import {createHash} from 'node:crypto';
const source=path.resolve(import.meta.dirname,'../..'),root=path.dirname(source),out=root+'/parent-consume1';
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
 }catch{}}},20);
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



 const prior=JSON.parse(read(root+'/parent-attempt3/result.json'));
 if(prior.steps.find(s=>s.name==='public-stage0-install')?.rc!==0)throw Error('public install not completed');
 const install=prior.install.path,target=root+'/attempt6-r1/install',tuple='linux_x86_64_cjnative';
 record.assemblerInstallRef=prior.assemblerRef;record.compilerRef=prior.compilerRef;
 record.install=prior.install;record.priorFailure=root+'/parent-attempt3/installed-compile.log';
 record.target={install:target,source:'0685ce27686d7cc047118de64cd0d0a23b6fefa3',scope:'explicit public import/library paths; no SDK overlay'};save();
 // stage0-run normally feeds std-bootstrap; its root carries H's 1.3 CJO.
 // For a bounded ordinary application, select existing compatible target std
 // through normal public import/library options. Do not disable version checks
 // or alter the published stage0 SDK to masquerade as stage1.
 fs.copyFileSync(root+'/parent-attempt3/hello.cj',out+'/hello.cj');
 await run('installed-compile',[install+'/bin/cjc','--static-std','-O2',
  '--import-path',target+'/modules/'+tuple,'--library-path',target+'/lib/'+tuple,
  '--library-path',target+'/runtime/lib/'+tuple,'--link-option','-Map='+out+'/hello.link.map',
  out+'/hello.cj','-o',out+'/hello']);
 await run('hello',[out+'/hello'],{environment:{...env,LD_LIBRARY_PATH:target+'/runtime/lib/'+tuple+':'+target+'/lib/'+tuple}});
 if(read(out+'/hello.log')!=='h1-parent-ok')throw Error('hello oracle');
 const maps=record.steps.find(s=>s.name==='installed-compile').processes.filter(p=>p.exe===install+'/libexec/compiler/cjcj-stage1');
 if(!maps.some(p=>p.maps.includes(install+'/.compiler-exec/runtime/')&&p.maps.includes(install+'/.compiler-exec/third_party/llvm/')))throw Error('actual execution maps missing');
 record.executionLibraries={runtime:hash(install+'/.compiler-exec/runtime/lib/'+tuple+'/libcangjie-runtime.so'),llvm:hash(install+'/.compiler-exec/third_party/llvm/lib/libLLVM-15.so')};
 record.helloELF=hash(out+'/hello');save();
 await run('source-final-clean',['git','diff','--exit-code'],{cwd:source});rc=0;
}catch(e){record.error=e.stack;console.error(e);}finally{
 for(const key of acquired){const r=spawnSync('bash',['/root/cjtools/measure_claim.sh','release',key],{encoding:'utf8'});record.claims.push({key,releaseRc:r.status,stdout:r.stdout,stderr:r.stderr});}
 record.rc=rc;record.end=new Date().toISOString();save();
}
process.exit(rc);

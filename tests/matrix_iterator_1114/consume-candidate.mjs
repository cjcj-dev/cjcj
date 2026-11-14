#!/usr/bin/env zx
import fs from 'node:fs';
import path from 'node:path';
import {spawn,spawnSync} from 'node:child_process';
import {createHash} from 'node:crypto';
const root='/mnt/cjcj-nvme/backport_compiler_astra_1112/matrix-current-1114';
const source=root+'/source',out=root+'/consumer-r2';
const built=root+'/candidate-r1/compiler/bin/cjcj-stage1';
const seed='/root/collect_ten_v2_sol_1113/current-main-1114/install';
const assembler='/root/collect_ten_v2_sol_1113/current-main-1114/sources/assembler';
const old='/mnt/cjcj-nvme/impl_full_sdk_sol_1108/main-pair-1114/work';
const native='/mnt/cjcj-data/impl_full_sdk_sol_1108/main-pair-1114/native/install';
const host='/mnt/cjcj-nvme/impl_full_sdk_sol_1108/inputs/official-host/host-sdk-dQJL56/cangjie';
const ref=process.argv[2];
fs.mkdirSync(out);for(const d of ['home','tmp','matrix','declared'])fs.mkdirSync(out+'/'+d);
fs.mkdirSync(out+'/matrix/temps');
const record={ref,source,out,seed,assembler,host,native,start:new Date().toISOString(),steps:[],claims:[]};
const save=()=>fs.writeFileSync(out+'/result.json',JSON.stringify(record,null,2));
const hash=p=>createHash('sha256').update(fs.readFileSync(p)).digest('hex');
const read=p=>fs.readFileSync(p,'utf8').trim();
const original=JSON.parse(fs.readFileSync('/root/collect_ten_v2_sol_1113/current-main-1114/apps/ours/matrix_multiply/run.json'));
const env={...process.env,...original.env,HOME:out+'/home',TMPDIR:out+'/tmp'};
async function run(name,argv,{cwd=out,environment=env,expected=0}={}){
 const fd=fs.openSync(out+'/'+name+'.log','wx');const row={name,argv,cwd,env:environment,start:new Date().toISOString()};record.steps.push(row);save();
 const child=spawn(argv[0],argv.slice(1),{cwd,env:environment,stdio:['ignore',fd,fd]});
 const seen=new Map();const sample=()=>{const todo=[child.pid];for(let n=0;n<todo.length;n++){const pid=todo[n];try{
  const exe=fs.readlinkSync(`/proc/${pid}/exe`),cmd=read(`/proc/${pid}/cmdline`).split('\0');
  if(!seen.has(pid))seen.set(pid,{pid,exe,cmd,maps:fs.readFileSync(`/proc/${pid}/maps`,'utf8')});
  for(const t of fs.readdirSync(`/proc/${pid}/task`))for(const c of read(`/proc/${pid}/task/${t}/children`).split(/\s+/).filter(Boolean).map(Number))if(!todo.includes(c))todo.push(c);
 }catch{}}};const timer=setInterval(sample,100);
 Object.assign(row,await new Promise((resolve,reject)=>{child.once('error',reject);child.once('close',(rc,signal)=>resolve({rc,signal}));}));
 clearInterval(timer);fs.closeSync(fd);row.end=new Date().toISOString();row.processes=[...seen.values()];save();console.log(name+' rc='+row.rc+' signal='+row.signal);
 if(row.rc!==expected||row.signal)throw Error(name+' expected '+expected);return row;
}
const acquired=[];let rc=1;
try{
 for(const [suffix,cpus]of [['cpu','64-71'],['smt','160-167']]){
  const key='backport_compiler_astra_1112-matrix-consumer-r2-'+suffix;
  const r=spawnSync('bash',['/root/cjtools/measure_claim.sh','claim',key,cpus,'matrix candidate entry correction and focused regressions'],{encoding:'utf8',env:{...process.env,MEASURE_OWNER_PID:String(process.pid)}});
  record.claims.push({key,cpus,rc:r.status,stdout:r.stdout,stderr:r.stderr});save();if(r.status!==0)throw Error('claim');acquired.push(key);
 }
 const cg='/sys/fs/cgroup'+read('/proc/self/cgroup').split('::').at(-1);
 record.resources=Object.fromEntries(['cpuset.cpus.effective','memory.max','memory.swap.max','cpu.max'].map(k=>[k,read(cg+'/'+k)]));record.limits=read('/proc/self/limits');
 record.topology=Object.fromEntries([64,71].map(c=>[c,read(`/sys/devices/system/cpu/cpu${c}/topology/thread_siblings_list`)]));save();
 if(record.resources['memory.swap.max']!=='0'||!record.limits.match(/Max core file size\s+0\s+0/))throw Error('resources');
 const git=(dir,...args)=>{const r=spawnSync('git',['-C',dir,...args],{encoding:'utf8'});if(r.status!==0)throw Error(r.stderr);return r.stdout.trim();};
 if(git(source,'rev-parse','HEAD')!==ref||git(source,'status','--porcelain')!=='')throw Error('candidate source');
 if(git(assembler,'rev-parse','HEAD')!=='40a5852b25563486a4da2b654fce43629426009e')throw Error('assembler changed');
 record.shimSourceDiff=git(source,'diff','675435fd495d6ff26ca27eb132de2a953669bffd',ref,'--','runtime_shim');
 if(record.shimSourceDiff)throw Error('native shim source changed');
 record.producerInputs=JSON.parse(fs.readFileSync(old+'/targets/stage0/bin/build-inputs.json'));
 const stage=source+'/tests/matrix_iterator_1114/assert-stage.mjs';
 const declared=source+'/tests/matrix_iterator_1114/declared_result.cj';
 const dump=d=>{const dir=d+'/probe_CHIR';const a=fs.readdirSync(dir).filter(x=>x.endsWith('_Devirtualization.chirtxt'));if(a.length!==1)throw Error('devirt dump');return dir+'/'+a[0];};
 record.product={path:built,buildRef:'5d8b92ef6415f3644ee0e9bf0fade488772b11e1',sha256:hash(built)};
 if(record.product.sha256!=='03b4fa09f06f77ee11cee8ea14da601063e5e1c413ae31ace0b078109af9a9e9')throw Error('built compiler identity');
 record.productSourceDiff=git(source,'diff',record.product.buildRef,ref,'--','packages','runtime_shim');
 if(record.productSourceDiff)throw Error('built compiler source differs');save();
 // Preserve the installer's relative native aliases: the launcher reads self()+'.entry'.
 // All seed aliases were inspected; reject escaping or absolute aliases before copying.
 const aliases=[];function walk(dir){for(const e of fs.readdirSync(dir,{withFileTypes:true})){
  const p=path.join(dir,e.name);if(e.isSymbolicLink()){const target=fs.readlinkSync(p),real=fs.realpathSync(p);aliases.push({path:path.relative(seed,p),target});if(path.isAbsolute(target)||!real.startsWith(seed+'/'))throw Error('non-private alias '+p);}
  else if(e.isDirectory())walk(p);
 }}walk(seed);record.aliases=aliases;save();
 await run('private-sdk-copy',['cp','-a','--reflink=auto',seed,out+'/install']);
 fs.copyFileSync(built,out+'/install/libexec/compiler/cjcj-stage1');
 record.install={root:out+'/install',entry:read(out+'/install/bin/cjcj-stage1.entry'),resolved:fs.realpathSync(out+'/install/bin/cjc'),compiler:hash(out+'/install/libexec/compiler/cjcj-stage1'),libLLVM:hash(out+'/install/third_party/llvm/lib/libLLVM-15.so'),stdCore:hash(out+'/install/lib/linux_x86_64_cjnative/libcangjie-std-core.a'),runtime:hash(out+'/install/runtime/lib/linux_x86_64_cjnative/libcangjie-runtime.so')};save();
 if(record.install.libLLVM!=='639981a2f902523edd2a02f52678301d87f11fc7d17c38ab11ec76bf61c5c99f'||record.install.runtime!=='5f56978bf71fa5d2c013a9dd1bc91fb9d25783c7d1e9b6c2398a94ac1075963a'||record.install.stdCore!==hash(seed+'/lib/linux_x86_64_cjnative/libcangjie-std-core.a'))throw Error('target dependency identity');
 const installed=Object.fromEntries(Object.entries(env).map(([k,v])=>[k,typeof v==='string'?v.replaceAll(seed,out+'/install'):v]));
 const input=source+'/tests/matrix_iterator_1114/matrix_multiply.cj';
 await run('matrix-compile',[out+'/install/bin/cjc','--static-std','-O2','--dump-chir','--save-temps',out+'/matrix/temps','--link-option','-Map='+out+'/matrix/link.map',input,'-o',out+'/matrix/probe'],{environment:installed});
 await run('matrix-green',[process.execPath,stage,dump(out+'/matrix'),'matrix']);
 await run('declared-compile',[out+'/install/bin/cjc','--static-std','-O2','--fno-chir-function-inlining','--dump-chir',declared,'-o',out+'/declared/probe'],{environment:installed});
 await run('declared-green',[process.execPath,stage,dump(out+'/declared'),'declared']);
 record.consumers={matrix:hash(out+'/matrix/probe'),declared:hash(out+'/declared/probe')};save();
 await run('declared-oracle',[out+'/declared/probe'],{environment:installed});
 await run('matrix-oracle',[out+'/matrix/probe','1600','17','11'],{environment:installed});
 record.matrixOracle=read(out+'/matrix-oracle.log')===read('/root/collect_ten_v2_sol_1113/current-main-1114/correctness/ours/matrix_multiply/stdout.txt');save();
 if(!record.matrixOracle)throw Error('matrix oracle mismatch');
 rc=0;
}catch(e){record.error=e.stack;console.error(e);}finally{
 for(const key of acquired){const r=spawnSync('bash',['/root/cjtools/measure_claim.sh','release',key],{encoding:'utf8'});record.claims.push({key,releaseRc:r.status,stdout:r.stdout,stderr:r.stderr});}
 record.rc=rc;record.end=new Date().toISOString();save();
}
process.exit(rc);

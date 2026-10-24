#!/usr/bin/env zx
// Defaults follow the process limits; explicit build choices remain explicit.
import fs from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';
import {fileURLToPath} from 'node:url';
async function optional(file) {
 try {return (await fs.readFile(file,'utf8')).trim();}
 catch(error){if(error.code==='ENOENT')return '';throw error;}
}
export async function buildCapacity() {
 const available=os.availableParallelism();
 const constrained=process.constrainedMemory();
 const memory=Math.min(os.totalmem(),constrained>0?constrained:Infinity);
 let quota=Infinity;
 if(process.platform==='linux') {
  const memberships=(await optional('/proc/self/cgroup')).split('\n').map(line=>line.split(':'));
  const mounts=(await optional('/proc/self/mountinfo')).split('\n');
  const decode=text=>text.replace(/\\([0-7]{3})/g,(_,digits)=>String.fromCharCode(parseInt(digits,8)));
  for(const line of mounts) {
   const [left,right]=line.split(' - ');if(!right)continue;
   const fields=left.split(' '),kind=right.split(' ')[0],options=right.split(' ')[2]||'';
   const member=memberships.find(row=>kind==='cgroup2'?row[0]==='0':kind==='cgroup'&&options.split(',').includes('cpu')&&row[1]?.split(',').includes('cpu'));
   if(!member?.[2])continue;
   const mountRoot=decode(fields[3]),mount=decode(fields[4]),group=member[2];
   // mountinfo root may already be the process cgroup in a cgroup namespace.
   const relative=mountRoot==='/'?group.slice(1):group===mountRoot?'':group.startsWith(mountRoot+'/')?group.slice(mountRoot.length+1):group==='/'?'':null;
   if(relative===null)continue;
   let directory=path.resolve(mount,relative);
   for(;;) {
    let amount,period;
    if(kind==='cgroup2') [amount,period]=(await optional(path.join(directory,'cpu.max'))).split(/\s+/);
    else {amount=await optional(path.join(directory,'cpu.cfs_quota_us'));period=await optional(path.join(directory,'cpu.cfs_period_us'));}
    if(Number(amount)>0&&Number(period)>0)quota=Math.min(quota,Number(amount)/Number(period));
    if(directory===mount)break;
    const parent=path.dirname(directory);
    if(parent===directory||!directory.startsWith(mount+'/'))break;
    directory=parent;
   }
  }
 }
 return {available,quota:Number.isFinite(quota)?quota:null,cpus:Math.max(1,Math.min(available,Math.floor(quota))),memory};
}
export async function selectBuildJobs(requested,env=process.env,capacity) {
 capacity??=await buildCapacity();
 const source=requested!==undefined?'argument':env.CANGJIE_BUILD_JOBS!==undefined?'CANGJIE_BUILD_JOBS':env.CMAKE_BUILD_PARALLEL_LEVEL!==undefined?'CMAKE_BUILD_PARALLEL_LEVEL':'effective CPU';
 const explicit=requested??env.CANGJIE_BUILD_JOBS??env.CMAKE_BUILD_PARALLEL_LEVEL;
 const budget=env.KKK2_JOBS===undefined?Infinity:Number(env.KKK2_JOBS);
 if(budget!==Infinity&&(!Number.isSafeInteger(budget)||budget<1))throw Error('BUILD_JOBS invalid declared KKK2_JOBS='+env.KKK2_JOBS);
 const jobs=explicit===undefined?Math.min(capacity.cpus,budget):Number(explicit);
 if(!Number.isSafeInteger(jobs)||jobs<1)throw Error('BUILD_JOBS invalid '+source+'='+explicit);
 if(jobs>budget)throw Error('BUILD_JOBS '+source+'='+jobs+' exceeds declared KKK2_JOBS budget='+budget);
 return jobs;
}
function heapBytes(value) {
 const match=/^([0-9]+)(KB|MB|GB)$/i.exec(String(value).replace(/\s/g,''));
 if(!match||BigInt(match[1])===0n)throw Error('BUILD_HEAP invalid '+value);
 return BigInt(match[1])*({KB:1024n,MB:1024n**2n,GB:1024n**3n})[match[2].toUpperCase()];
}
export async function selectBuildResources({heap,jobs,defaultHeap='48GB',env=process.env}={}) {
 const capacity=await buildCapacity();
 const requested=heap??env.CJ_HEAP??env.cjHeapSize;
 const source=heap!==undefined?'argument':env.CJ_HEAP!==undefined?'CJ_HEAP':env.cjHeapSize!==undefined?'cjHeapSize':'default';
 const bytes=requested===undefined?BigInt(Math.min(Number(heapBytes(defaultHeap)),Math.floor(capacity.memory*3/4/1024**2)*1024**2)):heapBytes(requested);
 if(bytes>BigInt(capacity.memory))console.error('BUILD_HEAP above observed memory; maximum heap is not RSS: source='+source+' requested='+requested+' bytes='+bytes+' effectiveBytes='+capacity.memory);
 if(bytes===0n)throw Error('BUILD_HEAP effective memory too small: '+capacity.memory);
 const selected={...capacity,heap:requested??(bytes/(1024n**2n)+'MB'),jobs:await selectBuildJobs(jobs,env,capacity),heapSource:source};
 console.error('BUILD_RESOURCES '+JSON.stringify(selected));
 return selected;
}
if(process.argv[1]&&path.resolve(process.argv[1])===fileURLToPath(import.meta.url)) {
 try {
  const args=process.argv.slice(2),json=args.includes('--json'),heap=args.find(arg=>!arg.startsWith('--'));
  if(args.includes('--jobs-only')){console.log(await selectBuildJobs());process.exit(0);}
  const selected=await selectBuildResources({heap,defaultHeap:'96GB'});
  console.log(json?JSON.stringify(selected):"STD_BUILD_HEAP='"+selected.heap+"'\nSTD_BUILD_JOBS="+selected.jobs);
 }catch(error){console.error(error.message);process.exitCode=1;}
}

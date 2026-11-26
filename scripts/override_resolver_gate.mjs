#!/usr/bin/env node
// Observe generic-call target selection through the real compiler CLI.
import fs from 'node:fs/promises';
import path from 'node:path';
import crypto from 'node:crypto';
import {parseArgs} from 'node:util';
import {fileURLToPath} from 'node:url';
import {spawn} from 'node:child_process';
import os from 'node:os';
async function optional(file) {
 try {return (await fs.readFile(file,'utf8')).trim();}
 catch(error){if(error.code==='ENOENT')return '';throw error;}
}
async function buildCapacity() {
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
async function selectBuildJobs(requested,env=process.env,capacity) {
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
const {values}=parseArgs({options:{compiler:{type:'string'},out:{type:'string'},jobs:{type:'string'}}});
if(!values.compiler||!values.out)throw Error('usage: override_resolver_gate.mjs --compiler FILE --out DIRECTORY [--jobs N]');
const compiler=path.resolve(values.compiler),out=path.resolve(values.out);
await fs.mkdir(out,{recursive:true});
const total=await selectBuildJobs(values.jobs),workers=Math.min(2,total),perCompiler=Math.max(1,Math.floor(total/workers));
const fixtures=path.join(path.dirname(fileURLToPath(import.meta.url)),'override_resolver_fixtures');
const digest=async file=>crypto.createHash('sha256').update(await fs.readFile(file)).digest('hex');
const optionalDigest=async file=>{try{return await digest(file);}catch(e){if(e.code==='ENOENT')return null;throw e;}};
const manifest={compiler,compiler_sha256:await digest(compiler),resources:await buildCapacity(),jobs:total,workers,perCompiler,started:new Date().toISOString()};
const names=['generic_override','direct_member'],cases=new Array(names.length);let next=0;
async function check(name){
 const source=path.join(fixtures,name+'.cj'),destination=path.join(out,name);
 await fs.mkdir(destination,{recursive:true});
 const command=[compiler,source,'-O2','--emit-chir=raw','--output-type=staticlib','--dump-chir','--jobs',String(perCompiler),'--diagnostic-format=noColor','-o',path.join(destination,'result.chir')];
 const started=performance.now(),log=await fs.open(path.join(destination,'compile.log'),'w');
 let result;
 try {result=await new Promise(resolve=>{const child=spawn(command[0],command.slice(1),{cwd:destination,stdio:['ignore',log.fd,log.fd]});child.once('error',error=>resolve({rc:null,signal:null,error:error.message}));child.once('close',(rc,signal)=>resolve({rc,signal}));});}
 finally{await log.close();}
 const dump=path.join(destination,'result_Emit_Debug.chirtxt');
 const text=await fs.readFile(dump,'utf8').catch(e=>{if(e.code==='ENOENT')return '';throw e;});
 const target=name==='generic_override'?'invoke':'main';
 const selected=text.split(/(?=^\[.*\] Func )/m).filter(block=>{
  const heading=block.split('{',1)[0];
  return heading.includes('srcCodeIdentifier: '+target+',')&&heading.includes('packageName: resolver_fixture')&&(name!=='generic_override'||block.split('\n',1)[0].includes('[generic_instantiated]'));
 });
 const calls=selected.flatMap(block=>block.split('\n')).filter(line=>/\b(?:Apply|Invoke)\(/.test(line)&&line.includes('3fooH')).map(line=>line.trim());
 const expected='@_CN16resolver_fixture1C3fooHv',targetOk=selected.length===1&&calls.length===1&&calls[0].includes(expected);
 const record={name,command,...result,source_sha256:await digest(source),wall:(performance.now()-started)/1000,function_count:selected.length,calls,expected_target:expected,assertion_executed:true,target_ok:targetOk,pass:result.rc===0&&targetOk,dump_sha256:await optionalDigest(dump),chir_sha256:await optionalDigest(path.join(destination,'result.chir'))};
 console.log((record.pass?'PASS':'FAIL')+' '+name+' rc='+result.rc+' target_ok='+targetOk+' calls='+JSON.stringify(calls));return record;
}
await Promise.all(Array.from({length:workers},async()=>{for(;;){const index=next++;if(index>=names.length)return;cases[index]=await check(names[index]);}}));
await fs.writeFile(path.join(out,'result.json'),JSON.stringify({...manifest,cases,ended:new Date().toISOString()},null,2)+'\n');
process.exitCode=cases.every(row=>row.pass)?0:1;

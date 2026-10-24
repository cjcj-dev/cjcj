#!/usr/bin/env zx
// Observe generic-call target selection through the real compiler CLI.
import fs from 'node:fs/promises';
import path from 'node:path';
import crypto from 'node:crypto';
import {parseArgs} from 'node:util';
import {fileURLToPath} from 'node:url';
import {spawn} from 'node:child_process';
import {selectBuildJobs,buildCapacity} from '../ci/build-resources.mjs';
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

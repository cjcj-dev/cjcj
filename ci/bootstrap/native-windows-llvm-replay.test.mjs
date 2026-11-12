import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';
import {spawnSync} from 'node:child_process';
import {fileURLToPath} from 'node:url';

const fixture=fileURLToPath(new URL('../fixtures/windows-tracerpt-43236671148/',import.meta.url));
const original=process.env.TRACE_REPLAY_ORIGINAL||fixture;
const entry=fileURLToPath(new URL('./native-windows-llvm-decode.mjs',import.meta.url));
const raw=await fs.readFile(path.join(original,'host-llvm.xml'),'utf8');
const capture=JSON.parse(await fs.readFile(path.join(original,'capture.json'),'utf8'));
async function replay(t,transform=x=>x,configure=()=>{}) {
 const work=await fs.mkdtemp(path.join(process.env.TRACE_TEST_EVIDENCE||os.tmpdir(),'etw-replay-'));
 if(!process.env.TRACE_TEST_EVIDENCE)t.after(()=>fs.rm(work,{recursive:true,force:true}));
 const config={xml:path.join(work,'raw.xml'),eventsFile:path.join(work,'events.json'),
  python:process.env.PYTHON||'python3',output:path.join(work,'result.json'),
  execution:capture.execution,parentPid:capture.parentPid,devices:capture.devices,
  executable:capture.argv[0],library:path.win32.join(path.win32.dirname(capture.argv[0]),'libLLVM-15.dll')};
 await fs.writeFile(config.xml,transform(raw));configure(config);
 const input=path.join(work,'config.json');await fs.writeFile(input,JSON.stringify(config));
 const p=spawnSync(process.execPath,[entry,input],{encoding:'utf8'});
 await fs.writeFile(path.join(work,'command-result.json'),JSON.stringify({argv:[process.execPath,entry,input],rc:p.status,signal:p.signal,stdout:p.stdout,stderr:p.stderr}));
 return {...p,config,result:await fs.readFile(config.output,'utf8').then(JSON.parse,()=>null)};
}
test('recorded Windows tracerpt output reaches the observed LLVM load assertion',async t=>{
 const p=await replay(t);assert.equal(p.status,0,p.stderr);
 assert.match(p.stdout,/TRACE_LLVM_PAYLOAD_ASSERTION_REACHED 1/);
 assert.equal(p.result.pid,10160);assert.deepEqual(p.result.loss,{events:0,buffers:0});
 assert.deepEqual(p.result.loaded,[p.config.library.toLowerCase()]);
 assert.equal(p.result.lifetime.key,'0xFFFFBB07653EA0C0');
 assert.equal(p.result.events[0].payload.ProcessId,'   10160');
});
for(const [name,transform,reason] of [
 ['header removed',x=>x.replace(/<Event xmlns=[\s\S]*?<\/Event>/,''),'TRACE_LOG_HEADER_REQUIRED'],
 ['wrong provider',x=>x.replaceAll('9e814aad-3204-11d2-9a82-006008a86939','00000000-0000-0000-0000-000000000000'),'TRACE_LOG_HEADER_REQUIRED'],
 ['event GUID missing',x=>x.replace(/<EventGuid>[^<]*<\/EventGuid>/g,''),'TRACE_LOG_HEADER_REQUIRED'],
 ['header type misidentified',x=>x.replaceAll('68fdd900-4a3e-11d1-84f4-0000f80464e3','3d6fa8d0-fe05-11d0-9dda-00c04fd7ba7c'),'TRACE_LOG_HEADER_REQUIRED'],
 ['events lost',x=>x.replace(/(Name="EventsLost">)\s*0/,'$1       1'),'TRACE_EVENTS_LOST'],
 ['buffers lost',x=>x.replace(/(Name="BuffersLost">)\s*0/,'$1       1'),'TRACE_EVENTS_LOST'],
 ['loss field missing',x=>x.replace(/<Data Name="EventsLost">[^<]*<\/Data>/,''),'TRACE_INTEGER'],
 ['wrong LLVM load identity',x=>x.replaceAll('llvm\\bin\\libLLVM-15.dll','other\\bin\\libLLVM-15.dll'),'TRACE_LLVM_LOAD_MISMATCH'],
 ['only rundown LLVM load',x=>x.replace(/<Event xmlns=[\s\S]*?<\/Event>/g,e=>e.includes('\\libLLVM-15.dll</Data>')?e.replace('<Opcode>10</Opcode>','<Opcode>3</Opcode>'):e),'TRACE_LLVM_LOAD_MISMATCH'],
 ['malformed XML',x=>x.slice(0,-20),'ParseError'],
])test('recorded trace rejects '+name,async t=>{
 const p=await replay(t,transform);assert.equal(p.status,1,p.stderr);assert.match(p.stderr,new RegExp(reason));assert.equal(p.result,null);
 if(reason==='TRACE_LLVM_LOAD_MISMATCH')assert.match(p.stdout,/TRACE_LLVM_PAYLOAD_ASSERTION_REACHED/);
});
test('missing XML cannot qualify a successful target command',async t=>{
 const p=await replay(t,x=>x,c=>c.xml+='.missing');assert.equal(p.status,1);assert.match(p.stderr,/FileNotFoundError/);assert.equal(p.result,null);
});

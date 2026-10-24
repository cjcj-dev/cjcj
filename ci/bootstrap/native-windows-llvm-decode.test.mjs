import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';
import {spawnSync} from 'node:child_process';
import {fileURLToPath} from 'node:url';
import {ETW_HEADER,ETW_PROCESS,ETW_IMAGE,traceWindowsPath} from './native-windows-llvm-decode.mjs';

const entry=fileURLToPath(new URL('./native-windows-llvm-decode.mjs',import.meta.url));
const executable=String.raw`C:\SDK & 测试\bin\llc.exe`,library=String.raw`C:\SDK & 测试\bin\libLLVM-15.dll`;
const devices={systemRoot:'C:\\Windows',drives:[{drive:'C:',device:String.raw`\Device\HarddiskVolume3`}]};
const instant=n=>`2026-10-20T12:00:00.${n}Z`;
const row=(provider,opcode,time,data)=>({provider,opcode,time:instant(time),data});
function original() {
 return [row(ETW_HEADER,0,'0000000',{EventsLost:0,BuffersLost:0,EndTime:'134054352010000000'}),
  row(ETW_PROCESS,1,'0010000',{ProcessId:72,ParentId:70,UniqueProcessKey:'0xffff123456780000',ImageFileName:'llc.exe'}),
  row(ETW_IMAGE,10,'0009000',{ProcessId:72,FileName:executable}),
  row(ETW_IMAGE,10,'0020000',{ProcessId:72,FileName:String.raw`\Device\HarddiskVolume3\SDK & 测试\bin\libLLVM-15.dll`}),
  row(ETW_PROCESS,2,'0095000',{ProcessId:72,ParentId:70,UniqueProcessKey:'0xffff123456780000',ExitStatus:0})];
}
const escape=value=>String(value).replaceAll('&','&amp;').replaceAll('<','&lt;').replaceAll('"','&quot;');
function xml(rows) {
 return '<?xml version="1.0" encoding="UTF-8"?><Events xmlns="http://schemas.microsoft.com/win/2004/08/events/event">'+rows.map(e=>
  `<Event><System><Provider Guid="{${e.provider}}"/><Opcode>${e.opcode}</Opcode><TimeCreated SystemTime="${e.time}"/><Execution ProcessID="999"/></System><EventData>`+
  Object.entries(e.data).map(([k,v])=>`<Data Name="${k}">${escape(v)}</Data>`).join('')+'</EventData></Event>').join('')+'</Events>';
}
async function cli(t,change=()=>{},textChange=x=>x) {
 const work=await fs.mkdtemp(path.join(process.env.TRACE_TEST_EVIDENCE||os.tmpdir(),'etw-decode-'));
 if(!process.env.TRACE_TEST_EVIDENCE)t.after(()=>fs.rm(work,{recursive:true,force:true}));
 const events=original(),config={xml:path.join(work,'raw.xml'),eventsFile:path.join(work,'events.json'),
  python:process.env.PYTHON||'python3',output:path.join(work,'result.json'),executable,library,devices,parentPid:70,
  execution:{pid:72,rc:0,started:instant('000'),ended:instant('009')}};
 change(events,config);await fs.writeFile(config.xml,textChange(xml(events)));
 await fs.writeFile(path.join(work,'config.json'),JSON.stringify(config));
 const p=spawnSync(process.execPath,[entry,path.join(work,'config.json')],{encoding:'utf8'});
 return {...p,config,result:await fs.readFile(config.output,'utf8').then(JSON.parse,()=>null)};
}
test('public decoder reads actual XML, payload PID, device mapping and submillisecond exit',async t=>{
 const p=await cli(t);assert.equal(p.status,0,p.stderr);assert.equal(p.result.status,'DECODED');
 assert.deepEqual(p.result.loaded,[library.toLowerCase()]);assert.equal(p.result.events[0].payload.ProcessId,'72');
 assert.match(p.stdout,/TRACE_XML_EVENTS 5/);assert.match(p.stdout,/TRACE_LLVM_PAYLOAD_ASSERTION_REACHED 1/);
});
test('wrong LLVM payload path reaches and fails the load invariant',async t=>{
 const p=await cli(t,e=>e[3].data.FileName=String.raw`C:\other\libLLVM-15.dll`);
 assert.equal(p.status,1);assert.match(p.stdout,/TRACE_LLVM_PAYLOAD_ASSERTION_REACHED 1/);
 assert.match(p.stderr,/TRACE_LLVM_LOAD_MISMATCH/);assert.equal(p.result,null);
});
for(const [name,change,reason] of [
 ['other PID cannot supply a load',e=>e[3].data.ProcessId=999,'TRACE_LLVM_LOAD_MISMATCH'],
 ['rundown cannot supply a load',e=>e[3].opcode=3,'TRACE_LLVM_LOAD_MISMATCH'],
 ['post-exit image cannot supply a load',e=>e[3].time=instant('0100000'),'TRACE_LLVM_LOAD_MISMATCH'],
 ['PID reuse is not the same lifetime',e=>e[4].data.UniqueProcessKey='0xffff123456780001','TRACE_PROCESS_LIFETIME'],
 ['multiple process starts are ambiguous',e=>e.push({...e[1]}),'TRACE_PROCESS_LIFETIME'],
 ['wrong parent is not this spawn',e=>e[1].data.ParentId=71,'TRACE_PROCESS_LIFETIME'],
 ['missing executable event is rejected',e=>e.splice(2,1),'TRACE_EXECUTABLE_LOAD_MISSING'],
 ['event loss is rejected',e=>e[0].data.EventsLost=1,'TRACE_EVENTS_LOST'],
 ['buffer loss is rejected',e=>e[0].data.BuffersLost=1,'TRACE_EVENTS_LOST'],
 ['unfinished log is rejected',e=>e[0].data.EndTime=0,'TRACE_NOT_FINALIZED'],
 ['header is required',e=>e.shift(),'TRACE_LOG_HEADER_REQUIRED'],
 ['failed target cannot qualify',(_e,c)=>c.execution.rc=9,'TRACE_TARGET_NOT_SUCCESSFUL'],
 ['header PID cannot replace missing payload',e=>delete e[3].data.ProcessId,'TRACE_INTEGER'],
 ['unknown device is rejected',e=>e[3].data.FileName=String.raw`\Device\Unknown\libLLVM-15.dll`,'TRACE_DEVICE_PATH_UNRESOLVED'],
])test(name,async t=>{const p=await cli(t,change);assert.equal(p.status,1,p.stderr);assert.match(p.stderr,new RegExp(reason));assert.equal(p.result,null);});
test('duplicate payload does not silently replace the observed path',async t=>{
 const p=await cli(t,()=>{},x=>x.replace('</EventData>','<Data Name="EventsLost">0</Data></EventData>'));
 assert.equal(p.status,1);assert.match(p.stderr,/TRACE_XML_PAYLOAD_DUPLICATE/);
});
test('DTD expansion is rejected by the actual XML reader',async t=>{
 const p=await cli(t,()=>{},x=>x.replace('<Events','<!DOCTYPE Events [<!ENTITY x "bad">]><Events'));
 assert.equal(p.status,1);assert.match(p.stderr,/TRACE_XML_DTD/);
});
test('NT path prefixes and actual SystemRoot mapping',()=>{
 for(const prefix of ['\\??\\','\\\\?\\'])assert.equal(traceWindowsPath(prefix+library,devices),library.toLowerCase());
 assert.equal(traceWindowsPath(String.raw`\SystemRoot\System32\ntdll.dll`,devices),'c:\\windows\\system32\\ntdll.dll');
});

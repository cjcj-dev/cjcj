#!/usr/bin/env zx
// Decode tracerpt originals; requested paths and PE imports are not load events.
import path from 'node:path';
import {fileURLToPath} from 'node:url';
import {command,atomicJson,readJson} from './sdk-flow.mjs';

export const ETW_IMAGE='2cb15d1d-5fc1-11d2-abe1-00a0c911f518';
export const ETW_PROCESS='3d6fa8d0-fe05-11d0-9dda-00c04fd7ba7c';
export const ETW_HEADER='68fdd900-4a3e-11d1-84f4-0000f80464e3';
// Python's standard XML reader handles namespaces, XML encodings and entities.
// No fixture or platform override enters the Windows capture function.
export const TRACE_XML_READER=String.raw`import json,sys,xml.etree.ElementTree as E
class NoDTD(E.TreeBuilder):
 def doctype(self,*args): raise ValueError('TRACE_XML_DTD')
root=E.parse(sys.argv[1],parser=E.XMLParser(target=NoDTD())).getroot()
local=lambda tag:tag.rsplit('}',1)[-1]
child=lambda node,name:next((e for e in node if local(e.tag)==name),None)
rows=[]
for e in root.iter():
 if local(e.tag)!='Event': continue
 s=child(e,'System')
 if s is None: raise ValueError('TRACE_XML_SYSTEM')
 p=child(s,'Provider')
 guid=p.get('Guid','').strip('{}').lower() if p is not None else ''
 if guid not in ('${ETW_IMAGE}','${ETW_PROCESS}','${ETW_HEADER}'): continue
 op=child(s,'Opcode');tm=child(s,'TimeCreated')
 if op is None or tm is None: raise ValueError('TRACE_XML_EVENT_HEADER')
 data={}
 for group in e:
  if local(group.tag) not in ('EventData','UserData'): continue
  for d in group.iter():
   if d is group or len(d): continue
   name=d.get('Name') if local(d.tag)=='Data' else local(d.tag)
   if not name or name in data: raise ValueError('TRACE_XML_PAYLOAD_DUPLICATE')
   data[name]=d.text or ''
 rows.append(dict(provider=guid,opcode=op.text,time=tm.get('SystemTime'),data=data))
with open(sys.argv[2],'w',encoding='utf-8') as f:json.dump(rows,f)
print('TRACE_XML_EVENTS',len(rows))
`;
function integer(value) {
 if(typeof value==='number'&&!Number.isSafeInteger(value))throw Error('TRACE_INTEGER');
 if(!/^(?:0x[0-9a-f]+|\d+)$/i.test(String(value)))throw Error('TRACE_INTEGER '+value);
 return BigInt(value);
}
function ticks(value) {
 const match=/^(\d{4}-\d\d-\d\dT\d\d:\d\d:\d\d)(?:\.(\d{1,7}))?Z$/.exec(value||'');
 if(!match||!Number.isFinite(Date.parse(match[1]+'Z')))throw Error('TRACE_TIME');
 return BigInt(Date.parse(match[1]+'Z'))*10000n+BigInt((match[2]||'').padEnd(7,'0'));
}
export function traceWindowsPath(value,devices) {
 if(typeof value!=='string'||value.includes('\0'))throw Error('TRACE_IMAGE_PATH');
 let file=value.replaceAll('/','\\');
 if(/^\\(?:\?\?\\|\\\?\\)/.test(file))file=file.replace(/^\\(?:\?\?\\|\\\?\\)/,'');
 if(/^\\SystemRoot\\/i.test(file)&&devices.systemRoot)file=devices.systemRoot+file.slice(11);
 if(/^\\Device\\/i.test(file)) {
  const candidates=(devices.drives||[]).filter(row=>file.toLowerCase().startsWith(row.device.toLowerCase()+'\\'));
  if(candidates.length!==1)throw Error('TRACE_DEVICE_PATH_UNRESOLVED');
  file=candidates[0].drive+file.slice(candidates[0].device.length);
 }
 if(!/^[a-z]:\\/i.test(file))throw Error('TRACE_IMAGE_PATH_UNRESOLVED');
 return path.win32.normalize(file).toLowerCase();
}
export function attributeWindowsLlvm(events,{execution,executable,library,devices,parentPid}) {
 if(execution?.rc!==0||execution.signal||execution.error||execution.timedOut||execution.cancelled
   ||!Number.isSafeInteger(execution.pid)||execution.pid<=0)throw Error('TRACE_TARGET_NOT_SUCCESSFUL');
 const pid=BigInt(execution.pid),begin=ticks(execution.started),finish=ticks(execution.ended);
 const headers=events.filter(e=>e.provider===ETW_HEADER&&integer(e.opcode)===0n);
 if(headers.length!==1)throw Error('TRACE_LOG_HEADER_REQUIRED');
 const h=headers[0].data;
 if(integer(h.EventsLost)!==0n||integer(h.BuffersLost)!==0n)throw Error('TRACE_EVENTS_LOST');
 if(integer(h.EndTime)===0n)throw Error('TRACE_NOT_FINALIZED');
 const process=events.filter(e=>e.provider===ETW_PROCESS&&integer(e.data.ProcessId)===pid);
 const starts=process.filter(e=>integer(e.opcode)===1n),ends=process.filter(e=>integer(e.opcode)===2n);
 if(starts.length!==1||ends.length!==1)throw Error('TRACE_PROCESS_LIFETIME');
 const start=starts[0],end=ends[0],first=ticks(start.time),last=ticks(end.time);
 // Date.toISOString records milliseconds; the close callback's fractional
 // millisecond is unavailable. Use its exclusive next-millisecond boundary.
 if(first<begin||last>=finish+10000n||last<first||integer(start.data.UniqueProcessKey)!==integer(end.data.UniqueProcessKey)
   ||integer(start.data.ParentId)!==integer(parentPid)||integer(end.data.ExitStatus)!==0n)
  throw Error('TRACE_PROCESS_LIFETIME');
 if(path.win32.basename(start.data.ImageFileName||'').toLowerCase()!==path.win32.basename(executable).toLowerCase())
  throw Error('TRACE_PROCESS_IMAGE');
 // System.Execution.ProcessID may be the kernel logger. Attribute exclusively
 // with the image payload ProcessId and the recorded spawn lifetime.
 // The initial executable mapping can precede the Process/Start notification.
 // A unique Start/End pair plus the actual spawn interval excludes PID reuse.
 const images=events.filter(e=>e.provider===ETW_IMAGE&&integer(e.opcode)===10n
   &&integer(e.data.ProcessId)===pid&&ticks(e.time)>=begin&&ticks(e.time)<=last);
 const resolved=images.map(e=>({...e,path:traceWindowsPath(e.data.FileName,devices)}));
 if(!resolved.some(e=>e.path===traceWindowsPath(executable,devices)))throw Error('TRACE_EXECUTABLE_LOAD_MISSING');
 const llvm=resolved.filter(e=>/^(?:lib)?LLVM(?:-[\d.]+)?\.dll$/i.test(path.win32.basename(e.path)));
 console.log('TRACE_LLVM_PAYLOAD_ASSERTION_REACHED '+llvm.length);
 if(!llvm.length||llvm.some(e=>e.path!==traceWindowsPath(library,devices)))throw Error('TRACE_LLVM_LOAD_MISMATCH');
 return {status:'DECODED',method:'ETW/tracerpt',pid:execution.pid,
  lifetime:{start:start.time,end:end.time,key:start.data.UniqueProcessKey},
  loss:{events:0,buffers:0},loaded:[...new Set(llvm.map(e=>e.path))],
  events:llvm.map(e=>({time:e.time,provider:e.provider,opcode:e.opcode,payload:e.data,path:e.path}))};
}
export async function decodeWindowsTrace({xml,eventsFile,python='python',execution,executable,library,devices,parentPid},run) {
 await run([python,'-I','-B','-c',TRACE_XML_READER,xml,eventsFile]);
 return attributeWindowsLlvm(await readJson(eventsFile),{execution,executable,library,devices,parentPid});
}
if(process.argv[1]&&path.resolve(process.argv[1])===fileURLToPath(import.meta.url)) {
 const records=[];
 try {
  const config=await readJson(process.argv[2]);
  const result=await decodeWindowsTrace(config,argv=>command(argv,{records}));
  await atomicJson(config.output,result);console.log(JSON.stringify(result));
 }catch(error){console.error(error.stack);process.exitCode=error.rc||1;}
}

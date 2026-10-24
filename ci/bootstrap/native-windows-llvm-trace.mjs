#!/usr/bin/env zx
// Native ETW capture and attribution from the same process's decoded events.
import fs from 'node:fs/promises';
import path from 'node:path';
import {spawn} from 'node:child_process';
import {fileURLToPath} from 'node:url';
import {atomicJson,fileDigest,privateRoot,readJson,withProcessCancellation} from './sdk-flow.mjs';
import {decodeWindowsTrace} from './native-windows-llvm-decode.mjs';

export const WINDOWS_DEVICE_MAP=String.raw`
$ErrorActionPreference = 'Stop'
Add-Type -TypeDefinition 'using System; using System.Text; using System.Runtime.InteropServices;
public static class TraceDosDevice { [DllImport("kernel32.dll", CharSet=CharSet.Unicode, SetLastError=true)]
public static extern uint QueryDosDevice(string name, StringBuilder target, int size); }'
$rows = @()
foreach ($drive in [Environment]::GetLogicalDrives()) {
  $name=$drive.Substring(0,2); $target=New-Object System.Text.StringBuilder 32768
  if ([TraceDosDevice]::QueryDosDevice($name,$target,$target.Capacity) -gt 0) {
    $rows += @{drive=$name; device=$target.ToString().Split([char]0)[0]}
  }
}
@{systemRoot=$env:SystemRoot; drives=@($rows)} | ConvertTo-Json -Depth 4 -Compress
`;

export function windowsTraceCommands(work,tools) {
  const etl=path.join(work,'host-llvm.etl');
  return {
    provider:[tools.logman,'query','providers','Windows Kernel Trace'],
    start:[tools.logman,'start','NT Kernel Logger','-p','Windows Kernel Trace','(process,img)','-o',etl,'-ets'],
    stop:[tools.logman,'stop','NT Kernel Logger','-ets'],
    decode:[tools.tracerpt,etl,'-o',path.join(work,'host-llvm.xml'),'-of','XML',
      '-summary',path.join(work,'host-llvm-summary.txt')],
  };
}

// Direct file descriptors preserve arbitrary native output without buffering
// it or turning a pipe's rc into the target's rc. No shell is involved.
export async function capturedTraceCommand(argv,{work,label,env=process.env,signal,timeoutMs=30000}) {
  if(!/^[a-z0-9-]+$/.test(label))throw Error('TRACE_COMMAND_LABEL');
  if(!Number.isSafeInteger(timeoutMs)||timeoutMs<=0)throw Error('TRACE_COMMAND_TIMEOUT');
  const stdout=label+'.stdout',stderr=label+'.stderr';
  const out=await fs.open(path.join(work,stdout),'wx');
  let err;
  try {err=await fs.open(path.join(work,stderr),'wx');}
  catch(error){await out.close();throw error;}
  const row={argv,cwd:work,started:new Date().toISOString(),pid:null,rc:null,signal:null,stdout,stderr};
  let timer,child,abort;
  try {
    await new Promise(resolve=>{
      if(signal?.aborted){row.cancelled=true;resolve();return;}
      child=spawn(argv[0],argv.slice(1),{cwd:work,env,stdio:['ignore',out.fd,err.fd],windowsHide:true});
      row.pid=child.pid??null;
      child.once('error',error=>{row.error={code:error.code,message:error.message};});
      child.once('close',(rc,childSignal)=>{
        if(row.pid===null&&row.error)row.spawnCloseCode=rc;else row.rc=rc;
        row.signal=childSignal;resolve();
      });
      abort=()=>{row.cancelled=true;child.kill('SIGKILL');};
      signal?.addEventListener('abort',abort,{once:true});
      timer=setTimeout(()=>{row.timedOut=true;child.kill('SIGKILL');},timeoutMs);
      if(signal?.aborted)abort();
    });
  } finally {
    clearTimeout(timer);if(abort)signal?.removeEventListener('abort',abort);
    await out.close();await err.close();row.ended=new Date().toISOString();
    await atomicJson(path.join(work,label+'.json'),row);
  }
  return row;
}
export function requireTraceCommand(row) {
  console.log('TRACE_COMMAND_RESULT_ASSERTION_REACHED '+JSON.stringify({pid:row.pid,rc:row.rc}));
  if(row.rc!==0||row.signal||row.error||row.cancelled||row.timedOut)
    throw Object.assign(Error('WINDOWS_TRACE_COMMAND_FAILED '+row.argv[0]),{command:row,rc:row.rc||1});
  return row;
}

export async function captureWindowsHostLlvm({host,work,tools,env=process.env},signal) {
  if(process.platform!=='win32'||process.arch!=='x64')throw Error('WINDOWS_TRACE_NATIVE_HOST_REQUIRED');
  // Explicit tools supplied by the admitted native host, never fetched here.
  if(!host||!work||!tools?.logman||!tools?.tracerpt)throw Error('WINDOWS_TRACE_INPUTS');
  const root=await fs.realpath(host),output=await privateRoot(work);
  const llc=await fs.realpath(path.join(root,'third_party/llvm/bin/llc.exe'));
  const library=await fs.realpath(path.join(root,'third_party/llvm/bin/libLLVM-15.dll'));
  if(!llc.toLowerCase().startsWith(root.toLowerCase()+path.sep))throw Error('WINDOWS_TRACE_HOST_ESCAPE');
  if(!library.toLowerCase().startsWith(root.toLowerCase()+path.sep))throw Error('WINDOWS_TRACE_HOST_ESCAPE');
  const nativeTools={logman:await fs.realpath(tools.logman),tracerpt:await fs.realpath(tools.tracerpt)};
  // A fresh attempt cannot overwrite ETL, command results or prior failures.
  await fs.mkdir(output,{recursive:false});
  const spec=windowsTraceCommands(output,nativeTools),commands=[],resultFile=path.join(output,'capture.json');
  const result={host:root,parentPid:process.pid,argv:[llc,'--version'],executableSha256:await fileDigest(llc),
    tools:{logman:{path:nativeTools.logman,sha256:await fileDigest(nativeTools.logman)},
      tracerpt:{path:nativeTools.tracerpt,sha256:await fileDigest(nativeTools.tracerpt)}},
    commands,observation:{status:'NOT_DECODED',reason:'native payload/lifetime/path/loss validation required'}};
  const run=async(label,argv,commandSignal=signal,onResult=()=>{})=>{
    const row=await capturedTraceCommand(argv,{work:output,label,env,signal:commandSignal});
    onResult(row);
    commands.push({...row,record:label+'.json'});await atomicJson(resultFile,result);
    return requireTraceCommand(row);
  };
  let owned=false,failure;
  try {
    const powershell=tools.powershell||path.join(env.SystemRoot||env.SYSTEMROOT||'',
      'System32/WindowsPowerShell/v1.0/powershell.exe');
    if(!path.isAbsolute(powershell))throw Error('WINDOWS_TRACE_SYSTEM_ROOT_REQUIRED');
    const deviceRow=await run('devices',[powershell,'-NoProfile','-NonInteractive','-Command',WINDOWS_DEVICE_MAP]);
    result.devices=JSON.parse((await fs.readFile(path.join(output,deviceRow.stdout),'utf8')).replace(/^\uFEFF/,''));
    await run('provider',spec.provider);
    // Never stop an existing session when this start fails or is refused.
    await run('start',spec.start,signal,row=>{if(row.rc===0&&!row.error)owned=true;});
    result.execution=await run('host-llvm',result.argv);
  } catch(error){failure=error;}
  finally {
    if(owned) {
      try{await run('stop',spec.stop,null);}
      catch(error){result.stopFailure=error.message;failure??=error;}
    }
  }
  // A failed llc invocation still leaves its raw trace and original command rc.
  // Export whenever our session stopped successfully, even if llc was red.
  if(owned&&!result.stopFailure) {
    try {
      await run('decode',spec.decode);
      result.originals={};
      for(const name of ['host-llvm.etl','host-llvm.xml','host-llvm-summary.txt']) {
        const file=path.join(output,name),stat=await fs.stat(file);
        if(!stat.isFile()||!stat.size)throw Error('WINDOWS_TRACE_MISSING_ORIGINAL '+name);
        result.originals[name]={path:name,bytes:stat.size,sha256:await fileDigest(file)};
      }
      if(!failure) {
        const observation=await decodeWindowsTrace({xml:path.join(output,'host-llvm.xml'),
          eventsFile:path.join(output,'host-llvm-events.json'),python:tools.python||'python',
          execution:result.execution,executable:llc,library,devices:result.devices,parentPid:result.parentPid},
          argv=>run('parse-events',argv));
        const loaded=[];
        for(const observed of observation.loaded) {
          const actual=await fs.realpath(observed);
          if(actual.toLowerCase()!==library.toLowerCase())throw Error('WINDOWS_TRACE_LOADED_FILE_MISMATCH');
          loaded.push(actual);
        }
        result.execution.loaded=loaded;
        result.observation=observation;
        result.library={path:library,sha256:await fileDigest(library)};
        const file=path.join(output,'host-llvm-events.json');
        result.originals['host-llvm-events.json']={path:'host-llvm-events.json',bytes:(await fs.stat(file)).size,sha256:await fileDigest(file)};
      }
    } catch(error){result.decodeFailure=error.message;failure??=error;}
  }
  result.captureRc=failure?.rc??(failure?1:0);
  if(failure)result.error=failure.message;
  await atomicJson(resultFile,result);
  if(failure)throw failure;
  return {record:resultFile,sha256:await fileDigest(resultFile),...result};
}

if(process.argv[1]&&path.resolve(process.argv[1])===fileURLToPath(import.meta.url)) {
  try {
    const result=await withProcessCancellation(async signal=>captureWindowsHostLlvm(await readJson(process.argv[2]),signal));
    console.log(JSON.stringify(result));
    if(result.observation.status!=='DECODED'||!result.execution?.loaded?.length) {
      console.error('WINDOWS_LLVM_LOAD_EVIDENCE_NOT_DECODED');process.exitCode=2;
    }
  } catch(error){console.error(error.stack);process.exitCode=error.rc||1;}
}

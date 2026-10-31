#!/usr/bin/env zx
import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs/promises';
import path from 'node:path';
import {createHash} from 'node:crypto';
import {spawnSync,spawn} from 'node:child_process';
import {setTimeout as delay} from 'node:timers/promises';
const root=process.env.WINDOWS_HOST_ENTRY_EVIDENCE;
if(!root)throw Error('WINDOWS_HOST_ENTRY_EVIDENCE required');
const sha=bytes=>createHash('sha256').update(bytes).digest('hex');
let sequence=0;
// These executable recorders are not Windows tools or compiler binaries. The
// original product collector spawns them, records its actual PID/rc/timestamps,
// invokes the real Python XML parser, and passes that result to its selector.
const recorder=String.raw`#!/usr/bin/python3
import os,sys,json,time,datetime,pathlib,html
name=pathlib.Path(sys.argv[0]).name
root=pathlib.Path(os.environ['SYNTHETIC_HOST_CASE'])
case=os.environ['SYNTHETIC_HOST_ARM']
def stamp():return datetime.datetime.now(datetime.timezone.utc).isoformat(timespec='microseconds').replace('+00:00','Z')
with (root/'tool-events.jsonl').open('a') as f:f.write(json.dumps(dict(name=name,argv=sys.argv,pid=os.getpid(),ppid=os.getppid()))+'\n')
if name=='cjc.exe':
 if '--version' in sys.argv:print('Cangjie Compiler: '+('wrong' if case=='version' else '1.3.0-alpha.20260925001050')+' (cjnative)')
 else:
  if case=='compiler':sys.exit(29)
  pathlib.Path(sys.argv[sys.argv.index('-o')+1]).write_text('synthetic compiler output, not a library')
elif name=='powershell.exe':print(json.dumps(dict(systemRoot='C:/windows',drives=[dict(drive='C:',device='\Device\HarddiskVolume3')])))
elif name=='logman.exe':
 if 'start' in sys.argv:
  if case=='start':sys.exit(23)
  pathlib.Path(sys.argv[sys.argv.index('-o')+1]).write_text('synthetic ETL transport marker')
 if 'stop' in sys.argv and case.startswith('cancel-'):
  (root/'stop-started.json').write_text(json.dumps(dict(pid=os.getpid(),at=stamp())))
  time.sleep(.2)
  (root/'stop-completed.json').write_text(json.dumps(dict(pid=os.getpid(),at=stamp())))
elif name=='llc.exe':
 if case.startswith('cancel-'):
  (root/'llc-running.json').write_text(json.dumps(dict(pid=os.getpid(),parent=os.getppid(),at=stamp())))
  time.sleep(60)
 time.sleep(.01);first=stamp();time.sleep(.01);last=stamp()
 (root/'llc-process.json').write_text(json.dumps(dict(pid=os.getpid(),parent=os.getppid(),start=first,end=last)))
 print('synthetic llc command output')
 if case=='llc':sys.exit(17)
elif name=='tracerpt.exe':
 if case=='convert':sys.exit(19)
 p=json.loads((root/'llc-process.json').read_text());pid=p['pid'];lib='C:'+str(root/'inputs/host/third_party/llvm/bin/libLLVM-15.dll');exe='C:'+str(root/'inputs/host/third_party/llvm/bin/llc.exe')
 def row(provider,opcode,when,data):return (provider,opcode,when,data)
 h='68fdd900-4a3e-11d1-84f4-0000f80464e3';pr='3d6fa8d0-fe05-11d0-9dda-00c04fd7ba7c';im='2cb15d1d-5fc1-11d2-abe1-00a0c911f518'
 rows=[row(h,0,p['start'],dict(EventsLost=1 if case=='loss' else 0,BuffersLost=0,EndTime=1)),
 row(pr,1,p['start'],dict(ProcessId=pid,ParentId=p['parent'],UniqueProcessKey=123,ImageFileName='llc.exe')),
 row(im,10,p['start'],dict(ProcessId=pid,FileName=exe)),
 row(im,3 if case=='rundown' else 10,p['start'],dict(ProcessId=pid+1 if case=='pid' else pid,FileName='C:/other/libLLVM-15.dll' if case=='dll' else lib)),
 row(pr,2,p['end'],dict(ProcessId=pid,UniqueProcessKey=124 if case=='reuse' else 123,ExitStatus=0))]
 if case=='unknown':rows[0]=row('00000000-0000-0000-0000-000000000000',0,p['start'],rows[0][3])
 if case=='missing':del rows[0][3]['BuffersLost']
 if case=='noexe':del rows[2]
 if case=='device':rows[3][3]['FileName']=r'\Device\UnknownVolume\libLLVM-15.dll'
 text='<Events xmlns="http://schemas.microsoft.com/win/2004/08/events/event">'
 for provider,op,when,data in rows:
  text+='<Event><System><Provider Guid="{'+provider+'}"/><Opcode>'+str(op)+'</Opcode><TimeCreated SystemTime="'+when+'"/><Execution ProcessID="999"/></System><EventData>'
  for k,v in data.items():text+='<Data Name="'+k+'">'+html.escape(str(v))+'</Data>'
  text+='</EventData></Event>'
 text+='</Events>'
 pathlib.Path(sys.argv[sys.argv.index('-o')+1]).write_text('<malformed' if case=='xml' else text)
 pathlib.Path(sys.argv[sys.argv.index('-summary')+1]).write_text('synthetic summary; decoder must use event payload')
`;
async function fixture(arm){
 await fs.mkdir(root,{recursive:true});
 const work=path.join(root,String(++sequence).padStart(3,'0')+'-'+arm);await fs.mkdir(work);
 const host=work+'/inputs/host',system=work+'/windows',version='1.3.0-alpha.20260925001050';
 for(const file of [host+'/bin/cjc.exe',host+'/third_party/llvm/bin/llc.exe',
  system+'/System32/logman.exe',system+'/System32/tracerpt.exe',system+'/System32/WindowsPowerShell/v1.0/powershell.exe']){
  await fs.mkdir(path.dirname(file),{recursive:true});await fs.writeFile(file,recorder,{mode:0o755});
 }
 await fs.writeFile(host+'/third_party/llvm/bin/libLLVM-15.dll','synthetic DLL byte input; never loaded on Windows');
 const archive=work+'/inputs/host.tar.gz',bytes=Buffer.from('synthetic download contract');await fs.writeFile(archive,bytes);
 const locations={platform:'windows_x86_64',host:{install:'host',archive:'host.tar.gz',version}};
 if(arm==='archive')await fs.appendFile(archive,'broken');
 if(arm==='escape')locations.host.install='../outside';
 const env={...process.env,SYNTHETIC_HOST_CASE:work,SYNTHETIC_HOST_ARM:arm,SystemRoot:'C:'+system,
  GITHUB_WORKSPACE:'C:'+work,GITHUB_ENV:'C:'+work+'/github.env',GITHUB_PATH:'C:'+work+'/github.path',
  RUNNER_TEMP:'C:'+work,CANGJIE_WORKSPACE:'C:'+work+'/workspace',CJCJ_SRCBUILD_TARGET:'windows-x64',
  CJCJ_NATIVE_INPUT_ROOT:'C:'+work+'/inputs',CJCJ_NATIVE_RUNTIME_REF:'79b34798d0f4696f9fe5a3708981539466ecd35b',
  CJCJ_NATIVE_LLVM_REF:'db51a4c7ebb6903e9f997d3b35d52f3577810385',CJCJ_NATIVE_HOST_VERSION:version,
  CJCJ_NATIVE_RUNTIME_INSTALL:'C:'+work+'/runtime'};
 for(const key of ['NODE_TEST_CONTEXT','NODE_OPTIONS','CJCJ_NATIVE_CJDB_INSTALL'])delete env[key];
 if(arm==='ast'){
  await fs.mkdir(work+'/workspace',{recursive:true});
  await fs.writeFile(work+'/workspace/.source-selection.json',JSON.stringify({compiler:{url:'file:///fixture-ast',tag:'a'.repeat(40)}}));
  locations.installations={llvm:{install:'host',buildResult:'llvm.json'},ast:{install:'host',buildResult:'ast.json'}};
  await fs.writeFile(work+'/inputs/llvm.json',JSON.stringify({commits:{compiler:'b'.repeat(40),llvm:env.CJCJ_NATIVE_LLVM_REF}}));
  await fs.writeFile(work+'/inputs/ast.json','{}');
 }
 await fs.writeFile(work+'/inputs/locations.json',JSON.stringify(locations));
 const cfg={env,nativePath:process.env.PATH,python:'/usr/bin/python3',download:{version,archive:'host.tar.gz',
  size:bytes.length,sha256:sha(bytes),releaseRepository:'controlled-fixture',url:'fixture://not-an-official-download'}};
 const config=work+'/config.json';await fs.writeFile(config,JSON.stringify(cfg));
 const run=async mode=>{
  const argv=['--experimental-test-module-mocks',new URL('../fixtures/windows-host-entry-child.mjs',import.meta.url).pathname,mode,config];
  const out=await fs.open(work+'/'+mode+'.stdout','wx'),err=await fs.open(work+'/'+mode+'.stderr','wx');
  let result;
  if(arm.startsWith('cancel-')) {
   const processChild=spawn(process.execPath,argv,{env,stdio:['ignore',out.fd,err.fd]});
   const closed=new Promise(resolve=>{processChild.once('error',error=>resolve({status:null,signal:null,error}));processChild.once('close',(status,signal)=>resolve({status,signal,ended:new Date().toISOString()}));});
   let llc,timer;
   const control={parentPid:processChild.pid,requestedSignal:arm==='cancel-int'?'SIGINT':'SIGTERM'};
   try {
    const deadline=Date.now()+10000;
    while(Date.now()<deadline){llc=await fs.readFile(work+'/llc-running.json','utf8').then(JSON.parse,e=>{if(e.code==='ENOENT')return null;throw e;});if(llc)break;await delay(20);}
    assert.ok(llc,'public prepare must reach an in-flight llc');process.kill(llc.pid,0);
    const capture=JSON.parse(await fs.readFile(work+'/.srcbuild/host-execution/windows-llvm-trace/capture.json'));
    assert.equal(capture.commands.find(row=>row.record==='start.json')?.rc,0,'cancel only after owned start');
    Object.assign(control,{llc,ownedStart:true,sentAt:new Date().toISOString(),sent:processChild.kill(control.requestedSignal)});
    result=await Promise.race([closed,new Promise((_,reject)=>{timer=setTimeout(()=>reject(Error('PUBLIC_CANCEL_TIMEOUT')),10000);})]);
   } finally {
    clearTimeout(timer);
    if(processChild.exitCode===null&&processChild.signalCode===null){control.parentCleanup=processChild.kill('SIGKILL');await closed;}
    if(llc){
     const cmd=await fs.readFile('/proc/'+llc.pid+'/cmdline','utf8').catch(e=>{if(e.code==='ENOENT')return null;throw e;});
     if(cmd===null)control.llcCleanup=false;
     else {assert.ok(cmd.includes(work+'/inputs/host/third_party/llvm/bin/llc.exe'),'cleanup only the owned recorder');process.kill(llc.pid,'SIGKILL');control.llcCleanup=true;}
    }
    await fs.writeFile(work+'/cancel-control.json',JSON.stringify({...control,result},null,2));
   }
  } else result=spawnSync(process.execPath,argv,{env,stdio:['ignore',out.fd,err.fd],timeout:90000});
  await out.close();await err.close();
  await fs.writeFile(work+'/'+mode+'.command.json',JSON.stringify({argv:[process.execPath,...argv],rc:result.status,signal:result.signal,error:result.error?.message}));
  return{rc:result.status,signal:result.signal,ended:result.ended,stdout:await fs.readFile(work+'/'+mode+'.stdout','utf8'),stderr:await fs.readFile(work+'/'+mode+'.stderr','utf8')};
 };
 return{work,run};
}
test('public host preparation consumes collector decoded events and exports the same host to configure',async()=>{
 const f=await fixture('normal'),r=await f.run('prepare');assert.equal(r.rc,0,r.stderr);
 assert.match(r.stdout,/NATIVE_HOST_SELECTED/);
 assert.match(await fs.readFile(f.work+'/.srcbuild/host-execution/windows-llvm-trace/parse-events.stdout','utf8'),/TRACE_XML_EVENTS 5/);
 const trace=JSON.parse(await fs.readFile(f.work+'/.srcbuild/host-execution/windows-llvm-trace/capture.json'));
 assert.equal(trace.observation.status,'DECODED');assert.equal(trace.observation.pid,trace.execution.pid);
 assert.equal(trace.commands.find(x=>x.argv[0]==='/usr/bin/python3'||x.argv[0]==='python').rc,0);
 assert.equal(trace.commands.filter(x=>x.record==='host-llvm.json').length,1);
 assert.deepEqual(trace.execution.loaded,['C:'+f.work+'/inputs/host/third_party/llvm/bin/libLLVM-15.dll']);
 assert.match(await fs.readFile(f.work+'/github.env','utf8'),new RegExp('CJCJ_BOOTSTRAP_BASE=C:'+f.work+'/inputs/host'));
 const configured=await f.run('configure');assert.equal(configured.rc,1);assert.match(configured.stderr,/GHA_HLE_ARTIFACT_PATH/);
 console.log('WINDOWS_HOST_CONFIG_BOUNDARY_REACHED missing-real-HLE; synthetic chain only');
});
for(const [arm,expected]of [['dll','TRACE_LLVM_LOAD_MISMATCH'],['pid','TRACE_LLVM_LOAD_MISMATCH'],
 ['loss','TRACE_EVENTS_LOST'],['reuse','TRACE_PROCESS_LIFETIME'],['rundown','TRACE_LLVM_LOAD_MISMATCH'],
 ['xml','WINDOWS_TRACE_COMMAND_FAILED python'],['unknown','TRACE_LOG_HEADER_REQUIRED'],
 ['missing','TRACE_INTEGER'],['noexe','TRACE_EXECUTABLE_LOAD_MISSING'],['device','TRACE_DEVICE_PATH_UNRESOLVED'],['start','WINDOWS_TRACE_COMMAND_FAILED'],['convert','WINDOWS_TRACE_COMMAND_FAILED'],
 ['llc','WINDOWS_TRACE_COMMAND_FAILED'],['compiler','Command failed'],['archive','original archive differs'],
 ['version','compiler mismatch'],['escape','NATIVE_HOST_MEMBER_PATH'],['ast','NATIVE_LLVM_AST_SOURCE_PAIR']])
 test('public host preparation rejects '+arm,async()=>{
  const f=await fixture(arm),r=await f.run('prepare');console.log('WINDOWS_HOST_REJECTION_ASSERTION_REACHED '+arm);
  assert.notEqual(r.rc,0);assert.match(r.stderr,new RegExp(expected));
  assert.equal(await fs.stat(f.work+'/github.env').then(()=>true,()=>false),false);
  if(arm==='xml'){
   const base=f.work+'/.srcbuild/host-execution/windows-llvm-trace/parse-events';
   assert.match(await fs.readFile(base+'.stderr','utf8'),/ParseError/);
   assert.equal(JSON.parse(await fs.readFile(base+'.json')).rc,1);
  }
  if(arm==='start'){
   const events=(await fs.readFile(f.work+'/tool-events.jsonl','utf8')).trim().split('\n').map(JSON.parse);
   assert.equal(events.some(e=>e.name==='logman.exe'&&e.argv.includes('stop')),false);
  }
 });

for(const [arm,rc]of [['cancel-int',130],['cancel-term',143]])test('public host preparation cancels '+arm+' after owned start and awaits one stop',async()=>{
 const f=await fixture(arm),r=await f.run('prepare');
 const events=(await fs.readFile(f.work+'/tool-events.jsonl','utf8')).trim().split('\n').map(JSON.parse);
 const stops=events.filter(e=>e.name==='logman.exe'&&e.argv.includes('stop'));
 console.log('OWNED_STOP_CANCELLATION_ASSERTION_REACHED '+arm);
 assert.equal(stops.length,1,'owned ETW stop must execute exactly once after cancellation');
 const finished=JSON.parse(await fs.readFile(f.work+'/stop-completed.json'));
 assert.ok(Date.parse(finished.at)<=Date.parse(r.ended),'public parent must await stop completion');
 const trace=f.work+'/.srcbuild/host-execution/windows-llvm-trace/';
 const llc=JSON.parse(await fs.readFile(trace+'host-llvm.json')),stop=JSON.parse(await fs.readFile(trace+'stop.json'));
 assert.equal(llc.cancelled,true);assert.equal(llc.rc,null);assert.equal(llc.signal,'SIGKILL');
 assert.equal(stop.rc,0);assert.equal(stop.cancelled,undefined);assert.equal(stop.signal,null);
 assert.equal(r.rc,rc,r.stderr);assert.equal(r.signal,null);assert.match(r.stderr,/SDK_CANCELLED/);
 assert.equal(JSON.parse(await fs.readFile(f.work+'/cancel-control.json')).llcCleanup,false,'collector must reap its own child');
 assert.equal(await fs.stat(f.work+'/github.env').then(()=>true,()=>false),false);
});

#!/usr/bin/env zx
// Public SDK boundary tests: no D-state, filesystem mount, or host proc mutation.
import fs from 'node:fs';import path from 'node:path';import assert from 'node:assert/strict';
import {spawn,spawnSync}from'node:child_process';import {setTimeout as delay}from'node:timers/promises';
const [source,runtime,root,version='candidate']=process.argv.slice(2);assert(source&&runtime&&root);fs.mkdirSync(root,{recursive:true});
const read=f=>fs.readFileSync(f,'utf8'),write=(f,v)=>{fs.mkdirSync(path.dirname(f),{recursive:true});fs.writeFileSync(f,typeof v==='string'?v:JSON.stringify(v,null,2)+'\n');};
const events=f=>fs.existsSync(f)?read(f).trim().split('\n').filter(Boolean).map(JSON.parse):[];
function identity(pid){try{const s=read('/proc/'+pid+'/stat'),v=s.slice(s.lastIndexOf(')')+2).split(' ');return{pid,start:v[19],state:v[0],ppid:+v[1],cwd:fs.readlinkSync('/proc/'+pid+'/cwd'),exe:fs.readlinkSync('/proc/'+pid+'/exe')};}catch{return null;}}
const alive=id=>{const x=id&&identity(id.pid);return x&&x.start===id.start&&x.state!=='Z';};
async function until(fn,label,ms=12000){const end=Date.now()+ms;while(Date.now()<end){const v=fn();if(v)return v;await delay(10);}throw Error('FIXTURE_TIMEOUT '+label);}
const arms=process.env.SDK_FINAL_ARMS?.split(',')||['normal','exec-term','exec-eof','stat-eio','stat-eacces'];const rows=[];
for(const arm of arms){
 const dir=root+'/'+arm;fs.mkdirSync(dir);const pool=dir+'/parent.fifo',release=dir+'/release',boundary=dir+'/boundary.json',marker=dir+'/payload.json',log=dir+'/events.jsonl';
 assert.equal(spawnSync('mkfifo',[pool]).status,0);const fd=fs.openSync(pool,fs.constants.O_RDWR|fs.constants.O_NONBLOCK);fs.writeSync(fd,'AB');
 const known=new Map(),capture=pid=>{const x=identity(pid);if(x)known.set(pid,x);return x;};
 const drain=()=>{const b=Buffer.alloc(16);try{return b.subarray(0,fs.readSync(fd,b,0,16,null)).toString();}catch(e){if(e.code==='EAGAIN')return '';throw e;}};
 const leaf=dir+'/payload.mjs';write(leaf,`import fs from'node:fs';fs.writeFileSync(${JSON.stringify(marker)},JSON.stringify({pid:process.pid,cwd:process.cwd()}));console.log('EXEC_PAYLOAD_CONSUMED');`);
 const cfg=dir+'/config.json';write(cfg,{work:dir+'/work',install:dir+'/install',repos:{},test:{},finalStage:'one',stages:[{id:'one',output:dir+'/install',commands:[{argv:[process.execPath,leaf]}]}]});
 let injected='';
 if(arm.startsWith('exec-'))injected=`\nimport subprocess\n_fixture_g=os.getpid()\n_fixture_signal=signal.pidfd_send_signal\ndef _fixture_send(fd,sig,*args):\n    if sig and not Path(${JSON.stringify(release)}).exists():return None\n    return _fixture_signal(fd,sig,*args)\nsignal.pidfd_send_signal=_fixture_send\ndef _fixture_hold():\n    signal.signal(signal.SIGINT,signal.SIG_IGN);signal.signal(signal.SIGTERM,signal.SIG_IGN)\n    fds={}\n    for name in os.listdir('/proc/self/fd'):\n        try:fds[name]=os.readlink('/proc/self/fd/'+name)\n        except FileNotFoundError:pass\n    Path(${JSON.stringify(boundary)}).write_text(json.dumps({'pid':os.getpid(),'parent':os.getppid(),'guardian':_fixture_g,'session':os.getsid(0),'fds':fds,'beforeExec':True}))\n    while not Path(${JSON.stringify(release)}).exists():time.sleep(0.01)\n_fixture_exec=os.execvpe\ndef _fixture_execvpe(*a,**k):\n    _fixture_hold()\n    return _fixture_exec(*a,**k)\nos.execvpe=_fixture_execvpe\n_fixture_popen=subprocess.Popen\ndef _fixture_popen_call(*a,**k):\n    original=k.get('preexec_fn')\n    def preexec():\n        if original:original()\n        _fixture_hold()\n    k['preexec_fn']=preexec\n    return _fixture_popen(*a,**k)\nsubprocess.Popen=_fixture_popen_call\n`;
 if(arm.startsWith('stat-'))injected=`\n_fixture_exists=Path.exists\ndef _fixture_stat(self):\n    if self.name=='failure' and globals().get('quiescent') and not _fixture_exists(Path(${JSON.stringify(release)})):\n        if not _fixture_exists(Path(${JSON.stringify(boundary)})):\n            Path(${JSON.stringify(boundary)}).write_text(json.dumps({'pid':os.getpid(),'phase':globals().get('phase'),'quiescent':quiescent,'poolFd':pool_fd,'borrowedHex':bytes(borrowed).hex(),'returned':returned,'errno':${arm==='stat-eio'?5:13}}))\n        raise OSError(${arm==='stat-eio'?5:13},'PRIVATE_FINAL_STAT_FAULT')\n    return _fixture_exists(self)\nPath.exists=_fixture_stat\n`;
 const hook=dir+'/hook.mjs';write(hook,`import cp from'node:child_process';import fs from'node:fs';import{syncBuiltinESMExports}from'node:module';const original=cp.spawn;cp.spawn=function(exe,args,opts){let instrument=false;if(exe==='python3'&&args?.[1]==='-c'){args=[...args];args[2]=args[2].replace('config=json.loads(sys.argv[1])','config=json.loads(sys.argv[1])'+${JSON.stringify(injected)});fs.writeFileSync(${JSON.stringify(dir+'/injected-program.py')},args[2]);instrument=true;}const child=original.call(this,exe,args,opts);if(instrument&&${JSON.stringify(arm)}==='exec-eof'){const t=setInterval(()=>{if(fs.existsSync(${JSON.stringify(boundary)})){clearInterval(t);fs.writeFileSync(${JSON.stringify(dir+'/eof.json')},JSON.stringify({owner:process.pid,guardian:child.pid}));child.stdio[3].end();}},5);t.unref();}return child;};syncBuiltinESMExports();`);
 const env={...process.env,MAKEFLAGS:'--jobserver-auth=3,4 -j3',CANGJIE_JOBSERVER_LOG:log};for(const k of ['CARGO_MAKEFLAGS','MFLAGS','CJCJ_SUPERVISOR_WORK'])delete env[k];
 const argv=[process.execPath,...(injected?['--import',hook]:[]),source+'/ci/bootstrap/sdk-build.mjs','--config',cfg,'--no-package'];
 const out=fs.openSync(dir+'/stdout','w'),err=fs.openSync(dir+'/stderr','w');const control=spawn(process.execPath,['-e','setInterval(()=>{},1000)'],{stdio:'ignore'}),unrelated=await until(()=>identity(control.pid),'unrelated');
 const p=spawn(argv[0],argv.slice(1),{cwd:dir,env,stdio:['ignore',out,err,fd,fd]});capture(p.pid);let result,returned='';p.once('exit',(rc,signal)=>{result={rc,signal};});
 try{
  if(arm==='normal')await until(()=>result,'normal completion');
  else{
   const b=await until(()=>fs.existsSync(boundary)&&JSON.parse(read(boundary)),'exact fault boundary');capture(b.pid);
   if(arm.startsWith('exec-')){assert.equal(b.pid===b.guardian,false,'actual fork child');assert.equal(b.parent,b.guardian);assert.equal(b.session,b.pid,'new payload session');assert(!fs.existsSync(marker),'before exec payload');if(arm==='exec-term')p.kill('SIGTERM');else await until(()=>fs.existsSync(dir+'/eof.json'),'actual control EOF');await delay(5600);}
   else{assert(b.quiescent);assert.equal(b.poolFd,null,'private pool closed before final stat');assert.equal(b.borrowedHex,'4142');assert.equal(b.returned,0);await delay(250);}
  }
  const es=events(log),ready=es.find(x=>x.event==='supervisor-ready'),g=ready&&capture(ready.pid);if(fs.existsSync(marker))capture(JSON.parse(read(marker)).pid);
  const status=ready&&fs.existsSync(ready.directory+'/status.json')?JSON.parse(read(ready.directory+'/status.json')):null;
  returned+=drain();const observed={arm,version,argv,result:result||null,status,boundary:fs.existsSync(boundary)?JSON.parse(read(boundary)):null,guardian:g,guardianAlive:!!alive(g),tokensBeforeRelease:returned,payloadReached:fs.existsSync(marker),events:es,identities:[...known.values()],liveBeforeRelease:[...known.values()].filter(alive),unrelatedAlive:!!alive(unrelated)};write(dir+'/observed-before-release.json',observed);
  console.log(JSON.stringify({event:'FINAL_LIFECYCLE_TARGET_ASSERTION_REACHED',arm,result:observed.result,status:status?.type,guardianAlive:observed.guardianAlive,tokens:returned,payloadReached:observed.payloadReached}));
  let assertion;
  try{
   assert(observed.unrelatedAlive);
   if(arm==='normal'){assert.equal(result.rc,0);assert(observed.payloadReached);assert.equal(returned,'AB');}
   else{assert.equal(status?.type,'incomplete','bounded INCOMPLETE at actual exec/final-stat boundary');assert(observed.guardianAlive,'live G retains responsibility');assert.equal(status.unreturnedHex,'4142');assert.equal(returned,'');assert(result,'public result bounded');assert.equal(result.rc,arm==='exec-term'?143:1);assert.equal(status.reaped,arm.startsWith('stat-'));
    if(arm.startsWith('exec-')){assert(!observed.payloadReached);assert.equal(status.execState,'pending');assert(!Object.values(observed.boundary.fds).includes(pool),'original upstream descriptors absent from pre-exec child');}
   }
  }catch(e){assertion=e;}
  write(release,'release\n');if(g&&alive(g))await until(()=>!alive(g),'true G recovery');if(!result)await until(()=>result,'public recovery');returned+=drain();
  const recovery={result,tokensTotal:returned,events:events(log),liveBeforeTestCleanup:[...known.values()].filter(alive)};write(dir+'/recovery-before-cleanup.json',recovery);rows.push({arm,version,pass:!assertion,error:assertion?.message,observed,recovery});write(root+'/results.json',rows);
  if(assertion)throw assertion;
  assert.equal(returned,'AB');assert.equal(recovery.liveBeforeTestCleanup.length,0);console.log(JSON.stringify({arm,pass:true,tokens:returned}));
 }finally{write(release,'release\n');for(const id of [...known.values()].filter(alive))if(alive(id))process.kill(id.pid,'SIGKILL');if(alive(unrelated))process.kill(unrelated.pid,'SIGKILL');fs.closeSync(fd);fs.closeSync(out);fs.closeSync(err);await delay(100);write(dir+'/cleanup.json',{remaining:[...known.values()].filter(alive)});}
}

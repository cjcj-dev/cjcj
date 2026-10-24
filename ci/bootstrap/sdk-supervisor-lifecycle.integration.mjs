#!/usr/bin/env zx
// Private process-local syscall faults, through the public SDK entry. Never changes host /proc.
import fs from 'node:fs';
import path from 'node:path';
import assert from 'node:assert/strict';
import {spawn,spawnSync} from 'node:child_process';
import {setTimeout as delay} from 'node:timers/promises';
const [source,runtime,root,version='candidate']=process.argv.slice(2);
assert(source&&runtime&&root);fs.mkdirSync(root,{recursive:true});
const read=f=>fs.readFileSync(f,'utf8'),write=(f,v)=>{fs.mkdirSync(path.dirname(f),{recursive:true});fs.writeFileSync(f,typeof v==='string'?v:JSON.stringify(v,null,2)+'\n');};
const events=f=>fs.existsSync(f)?read(f).trim().split('\n').filter(Boolean).map(JSON.parse):[];
function identity(pid){try{const raw=read('/proc/'+pid+'/stat'),v=raw.slice(raw.lastIndexOf(')')+2).split(' ');return {pid,start:v[19],state:v[0],ppid:+v[1],cwd:fs.readlinkSync('/proc/'+pid+'/cwd'),exe:fs.readlinkSync('/proc/'+pid+'/exe')};}catch{return null;}}
const alive=id=>{const x=id&&identity(id.pid);return x&&x.start===id.start&&x.state!=='Z';};
async function until(fn,label,ms=10000){const end=Date.now()+ms;while(Date.now()<end){const x=fn();if(x)return x;await delay(20);}throw Error('FIXTURE_TIMEOUT '+label);}
const arms=process.env.SDK_LIFECYCLE_ARMS?.split(',')||['normal','readonly','readonly-adapter','primary-stuck','primary-error-stuck','proc-preflight-fifo','proc-preflight-numeric','proc-runtime'];
const rows=[];
for(const arm of arms){
 const dir=path.join(root,arm);fs.mkdirSync(dir);const pool=dir+'/parent.fifo',release=dir+'/release',marker=dir+'/payload.json',log=dir+'/events.jsonl',fault=dir+'/fault.jsonl';
 assert.equal(spawnSync('mkfifo',[pool]).status,0);const fd=fs.openSync(pool,fs.constants.O_RDWR|fs.constants.O_NONBLOCK);fs.writeSync(fd,'AB');
 const known=new Map();let result,observed,publicChild,control;const capture=pid=>{const id=identity(pid);if(id)known.set(pid,id);return id;};
 const drain=()=>{const b=Buffer.alloc(64);try{return b.subarray(0,fs.readSync(fd,b,0,64,null)).toString();}catch(e){if(e.code==='EAGAIN')return '';throw e;}};
 let returned='';const payload=dir+'/payload.mjs';
 write(payload,`import fs from 'node:fs';import{spawn}from'node:child_process';const arm=${JSON.stringify(arm)};let child;if(arm.startsWith('proc-'))child=spawn(process.execPath,['-e',"process.on('SIGTERM',()=>{});setInterval(()=>{},1000)"],{detached:true,stdio:'ignore'});fs.writeFileSync(${JSON.stringify(marker)},JSON.stringify({pid:process.pid,child:child?.pid,cwd:process.cwd()}));if(arm.startsWith('primary-'))setInterval(()=>{},1000);else {child?.unref();process.exit(0);}`);
 let command=[process.execPath,payload];if(arm==='readonly-adapter')command=[process.execPath,runtime+'/stdlib/scripts/ninja-jobserver.mjs','run','--jobs','3','--',process.execPath,payload];
 const config=dir+'/config.json';write(config,{work:dir+'/work',install:dir+'/install',repos:{},finalStage:'one',test:{},stages:[{id:'one',output:dir+'/install',commands:[{argv:command,cwd:arm.startsWith('readonly')?'/proc':dir}]}]});
 let injected='';
 if(arm.startsWith('primary-'))injected=`\n_fixture_signal=signal.pidfd_send_signal\ndef _fixture_send(fd,sig,*args):\n    if sig and not Path(${JSON.stringify(release)}).exists():\n        with open(${JSON.stringify(fault)},'a') as f:f.write(json.dumps({'signal':int(sig),'pid':os.getpid()})+'\\n')\n        return None\n    return _fixture_signal(fd,sig,*args)\nsignal.pidfd_send_signal=_fixture_send\n`;
 if(arm.startsWith('proc-'))injected=`\n_fixture_read=Path.read_text\ndef _fixture_read_text(self,*args,**kwargs):\n    if str(self).startswith('/proc/self/task/') and str(self).endswith('/children') and not Path(${JSON.stringify(release)}).exists()${arm==='proc-runtime'?` and Path(${JSON.stringify(marker)}).exists()`:''}:\n        with open(${JSON.stringify(fault)},'a') as f:f.write(json.dumps({'read':str(self),'pid':os.getpid()})+'\\n')\n        raise OSError(5,'PRIVATE_PROC_READ_FAULT')\n    return _fixture_read(self,*args,**kwargs)\nPath.read_text=_fixture_read_text\n`;
 const hook=dir+'/hook.mjs';
 write(hook,`import cp from 'node:child_process';import fs from'node:fs';import{syncBuiltinESMExports}from'node:module';const original=cp.spawn;cp.spawn=function(exe,args,opts){if(exe==='python3'&&args?.[1]==='-c'){args=[...args];args[2]=args[2].replace('config=json.loads(sys.argv[1])','config=json.loads(sys.argv[1])'+${JSON.stringify(injected)});${arm==='primary-error-stuck'?`args[2]=args[2].replace("        trace('supervisor-child',child=primary.pid,directory=directory,mode=config['mode'])", "        trace('supervisor-child',child=primary.pid,directory=directory,mode=config['mode'])\\n        raise RuntimeError('PRIVATE_POST_SPAWN_FAULT')");`:''}fs.writeFileSync(${JSON.stringify(dir+'/injected-program.py')},args[2]);}return original.call(this,exe,args,opts);};syncBuiltinESMExports();`);
 const env={...process.env,MAKEFLAGS:'-j3 --jobserver-auth='+(arm==='proc-preflight-fifo'?'fifo:'+pool:'3,4'),CANGJIE_JOBSERVER_LOG:log};delete env.CARGO_MAKEFLAGS;delete env.MFLAGS;delete env.CJCJ_SUPERVISOR_WORK;
 const argv=[process.execPath,...(injected?['--import',hook]:[]),source+'/ci/bootstrap/sdk-build.mjs','--config',config,'--no-package'];
 const out=fs.openSync(dir+'/stdout','w'),err=fs.openSync(dir+'/stderr','w');
 control=spawn(process.execPath,['-e','setInterval(()=>{},1000)'],{stdio:'ignore'});const unrelated=await until(()=>identity(control.pid),'control');
 publicChild=spawn(argv[0],argv.slice(1),{cwd:dir,env,stdio:['ignore',out,err,fd,fd]});capture(publicChild.pid);publicChild.once('exit',(rc,signal)=>{result={rc,signal};});
 let assertion;
 try{
  if(arm.startsWith('primary-')){
   await until(()=>fs.existsSync(marker),'primary ready');const p=JSON.parse(read(marker));capture(p.pid);
   if(arm==='primary-stuck')publicChild.kill('SIGTERM');
   await until(()=>events(fault).length,'fault consumed');await delay(5600);
  }else if(arm==='proc-runtime'){
   await until(()=>fs.existsSync(marker),'payload ready');const p=JSON.parse(read(marker));capture(p.pid);capture(p.child);
   await until(()=>events(fault).length,'runtime fault consumed');await delay(250);
  }else await until(()=>result,'public completion');
  const es=events(log),ready=es.find(x=>x.event==='supervisor-ready'),g=ready&&capture(ready.pid);
  if(fs.existsSync(marker)){const p=JSON.parse(read(marker));capture(p.pid);if(p.child)capture(p.child);}
  const status=ready&&fs.existsSync(ready.directory+'/status.json')?JSON.parse(read(ready.directory+'/status.json')):null;
  returned+=drain();
  observed={arm,version,argv,result:result||null,events:es,status,guardian:g,guardianAlive:!!alive(g),live:[...known.values()].filter(alive),tokensBeforeRelease:returned,payload:fs.existsSync(marker)?JSON.parse(read(marker)):null,faultReached:events(fault).length,unrelatedAlive:!!alive(unrelated)};
  write(dir+'/observed-before-release.json',observed);
  console.log(JSON.stringify({event:'LIFECYCLE_TARGET_ASSERTION_REACHED',arm,result:observed.result,status:status?.type,tokens:returned,guardianAlive:observed.guardianAlive}));
  assert(observed.unrelatedAlive,'unrelated alive');
  try{
   if(arm.startsWith('primary-')||arm==='proc-runtime'){
    assert.equal(status?.type,'incomplete','bounded INCOMPLETE before fault release');assert(observed.guardianAlive,'live G retains ledger');assert.equal(status.unreturnedHex,'4142');assert.equal(status.reaped,false);assert.equal(returned,'','no early return');assert(result,'public result is bounded');assert.notEqual(result.rc,0);if(arm==='primary-stuck')assert.equal(result.rc,143);
   }else if(arm.startsWith('proc-preflight')){
    assert.notEqual(result.rc,0);assert.equal(observed.payload,null,'preflight before payload');assert(!es.some(x=>x.event==='scope-budget'),'preflight before borrow');assert.equal(returned,'AB');assert.match(read(dir+'/stdout')+read(dir+'/stderr'),/SUPERVISOR_PROC/);
   }else{
    assert.equal(result.rc,0,'normal readonly command succeeds');assert.equal(observed.payload.cwd,arm.startsWith('readonly')?'/proc':dir,'payload cwd preserved');assert.equal(returned,'AB');assert(es.filter(x=>x.event==='supervisor-ready').every(x=>x.directory.startsWith(dir+'/work/')),'private work diagnostic domain');
   }
  }catch(e){assertion=e;}
  // Remove only the private syscall fault. Recovery must be performed by live G.
  write(release,'release\n');
  if(g&&alive(g))await until(()=>!alive(g),'guardian true recovery');
  if(!result)await until(()=>result,'public after release');returned+=drain();
  const finalEvents=events(log),recovery={result,tokensTotal:returned,liveBeforeTestCleanup:[...known.values()].filter(alive),events:finalEvents};write(dir+'/recovery-before-cleanup.json',recovery);
  if(!assertion){assert.equal(returned,'AB');assert.equal(recovery.liveBeforeTestCleanup.length,0);if(arm.startsWith('primary-')||arm==='proc-runtime')assert(finalEvents.some(x=>x.event==='parent-return'&&x.originalHex==='4142'));}
  rows.push({arm,version,pass:!assertion,error:assertion?.message,observed,recovery});write(root+'/results.json',rows);
  if(assertion)throw assertion;
  console.log(JSON.stringify({arm,pass:true,tokens:returned}));
 }finally{
  write(release,'release\n');for(const id of [...known.values()].filter(alive))if(alive(id))process.kill(id.pid,'SIGKILL');if(alive(unrelated))process.kill(unrelated.pid,'SIGKILL');fs.closeSync(fd);fs.closeSync(out);fs.closeSync(err);await delay(100);write(dir+'/cleanup.json',{remaining:[...known.values()].filter(alive)});
 }
}

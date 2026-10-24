// Real installed-input integration fixture; requires an owned SDK and actual resource settings.
// Builds no std: copied existing payload is explicitly recorded as a fixture.
import test from 'node:test';
import {sdkEnvironment} from './sdk-platform.mjs';
import fs from 'node:fs/promises';
import fss from 'node:fs';
import path from 'node:path';
import assert from 'node:assert/strict';
import {spawn, spawnSync} from 'node:child_process';
import {createBootstrapTargets} from './sdk-targets.mjs';
test('Windows loader PATH retains SDK tools libraries and system paths for both native consumers',()=>{
 const env=sdkEnvironment('C:/sdk','windows_x86_64',{PATH:'C:/Windows/System32;C:/Python'});
 const expected=['C:/sdk/bin','C:/sdk/tools/bin','C:/sdk/third_party/llvm/bin','C:/sdk/runtime/lib/windows_x86_64_cjnative','C:/sdk/lib/windows_x86_64_cjnative','C:/sdk/third_party/llvm/bin','C:/sdk/tools/lib','C:/Windows/System32','C:/Python'];
 console.log('WINDOWS_LOADER_CONFIGURATION_ASSERTION_REACHED '+JSON.stringify(env));
 assert.deepEqual(env.PATH.split(';'),expected);
 assert.equal(env.CANGJIE_HOME,'C:/sdk');
});

const sdk=process.env.SDK_NATIVE_INSTALLED_SDK,base=process.env.SDK_NATIVE_INSTALLED_TEST_ROOT,inputFile=process.env.SDK_NATIVE_INSTALLED_INPUTS;
if(!sdk||!base||!inputFile)throw new Error('SDK_NATIVE_INSTALLED_SDK/TEST_ROOT/INPUTS required');
const source=base+'/fixture-source',work=base+'/work',output=base+'/installed-std',evidence=base+(process.env.SDK_NATIVE_MATRIX_CONTINUE==='1'?'/evidence-continuation':'/evidence');
await fs.mkdir(source+'/stdlib',{recursive:true});await fs.mkdir(evidence,{recursive:true});
const continuing=process.env.SDK_NATIVE_MATRIX_CONTINUE==='1';
const file=base+'/targets.json',predecessor=base+'/predecessor.txt';let config,commit;
if(!continuing){
const input=JSON.parse(await fs.readFile(inputFile,'utf8'));
const generated=createBootstrapTargets({...input,work:base+'/generated-work',install:base+'/generated-install'});
await fs.writeFile(base+'/generated-targets.json',JSON.stringify(generated,null,2));
const producer=`import sys,json,shutil,pathlib,os,subprocess,time\nroot=pathlib.Path(__file__).resolve().parents[1]\npayload=pathlib.Path(${JSON.stringify(sdk)})\nwith (root/'calls.jsonl').open('a') as log: log.write(json.dumps(sys.argv)+'\\n')\nif os.environ.get('SDK_FIXTURE_FAIL')==sys.argv[1]: raise SystemExit(7)\nif os.environ.get('SDK_FIXTURE_WAIT')==sys.argv[1]:\n child=subprocess.Popen(['sleep','120'])\n pathlib.Path(os.environ['SDK_FIXTURE_READY']).write_text(json.dumps([os.getpid(),child.pid]))\n child.wait()\nif sys.argv[1]=='build':\n print('FIXTURE_BUILD_USES_EXISTING_STD_NO_STD_PRODUCTION')\nelif sys.argv[1]=='install':\n out=pathlib.Path(sys.argv[sys.argv.index('--prefix')+1])\n for rel in ['lib','modules']:\n  shutil.copytree(payload/rel,out/rel,dirs_exist_ok=True,symlinks=False)\n rel='runtime/lib/linux_x86_64_cjnative/libcangjie-std-core.so'\n (out/rel).parent.mkdir(parents=True,exist_ok=True)\n shutil.copy2(payload/rel,out/rel)\n print('FIXTURE_INSTALL_EXISTING_PAYLOAD')\nelse: raise SystemExit(97)\n`;
await fs.writeFile(source+'/stdlib/build.py',producer);await fs.writeFile(source+'/.gitignore','calls.jsonl\n');
function cmd(exe,args,opts={}){const p=spawnSync(exe,args,{encoding:'utf8',maxBuffer:16*1024*1024,...opts});assert.equal(p.status,0,p.stderr||p.stdout);return p.stdout.trim();}
cmd('git',['init','-q',source]);cmd('git',['-C',source,'add','.']);cmd('git',['-C',source,'-c','user.name=Zxilly','-c','user.email=zxilly@outlook.com','commit','-qm','test: existing std installation fixture']);
commit=cmd('git',['-C',source,'rev-parse','HEAD']);const tree=cmd('git',['-C',source,'rev-parse','HEAD^{tree}']);
await fs.writeFile(predecessor,'42\n');
const check=base+'/check-predecessor.mjs';await fs.writeFile(check,`import fs from 'node:fs';const value=fs.readFileSync(process.argv[2],'utf8').trim();console.log('PREDECESSOR_ASSERTION_REACHED '+value);if(value!=='42')process.exit(65);`);
const stdStage=structuredClone(generated.stages.find(s=>s.id==='stage3-std'));
stdStage.output=output;
// Keep the generated native command and stage consumer. Only the fixture source,
// identity, predecessor, and output bindings differ from production inputs.
const a=stdStage.commands[0].argv;a[a.indexOf('--commit')+1]=commit;a.push('--heap','8GB');
config={work,install:output,repos:{std1:{root:source,checkout:base+'/checkout',commit,tree}},stages:[{id:'stage2',output:sdk,reuse:'fixed-existing-C2',test:{commands:[{argv:[process.execPath,check,predecessor]}]}},stdStage],finalStage:'stage3-std',platform:'linux_x86_64',test:{required:['PROVENANCE.txt','lib/linux_x86_64_cjnative/libcangjie-std-core.a']}};
await fs.writeFile(file,JSON.stringify(config,null,2));
await fs.writeFile(base+'/scope.json',JSON.stringify({scope:'native-public-entry-fixture-not-std-production',commit,tree,payload:sdk,generatedStdStage:generated.stages.find(s=>s.id==='stage3-std'),fixtureStdStage:stdStage},null,2));

}else{config=JSON.parse(await fs.readFile(file,'utf8'));commit=config.repos.std1.commit;}
const cli=new URL('./sdk-build.mjs',import.meta.url).pathname,rows=[];
async function run(name,args,expected=0,pattern){const p=spawnSync(process.execPath,[cli,'--config',file,'--no-package',...args],{encoding:'utf8',maxBuffer:16*1024*1024,timeout:600000});await fs.writeFile(evidence+'/'+name+'.stdout',p.stdout||'');await fs.writeFile(evidence+'/'+name+'.stderr',p.stderr||'');rows.push({name,argv:[cli,'--config',file,'--no-package',...args],rc:p.status,signal:p.signal,error:p.error?.message});await fs.writeFile(evidence+'/results.json',JSON.stringify(rows,null,2));assert.equal(p.status,expected,name+': '+p.stderr);if(pattern)assert.match(p.stdout+p.stderr,pattern,name);return p;}
const calls=async()=> (await fs.readFile(base+'/checkout/calls.jsonl','utf8')).trim().split('\n').length;
if(!continuing){
await run('first',[]);assert.equal(await calls(),2);assert.match(await fs.readFile(output+'/PROVENANCE.txt','utf8'),/STD_SOURCE_COMMIT/);
const firstConfiguration=JSON.parse(await fs.readFile(work+'/build-result.json','utf8')).configuration;
const records=evidence+'/first.stdout';
const resume=['--resume-installed','stage3-std','--accept-records',records];
await run('resume',resume,0,/resume-accepted/);assert.equal(await calls(),2);
await run('resume-again',resume,0,/resume-accepted/);assert.equal(await calls(),2);assert.equal(JSON.parse(await fs.readFile(work+'/build-result.json','utf8')).configuration,firstConfiguration);
await run('missing-record',['--resume-installed','stage3-std','--accept-records',base+'/missing'],1,/STD_RESUME_RECORD missing/);assert.equal(await calls(),2);
const mutations = {
  'cancelled build with exit zero': rows => { rows.find(r=>r.event==='target-result'&&r.argv?.includes('build.py')&&r.argv.includes('build')).cancelled=true; },
  'cancelled install with exit zero': rows => { rows.find(r=>r.event==='target-result'&&r.argv?.includes('install')).cancelled=true; },
  'build failure': rows => { rows.find(r=>r.event==='target-result'&&r.argv?.includes('build.py')&&r.argv.includes('build')).rc=1; },
  'install failure': rows => { rows.find(r=>r.event==='target-result'&&r.argv?.includes('install')).rc=1; },
  'wrong prefix': rows => { const r=rows.find(r=>r.event==='target-result'&&r.argv?.includes('install')); r.argv[r.argv.indexOf('--prefix')+1]+='-wrong'; },
  'wrong order': rows => { const i=rows.findIndex(r=>r.event==='target-command'&&r.argv?.includes('build.py')); rows.splice(i,4,...rows.slice(i+2,i+4),...rows.slice(i,i+2)); },
  'missing start': rows => { rows.splice(rows.findIndex(r=>r.event==='target-command'&&r.argv?.includes('std')),1); },
  'cross attempt': rows => { const i=rows.findIndex(r=>r.event==='target-command'&&r.argv?.includes('std')); rows.splice(i+3,0,structuredClone(rows[i])); },
  'later failed attempt': rows => { const r=structuredClone(rows.find(r=>r.event==='target-command'&&r.argv?.includes('std'))); rows.push(r,{...r,event:'target-result',rc:1,signal:null,wall:1}); },
  'later orphan build': rows => { rows.push(structuredClone(rows.find(r=>r.event==='target-command'&&r.argv?.includes('build.py')))); },
  'different attempt result': rows => { rows.find(r=>r.event==='target-result'&&r.argv?.includes('std')).wall+=1; },
  'wrong compiler runtime': rows => { for(const r of rows.filter(r=>r.argv?.includes('--compiler-runtime')))r.argv[r.argv.indexOf('--compiler-runtime')+1]='host'; },
  'wrong platform': rows => { for(const r of rows.filter(r=>r.argv?.includes('--platform')))r.argv[r.argv.indexOf('--platform')+1]='linux_aarch64'; },
  'wrong sdk': rows => { for(const r of rows.filter(r=>r.argv?.includes('--sdk')))r.argv[r.argv.indexOf('--sdk')+1]+='-different'; },
  'wrong runtime': rows => { for(const r of rows.filter(r=>r.argv?.includes('--runtime')))r.argv[r.argv.indexOf('--runtime')+1]+='-different'; },
  'wrong commit': rows => { for(const r of rows.filter(r=>r.argv?.includes('--commit')))r.argv[r.argv.indexOf('--commit')+1]='1'.repeat(40); },
};

const firstRows=(await fs.readFile(records,'utf8')).split('\n').filter(l=>l.startsWith('{')).map(l=>JSON.parse(l));
for(const [name,mutate] of Object.entries(mutations)) {
 const copy=structuredClone(firstRows);mutate(copy);
 const log=evidence+'/mutated-'+name.replaceAll(' ','-')+'.records';
 await fs.writeFile(log,copy.map(r=>JSON.stringify(r)).join('\n'));
 const state=await fs.readFile(work+'/build-result.json');
 await run('reject-'+name.replaceAll(' ','-'),['--resume-installed','stage3-std','--accept-records',log],1,/STD_RESUME_RECORD/);
 assert.equal(await calls(),2);assert.deepEqual(await fs.readFile(work+'/build-result.json'),state);
}
for(const field of ['root','checkout','commit']) {
 const before=await fs.readFile(file),changed=structuredClone(config),state=await fs.readFile(work+'/build-result.json');
 changed.repos.std1[field]=field==='commit'?'f'.repeat(40):base+'/wrong-'+field;
 await fs.writeFile(file,JSON.stringify(changed));
 try{await run('config-'+field,resume,1,/WORK_INPUT_MISMATCH/);assert.deepEqual(await fs.readFile(work+'/build-result.json'),state);assert.equal(await calls(),2);}
 finally{await fs.writeFile(file,before);}
}
for(const kind of ['no-prior','unknown-stage','skipped-stage','records-without-resume']) {
 let args=[...resume];const stateFile=work+'/build-result.json',saved=work+'/saved-state.json';
 if(kind==='no-prior')await fs.rename(stateFile,saved);
 if(kind==='unknown-stage')args[1]='missing';
 if(kind==='skipped-stage')args.push('--from','stage2');
 if(kind==='records-without-resume')args.splice(0,2);
 const before=await fs.readFile(stateFile).catch(()=>null);
 try{await run(kind,args,1,/STD_RESUME|WORK_INPUT/);assert.deepEqual(await fs.readFile(stateFile).catch(()=>null),before);assert.equal(await calls(),2);}
 finally{if(kind==='no-prior')await fs.rename(saved,stateFile);}
}
await run('from',['--from','stage3-std']);assert.equal(await calls(),4);
await fs.writeFile(predecessor,'41\n');
try{await run('predecessor-reject',['--from','stage3-std'],65,/PREDECESSOR_ASSERTION_REACHED 41/);assert.equal(await calls(),4);}
finally{await fs.writeFile(predecessor,'42\n');}
await run('full-restored',[]);assert.equal(await calls(),6);
} else {
  // The preceding unknown failure lost the predecessor record. Repair via the
  // public normal entry; never synthesize a production record or replace inputs.
  await run('repair-predecessor-record',[]);
}
// These failures execute the real public command/adapter; the tiny producer is
// explicit fixture input, while installed String compilation consumes real C2.
const normalArgs = ['--from','stage3-std'];
const tracked = base+'/checkout/stdlib/build.py';
const original = await fs.readFile(tracked);
await fs.appendFile(tracked, '\n# dirty tracked source\n');
try { const n=await calls(); await run('dirty-checkout',normalArgs,1,/SOURCE_CHECKOUT std1/); assert.equal(await calls(),n); }
finally { await fs.writeFile(tracked, original); }
for (const phase of ['build','install']) {
  process.env.SDK_FIXTURE_FAIL=phase;
  try { await run('real-failed-'+phase,normalArgs,7,/'?TARGET_FAILED rc=7/); }
  finally { delete process.env.SDK_FIXTURE_FAIL; }
  const failedRecords=evidence+'/real-failed-'+phase+'.stdout';
  const n=await calls();
  await run('reject-real-failed-'+phase,['--resume-installed','stage3-std','--accept-records',failedRecords],1,/STD_RESUME_RECORD/);
  assert.equal(await calls(),n);
}
for (const signal of ['SIGTERM','SIGINT']) {
  const ready=base+'/cancel-'+signal+'.pids';
  const argv=[cli,'--config',file,'--no-package',...normalArgs];
  const child=spawn(process.execPath,argv,{env:{...process.env,SDK_FIXTURE_WAIT:'build',SDK_FIXTURE_READY:ready},stdio:['ignore','pipe','pipe']});
  let stdout='',stderr='';child.stdout.on('data',c=>stdout+=c);child.stderr.on('data',c=>stderr+=c);
  const done=new Promise(resolve=>child.once('close',(rc,sig)=>resolve({rc,signal:sig})));
  const deadline=Date.now()+30000;
  while(!fss.existsSync(ready)) {if(Date.now()>deadline){child.kill('SIGTERM');await done;assert.fail('cancel fixture not reached '+stderr);}await new Promise(r=>setTimeout(r,25));}
  const pids=JSON.parse(await fs.readFile(ready,'utf8')); child.kill(signal);
  const result=await done;
  await fs.writeFile(evidence+'/cancel-'+signal+'.stdout',stdout);await fs.writeFile(evidence+'/cancel-'+signal+'.stderr',stderr);
  rows.push({name:'cancel-'+signal,argv,...result,pids});await fs.writeFile(evidence+'/results.json',JSON.stringify(rows,null,2));
  assert.equal(result.rc,signal==='SIGINT'?130:143,stderr);
  for (const pid of pids) assert.throws(()=>process.kill(pid,0),/ESRCH/,'fixture descendant must be reaped');
  const n=await calls();
  await run('reject-cancel-'+signal,['--resume-installed','stage3-std','--accept-records',evidence+'/cancel-'+signal+'.stdout'],1,/STD_RESUME_RECORD/);
  assert.equal(await calls(),n);
}
await run('after-failure-restored',normalArgs);
const restoredRecords=evidence+'/after-failure-restored.stdout',n=await calls();
await run('after-failure-resume',['--resume-installed','stage3-std','--accept-records',restoredRecords],0,/resume-accepted/);
assert.equal(await calls(),n);
await fs.writeFile(evidence+'/completion.json',JSON.stringify({status:'PASS',buildInstallCalls:await calls(),source:commit,fullStdProduction:'NOT_RUN'}));
console.log(JSON.stringify(rows));

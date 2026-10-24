#!/usr/bin/env zx
// Finite public SDK CLI -> build.py -> actual Ninja/C2 gate. Full nativeStage
// (with actual resource settings), complete std and complete SDK qualification remain separate.
import fs from 'node:fs';
import path from 'node:path';
import assert from 'node:assert/strict';
import {spawn, spawnSync} from 'node:child_process';
import {fileURLToPath} from 'node:url';
import {setTimeout as delay} from 'node:timers/promises';
const entry=fileURLToPath(new URL('./sdk-build.mjs',import.meta.url));
const root=process.env.SDK_JOBSERVER_TEST_ROOT, sdk=process.env.JOBSERVER_TEST_SDK;
const template=process.env.SDK_JOBSERVER_TEMPLATE;
assert(root&&sdk&&template,'owned root, fixed installed SDK and finite std fixture required');
fs.mkdirSync(root,{recursive:true});
const mode=process.argv[2]||'candidate';
const buildType=process.env.JOBSERVER_TEST_BUILD_TYPE||'release';
assert(['release','relwithdebinfo'].includes(buildType));
const fixture=path.join(root,'fixture');
const env={...process.env,PATH:`${sdk}/bin:${sdk}/tools/bin:${process.env.PATH}`,CANGJIE_HOME:sdk,CJCJ_JOBSERVER_TRACE:'1',
  CANGJIE_JOBSERVER_LOG:path.join(root,mode+'.jsonl'),LD_LIBRARY_PATH:`${sdk}/runtime/lib/linux_x86_64_cjnative:${sdk}/lib/linux_x86_64_cjnative`};
for(const key of ['MAKEFLAGS','MFLAGS','CARGO_MAKEFLAGS','CJPM_JOBSERVER','CANGJIE_JOBSERVER_ROOT','CANGJIE_JOBSERVER_JOBS','CJCJ_BACKEND_CONCURRENCY'])delete env[key];
function run(name,args,extra={}) {const a=fs.openSync(path.join(root,name+'.stdout'),'w'),b=fs.openSync(path.join(root,name+'.stderr'),'w');const r=spawnSync(args[0],args.slice(1),{cwd:root,env,stdio:['ignore',a,b],timeout:300000,...extra});fs.closeSync(a);fs.closeSync(b);fs.writeFileSync(path.join(root,name+'.result.json'),JSON.stringify({args,rc:r.status,signal:r.signal,error:r.error?.message}));return {...r,stdout:fs.readFileSync(path.join(root,name+'.stdout'),'utf8'),stderr:fs.readFileSync(path.join(root,name+'.stderr'),'utf8')};}
const probe=path.join(root,'fd-probe.mjs');
fs.writeFileSync(probe,`import fs from 'node:fs';
const auth=process.env.MAKEFLAGS.match(/--jobserver-(?:auth|fds)=(\\d+),(\\d+)/);
let valid=false,detail;try{valid=!!auth&&auth.slice(1).every(fd=>fs.fstatSync(+fd).isFIFO());detail=auth?.slice(1).map(fd=>fs.readlinkSync('/proc/self/fd/'+fd));}catch(e){detail=e.code;}
console.log('SDK_FD_ASSERTION_REACHED '+JSON.stringify({valid,detail}));if(!valid)process.exit(72);
`);
function config(name,commands,test={}) {const work=path.join(root,name),install=path.join(work,'install');const c={work,install,repos:{},finalStage:'finite',stages:[{id:'finite',output:install,commands}],test};const f=path.join(root,name+'.json');fs.writeFileSync(f,JSON.stringify(c,null,2));return f;}
const python=['python3',path.join(fixture,'build.py')];
const installCommands=[{argv:[...python,'install','--prefix','${install}']}];
const tests={required:['bin/probe','bin/native_probe'],commands:[{argv:['${install}/bin/probe']},{argv:['${install}/bin/native_probe']}]};
if(mode==='candidate') {
  assert(!fs.existsSync(fixture),'fresh finite fixture required');fs.mkdirSync(fixture);
  for(const n of ['build.py','cmake','budget_a','budget_b','main.cj','CMakeLists.txt'])fs.cpSync(path.join(template,n),path.join(fixture,n),{recursive:true});
  fs.symlinkSync(fs.realpathSync(path.join(template,'scripts')),path.join(fixture,'scripts'));
  fs.writeFileSync(path.join(fixture,'native.c'),'#include <stdio.h>\nint main(void){puts("NATIVE_CONTROL_42");return 0;}\n');
  fs.appendFileSync(path.join(fixture,'CMakeLists.txt'),'\nadd_executable(native_probe native.c)\ninstall(TARGETS native_probe RUNTIME DESTINATION bin)\n');
}
if(['candidate','cut','restored'].includes(mode)) {
  const commands=[{argv:['node',probe]}];
  if(mode==='candidate')commands.push({argv:[...python,'build','-t',buildType,'--jobs','4','--package-jobs','2']},...installCommands);
  const file=config(mode,commands,mode==='candidate'?tests:{});
  const makefile=path.join(root,mode+'.mk');fs.writeFileSync(makefile,`all:\n\t+node ${entry} --config ${file} --no-package\n`);
  const r=run(mode,['make','-s','-j4','-f',makefile]);
  assert.match(r.stdout,/SDK_FD_ASSERTION_REACHED/);
  if(mode==='cut') {assert.notEqual(r.status,0);assert.match(r.stdout,/"valid":false/);assert.match(r.stdout,/"rc":72/);}
  else {assert.equal(r.status,0,r.stderr);assert.match(r.stdout,/"valid":true/);}
  if(mode==='candidate') {
    assert.match(r.stdout,/NATIVE_CONTROL_42/);assert.match(r.stdout,/(?:^|\n)16\s*(?:\n|$)/);
    const events=fs.readFileSync(env.CANGJIE_JOBSERVER_LOG,'utf8').trim().split('\n').map(JSON.parse);
    assert(events.some(e=>e.event==='pool-start'&&e.imported&&e.borrowed===3&&e.jobs===4));
    assert(events.some(e=>e.event==='parent-return'&&e.count===3));
    const commands=events.filter(e=>e.event==='command-start').map(e=>e.command);
    assert.equal(commands.filter(c=>c[0]==='cjc').length,5);
    if(buildType==='relwithdebinfo') {
      const packages=commands.filter(c=>c[0]==='cjc'&&c.includes('-p'));
      assert.equal(packages.length,4);assert(packages.every(c=>c.includes('--apc=1')));
    }
    assert(commands.some(c=>c.includes('-c')&&c.some(v=>v.endsWith('/native.c'))),'native compile consumes shared budget');
    assert(commands.some(c=>c.includes('-o')&&c.includes('native_probe')),'native link consumes shared budget');
    const peaks=[...(r.stdout+r.stderr).matchAll(/CJCJ_JOBSERVER acquired=(\d+) released=(\d+) active=(\d+) peak=(\d+) held_tokens=(\d+)/g)].map(m=>m.slice(1).map(Number));
    assert.equal(peaks.length,5);assert(peaks.every(([a,b,c,p,h])=>a>0&&a===b&&c===0&&p>=1&&p<=4&&h===0));assert(peaks.some(x=>x[3]>1));
    fs.writeFileSync(path.join(root,'candidate-consumers.json'),JSON.stringify({commands,peaks},null,2));
  }
  const plain=config(mode+'-control',[{argv:['node','-e','console.log("INDEPENDENT_CONTROL_42")']}]);
  const control=run(mode+'-control',['node',entry,'--config',plain,'--no-package']);assert.equal(control.status,0);assert.match(control.stdout,/INDEPENDENT_CONTROL_42/);
  console.log('SDK_'+mode.toUpperCase()+'_FD_AND_INDEPENDENT_CONTROL_PASS');
} else if(mode==='cache') {
  const previous=JSON.parse(fs.readFileSync(path.join(root,'candidate-consumers.json')));
  assert.equal(previous.commands.filter(c=>c[0]==='cjc').length,5,'real compilation positive control');
  const file=path.join(root,'candidate.json'),makefile=path.join(root,'cache.mk');
  fs.writeFileSync(makefile,`all:\n\t+node ${entry} --config ${file} --from finite --no-package\n`);
  const r=run('cache',['make','-s','-j4','-f',makefile]);
  assert.equal(r.status,0,r.stderr);assert.match(r.stdout,/NATIVE_CONTROL_42/);
  const events=fs.readFileSync(env.CANGJIE_JOBSERVER_LOG,'utf8').trim().split('\n').map(JSON.parse);
  const commands=events.filter(e=>e.event==='command-start').map(e=>e.command);
  const compiler=commands.filter(c=>c[0]==='cjc');
  const archive=commands.filter(c=>/(^|\/)(?:llvm-)?ar$/.test(c[0]));
  fs.writeFileSync(path.join(root,'cache-classification.json'),JSON.stringify({previousCompiler:5,
    compiler:compiler.length,archive:archive.length,commands},null,2));
  assert.equal(compiler.length,0,'same input/configuration must not recompile');
  assert(events.some(e=>e.event==='parent-return'&&e.count===3));
  console.log('SDK_CACHE_REAL_COMPILER_POSITIVE_AND_RESUME_PASS');
} else if(mode==='cancel') {
  // Reuse input bytes, only make the existing main source newer than its output.
  const now=new Date();fs.utimesSync(path.join(fixture,'main.cj'),now,now);
  const fifo=path.join(root,'cancel-parent.fifo');assert.equal(run('mkfifo',['mkfifo',fifo]).status,0);
  const fd=fs.openSync(fifo,fs.constants.O_RDWR|fs.constants.O_NONBLOCK);fs.writeSync(fd,Buffer.from('abc'));
  const file=config('cancel',[{argv:[...python,'build','-t',buildType,'--jobs','4']}]);
  const a=fs.openSync(path.join(root,'cancel.stdout'),'w'),b=fs.openSync(path.join(root,'cancel.stderr'),'w');
  const child=spawn('node',[entry,'--config',file,'--no-package'],{cwd:root,env:{...env,MAKEFLAGS:`--jobserver-auth=fifo:${fifo} -j4`},stdio:['ignore',a,b]});
  let final;const done=new Promise(resolve=>child.once('exit',(rc,signal)=>{final={rc,signal};resolve(final);}));
  const expected=fs.realpathSync(path.join(sdk,JSON.parse(fs.readFileSync(path.join(sdk,'STAGE-INPUTS.json'))).compilerFile));
  let observed,group;
  try {
    for(let i=0;i<2000&&!final;i++) {
      const events=fs.existsSync(env.CANGJIE_JOBSERVER_LOG)?fs.readFileSync(env.CANGJIE_JOBSERVER_LOG,'utf8').trim().split('\n').filter(Boolean).map(JSON.parse):[];
      const pool=events.find(e=>e.event==='pool-start');group=pool?.pid; // root launches group whose id is Ninja child; obtain below from proc.
      for(const name of fs.readdirSync('/proc').filter(n=>/^\d+$/.test(n)))try {
        if(fs.realpathSync('/proc/'+name+'/exe')!==expected)continue;
        const cwd=fs.realpathSync('/proc/'+name+'/cwd');if(!cwd.startsWith(fixture))continue;
        const fields=fs.readFileSync('/proc/'+name+'/stat','utf8').split(') ')[1].split(' ');
        observed={pid:+name,exe:expected,cwd,group:+fields[2]};group=observed.group;break;
      }catch{}
      if(observed)break;await delay(10);
    }
    assert(observed,'actual installed C2 must execute before cancelling public SDK entry');
    child.kill('SIGTERM');const result=await done;assert.equal(result.rc,143);
    const bytes=Buffer.alloc(3);assert.equal(fs.readSync(fd,bytes,0,3,null),3);assert.equal([...bytes].sort().join(''),[...Buffer.from('abc')].sort().join(''));
    for(const name of fs.readdirSync('/proc').filter(n=>/^\d+$/.test(n))) {
      let fields;try{fields=fs.readFileSync('/proc/'+name+'/stat','utf8').split(') ')[1].split(' ');}catch{continue;}
      assert(!(Number(fields[2])===group&&fields[0]!=='Z'),'no owned live compiler group after token return');
    }
    fs.writeFileSync(path.join(root,'cancel.result.json'),JSON.stringify({result,observed,returned:bytes.toString()}));
    console.log('SDK_PUBLIC_CANCEL_REAL_C2_AND_PARENT_RETURN_PASS');
  } finally {
    if(!final){child.kill('SIGTERM');await done;}fs.closeSync(a);fs.closeSync(b);fs.closeSync(fd);
  }
} else throw Error('unknown mode '+mode);

#!/usr/bin/env zx
// Actual Linux_CJNATIVE command generation and RuntimeInit/OpenMacroLibrary
// host control. This does not replace the public paired CJ macro gate.
import fs from 'node:fs';
import path from 'node:path';
import assert from 'node:assert/strict';
import {spawnSync} from 'node:child_process';
const [consumer,checker,runtime,work,arm]=process.argv.slice(2);
assert.ok(consumer&&checker&&runtime&&work&&['red','fixed'].includes(arm));
fs.mkdirSync(work);fs.mkdirSync(path.join(work,'old-runtime'));
const records=[];
function run(name,args,want=0,env=process.env){
  const started=new Date().toISOString();
  const p=spawnSync(args[0],args.slice(1),{cwd:work,env,encoding:'utf8',timeout:60000});
  const r={name,args,started,ended:new Date().toISOString(),pid:p.pid,rc:p.status,signal:p.signal,error:p.error?.message??null,stdout:p.stdout,stderr:p.stderr};
  records.push(r);fs.writeFileSync(path.join(work,'commands.json'),JSON.stringify(records,null,2));
  assert.equal(p.error,undefined);assert.equal(p.signal,null);assert.equal(p.status,want);return p.stdout;
}
const clean=Object.fromEntries(Object.entries(process.env).filter(([k])=>!['LD_LIBRARY_PATH','LD_PRELOAD','LD_AUDIT'].includes(k)));
const env={...process.env,M1_WORK:work};
const source=path.join(work,'image.c');
fs.writeFileSync(source,'#include <stdio.h>\n__attribute__((constructor)) static void init(void){puts("M1_IMAGE_INIT");}\nint binding_value(void){return 42;}\n');
function link(name,paths){run('link-'+name,['clang-15','-shared','-fPIC',source,'-Wl,--disable-new-dtags',...paths.map(p=>'-Wl,-rpath,'+p),'-o',path.join(work,name)],0,clean);}
const generated=run('macro-producer-options',[consumer,'macro'],arm==='red'?2:0,env);
assert.match(generated,/LINK_PATH_ASSERT macro=true reached=1/);
const paths=generated.split('\n').filter(l=>l.startsWith('RPATH=')).map(l=>l.slice(6));assert.equal(paths.length,2);
link('generated.so',paths);
run('generated-dynamic',['readelf','-d',path.join(work,'generated.so')],0,clean);
run('generated-admission',[checker,path.join(work,'generated.so'),runtime],arm==='red'?2:0);
assert.match(run('ordinary-control',[consumer,'ordinary'],0,env),/LINK_PATH_ASSERT macro=false reached=1 matches=true/);
// Merely adding the new SDK at the tail cannot cure an older first binding.
link('old-before-current.so',[path.join(work,'old-runtime'),runtime]);
run('old-before-current-refused',[checker,path.join(work,'old-before-current.so'),runtime],2);
link('old.so',[path.join(work,'old-runtime')]);link('current.so',[runtime]);
const borrowed=run('borrowed-host',[consumer,'borrowed'],arm==='red'?3:0,env);
assert.match(borrowed,/BORROWED_STALE rejected=true/);
assert.match(borrowed,/BORROWED_BINDING_ASSERT handleNone=true opened=/);
if(arm==='red'){assert.doesNotMatch(borrowed,/M1_IMAGE_INIT/);}
else {assert.equal(borrowed.split('M1_IMAGE_INIT').length-1,1);assert.match(borrowed,/BORROWED_CLOSE_CONTROL task42=true hostAlive=true/);}
console.log('M1_R12_'+arm.toUpperCase()+'_ASSERTIONS_REACHED');

import test from'node:test';import assert from'node:assert/strict';import {remoteCommand}from'../../tools/srcbuild-kkk2.mjs';
test('native build launcher disables both core limits and calls the actual flow',()=>{
 const c=remoteCommand({source:'/root/lane/source',config:'/root/lane/targets.json',from:'stage2',through:'stage3'});
 assert.match(c,/ulimit -c 0; ulimit -Hc 0;/);assert.match(c,/ci\/bootstrap\/sdk-flow.mjs/);assert.match(c,/'--from' 'stage2'/);assert.match(c,/'--through' 'stage3'/);
});
test('remote arguments remain literal shell data',()=>{
 const c=remoteCommand({source:'/root/lane/single\'quote',config:'/root/lane/$(touch pwn).json'});
 assert.ok(c.includes("'\\''"));assert.ok(c.includes("'/root/lane/$(touch pwn).json'"));
 assert.throws(()=>remoteCommand({source:'/root/x',config:'/root/a\nnode evil'}),/REMOTE_ARGUMENT/);
 assert.throws(()=>remoteCommand({source:'/tmp/x',config:'/root/a'}),/REMOTE_PRIVATE_PATH/);
});


// Observe the public launcher at the actual wf spawn boundary. This test does
// not invoke a remote build or claim any runner/stage qualification.
import fs from 'node:fs';import os from 'node:os';import path from 'node:path';import {spawnSync} from 'node:child_process';
test('public native launcher preserves admitted resources, explicit memory and child rc', t => {
 const root=fs.mkdtempSync(path.join(os.tmpdir(),'native-launch-resource-'));
 t.after(()=>fs.rmSync(root,{recursive:true,force:true}));
 const hook=path.join(root,'observe.mjs'),record=path.join(root,'spawn.json');
 fs.writeFileSync(hook,`import fs from 'node:fs';import cp from 'node:child_process';import {syncBuiltinESMExports} from 'node:module';
 cp.spawnSync=(exe,args,options)=>{fs.writeFileSync(process.env.OBSERVED_SPAWN,JSON.stringify({exe,args,jobs:options.env.KKK2_JOBS??null,memory:options.env.KKK2_MEM_GB??null}));return {status:37,signal:null};};syncBuiltinESMExports();`);
 const entry=new URL('../../tools/srcbuild-kkk2.mjs',import.meta.url).pathname;
 for(const [label,extra,parent,expected] of [
  ['inherited',[],{KKK2_JOBS:'2',KKK2_MEM_GB:'8'},{jobs:'2',memory:'8'}],
  ['explicit',['--memory-gb','3'],{KKK2_JOBS:'2',KKK2_MEM_GB:'8'},{jobs:'2',memory:'3'}],
  ['controller-defaults',[],{},{jobs:null,memory:null}],
 ]) {
  const env={...process.env,OBSERVED_SPAWN:record};delete env.KKK2_JOBS;delete env.KKK2_MEM_GB;Object.assign(env,parent);
  const r=spawnSync(process.execPath,['--import',hook,entry,'--lane','finite',
   '--source','/mnt/cjcj-data/finite/source','--config','/mnt/cjcj-data/finite/config.json',...extra],{env,encoding:'utf8'});
  assert.equal(r.status,37,r.stderr);const observed=JSON.parse(fs.readFileSync(record,'utf8'));
  assert.equal(observed.exe,'/root/cj_build/tools/cjops');assert.deepEqual(observed.args.slice(0,4),['control','wf-kkk2','bsh','finite']);
  assert.deepEqual({jobs:observed.jobs,memory:observed.memory},expected,label);
  console.log('PUBLIC_NATIVE_LAUNCH_RESOURCES '+JSON.stringify({label,...observed,rc:r.status}));
 }
 for(const extra of [['--memory-gb','0'],['--source','/mnt/cjcj-data/finite/../other/source']]) {
  fs.rmSync(record);const r=spawnSync(process.execPath,['--import',hook,entry,'--lane','finite',
   '--source','/root/finite/source','--config','/root/finite/config.json',...extra],{env:{...process.env,OBSERVED_SPAWN:record},encoding:'utf8'});
  assert.equal(r.status,1);assert.match(r.stderr,/MEMORY_GB|LANE_PATH/);assert.equal(fs.existsSync(record),false);
  fs.writeFileSync(record,'not an executed spawn');
 }
});

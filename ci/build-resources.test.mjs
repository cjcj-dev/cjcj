import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';
import {spawnSync} from 'node:child_process';
const repo=path.resolve(import.meta.dirname,'..');
const env={...process.env};
for(const name of ['CJ_HEAP','cjHeapSize','KKK2_JOBS','CANGJIE_BUILD_JOBS','CMAKE_BUILD_PARALLEL_LEVEL'])delete env[name];
const root=await fs.mkdtemp(path.join(process.env.BUILD_RESOURCE_EVIDENCE||os.tmpdir(),'build-resources-'));
if(!process.env.BUILD_RESOURCE_EVIDENCE)test.after(()=>fs.rm(root,{recursive:true,force:true}));
const records=[];
async function run(label,argv,options={}) {
 const r=spawnSync(argv[0],argv.slice(1),{cwd:repo,env,encoding:'utf8',...options});
 assert.ifError(r.error);assert.equal(r.signal,null);
 await fs.writeFile(path.join(root,label+'.log'),r.stdout+r.stderr);
 records.push({label,argv,rc:r.status,signal:r.signal});await fs.writeFile(path.join(root,'commands.json'),JSON.stringify(records,null,2));
 return {...r,text:r.stdout+r.stderr};
}
const cli=[process.execPath,path.join(repo,'ci/build-resources.mjs'),'--json'];
let selected;
test('resource CLI defaults follow actual memory and CPU quota',async()=>{
 const r=await run('default',cli);assert.equal(r.status,0,r.text);selected=JSON.parse(r.stdout);
 const limit=process.constrainedMemory(),memory=Math.min(os.totalmem(),limit>0?limit:Infinity);
 assert.equal(selected.memory,memory);
 assert.equal(selected.heap,Math.min(96*1024,Math.floor(memory*3/4/1024**2))+'MB');
 assert.equal(selected.jobs,selected.cpus);
 if(process.env.BUILD_RESOURCE_EXPECT_CPUS)assert.equal(selected.cpus,Number(process.env.BUILD_RESOURCE_EXPECT_CPUS));
 console.log('EFFECTIVE_RESOURCES_OBSERVED '+JSON.stringify(selected));
});
test('explicit maximum heap and jobs remain explicit; malformed input fails',async()=>{
 const jobs=os.availableParallelism()+1;
 const r=await run('explicit',[...cli,'4MB'],{env:{...env,CANGJIE_BUILD_JOBS:String(jobs)}});
 assert.equal(r.status,0,r.text);const value=JSON.parse(r.stdout);assert.equal(value.heap,'4MB');assert.equal(value.jobs,jobs);
 const impossible=await run('over-memory',[...cli,Math.ceil(os.totalmem()/1024**2+1)+'MB']);
 assert.equal(impossible.status,0,impossible.text);assert.match(impossible.stderr,/above observed memory/);
 assert.equal(JSON.parse(impossible.stdout).heap,Math.ceil(os.totalmem()/1024**2+1)+'MB');
 for(const heap of ['2MB','4 mb']) {const valid=await run('valid-'+heap.replace(/ /g,''),[...cli,heap]);assert.equal(valid.status,0,valid.text);assert.equal(JSON.parse(valid.stdout).heap,heap);}
 const malformed=await run('bad-heap',[...cli,'0MB']);assert.equal(malformed.status,1);assert.match(malformed.stderr,/BUILD_HEAP invalid/);
 const bounded=await run('declared-budget',cli,{env:{...env,KKK2_JOBS:'1'}});assert.equal(bounded.status,0,bounded.text);assert.equal(JSON.parse(bounded.stdout).jobs,1);
 const conflict=await run('budget-conflict',cli,{env:{...env,KKK2_JOBS:'1',CANGJIE_BUILD_JOBS:'2'}});assert.equal(conflict.status,1);assert.match(conflict.stderr,/exceeds declared KKK2_JOBS budget=1/);
 const bad=await run('bad-jobs',cli,{env:{...env,CANGJIE_BUILD_JOBS:'0'}});
 assert.equal(bad.status,1);assert.match(bad.stderr,/BUILD_JOBS/);
});
test('public native-stage passes default and explicit resources to its selected source producer',async()=>{
 const source=path.join(root,'source');await fs.mkdir(path.join(source,'runtime_shim'),{recursive:true});
 await fs.writeFile(path.join(source,'cjpm.toml'),'[package]\nname="resource-transport"\n');
 await fs.writeFile(path.join(source,'runtime_shim/build_shim.mjs'),"console.log('RESOURCE_PRODUCER '+JSON.stringify({heap:process.env.cjHeapSize,jobs:process.env.CANGJIE_BUILD_JOBS}));process.exit(17);\n");
 for(const [label,args] of [['init',['init']],['add',['add','.']],['commit',['-c','user.name=Zxilly','-c','user.email=zxilly@outlook.com','commit','-m','Finite resource entry']]]) {
  const r=await run('git-'+label,['git','-C',source,...args]);assert.equal(r.status,0,r.text);
 }
 const head=await run('git-head',['git','-C',source,'rev-parse','HEAD']);
 const platform=({linux:'linux',darwin:'darwin',win32:'windows'}[process.platform])+'_'+(process.arch==='arm64'?'aarch64':'x86_64');
 const argv=[process.execPath,path.join(repo,'ci/bootstrap/sdk-native-stage.mjs'),'--kind','compiler','--zx',process.execPath,'--source',source,'--commit',head.stdout.trim(),'--sdk',root+'/absent-sdk','--output',root+'/stage','--platform',platform];
 for(const [label,args,heap,jobs] of [['default',[],Math.min(48*1024,Math.floor(selected.memory*3/4/1024**2))+'MB',selected.cpus],['explicit',['--heap','4MB','--jobs',String(os.availableParallelism()+1)],'4MB',os.availableParallelism()+1]]) {
  const r=await run('stage-'+label,[...argv,...args]);
  assert.equal(r.status,17,r.text);
  const observed=JSON.parse(r.stdout.match(/RESOURCE_PRODUCER (.+)/)?.[1]||'null');
  assert.deepEqual(observed,{heap,jobs:String(jobs)});
 }
});

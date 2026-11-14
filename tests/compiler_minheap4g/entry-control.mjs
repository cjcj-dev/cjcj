#!/usr/bin/env zx
import fs from 'node:fs';
import path from 'node:path';
import {spawnSync} from 'node:child_process';
const source=path.resolve(import.meta.dirname,'../..'),root=path.dirname(source),out=root+'/entry-control';
fs.mkdirSync(out);fs.mkdirSync(out+'/home');fs.mkdirSync(out+'/tmp');
const env={PATH:'/usr/local/bin:/usr/bin:/bin',HOME:out+'/home',TMPDIR:out+'/tmp',LANG:'C.UTF-8'};
const read=p=>fs.readFileSync(p,'utf8').trim();
const records={steps:[],claims:[]};const save=()=>fs.writeFileSync(out+'/result.json',JSON.stringify(records,null,2));
function run(name,argv,environment=env,expected=0){
 const r=spawnSync(argv[0],argv.slice(1),{cwd:out,env:environment,encoding:'utf8',timeout:60000});
 fs.writeFileSync(out+'/'+name+'.stdout',r.stdout??'');fs.writeFileSync(out+'/'+name+'.stderr',r.stderr??'');
 records.steps.push({name,argv,env:environment,rc:r.status,signal:r.signal,error:r.error?.message??null});save();
 if(r.status!==expected||r.signal||r.error)throw Error(name+' rc='+r.status+' '+r.stderr);return r;
}
const keys=[];let rc=1;
try{
 for(const [suffix,cpus] of [['cpu','32-33'],['smt','128-129']]){
  const key='backport_compiler_astra_1112-minheap-entry-'+suffix;
  const r=spawnSync('bash',['/root/cjtools/measure_claim.sh','claim',key,cpus,'compiler minheap final entry control'],{encoding:'utf8',env:{...env,MEASURE_OWNER_PID:String(process.pid)}});
  records.claims.push({key,cpus,rc:r.status,stdout:r.stdout,stderr:r.stderr});save();if(r.status!==0)throw Error('claim');keys.push(key);
 }
 const cg='/sys/fs/cgroup'+read('/proc/self/cgroup').split('::').at(-1);
 records.resources=Object.fromEntries(['cpuset.cpus.effective','memory.max','memory.swap.max'].map(k=>[k,read(cg+'/'+k)]));records.limits=read('/proc/self/limits');save();
 if(records.resources['memory.swap.max']!=='0'||!records.limits.match(/Max core file size\s+0\s+0/))throw Error('resources');
 const ref=read(source+'/.git').includes('gitdir:')?spawnSync('git',['-C',source,'rev-parse','HEAD'],{encoding:'utf8'}).stdout.trim():null;
 const r=run('parent-argument-parser',[process.execPath,source+'/ci/bootstrap/sdk-native-stage.mjs','--kind','entry-control','--source',source,'--commit',ref,'--sdk',root+'/attempt3/install','--runtime',root+'/attempt3/install','--output',out+'/stage','--platform','linux_x86_64','--private-tools',out+'/unused-legacy-tools','--jobs','1','--heap','4GB'],env,1);
 if(!r.stderr.includes('NATIVE_TARGET_KIND entry-control')||r.stderr.includes('Unknown option'))throw Error('parent argument compatibility');
 run('normal-parent-graph',[process.execPath,'--test',source+'/ci/bootstrap/sdk-targets.test.mjs']);
 const install=root+'/attempt3/install';
 run('application-default',[root+'/attempt4/native/target-cj-cut'],{...env,LD_LIBRARY_PATH:install+'/runtime/lib/linux_x86_64_cjnative:'+install+'/lib/linux_x86_64_cjnative',CJCJ_TEST_HEAP_BYTES:'268435456',CJCJ_TEST_HEAP_ENV:'<unset>'});
 rc=0;
}catch(e){records.error=e.stack;}finally{
 for(const key of keys){const r=spawnSync('bash',['/root/cjtools/measure_claim.sh','release',key],{encoding:'utf8'});records.claims.push({key,releaseRc:r.status,stdout:r.stdout,stderr:r.stderr});}
 records.rc=rc;save();
}
process.exit(rc);

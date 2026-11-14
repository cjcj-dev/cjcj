#!/usr/bin/env zx
import fs from 'node:fs';
import path from 'node:path';
import assert from 'node:assert/strict';
import {spawnSync} from 'node:child_process';
const source=path.resolve(import.meta.dirname,'../..'),root=path.dirname(source);
const [ref,attempt='attempt1']=globalThis.argv?._??process.argv.slice(2);
const out=root+'/publish-parent/'+attempt;
fs.mkdirSync(out,{recursive:true});for(const n of ['home','tmp','evidence'])fs.mkdirSync(out+'/'+n);
const env={PATH:'/usr/local/bin:/usr/bin:/bin',HOME:out+'/home',TMPDIR:out+'/tmp',LANG:'C.UTF-8',LC_ALL:'C.UTF-8',
 RELEASE_EVIDENCE_TEST_ROOT:out+'/evidence',STDX_FACTS_EVIDENCE:out+'/stdx',CANGJIE_BUILD_JOBS:'4',CMAKE_BUILD_PARALLEL_LEVEL:'4',
 CMAKE_C_COMPILER_LAUNCHER:'ccache',CMAKE_CXX_COMPILER_LAUNCHER:'ccache',CCACHE_DIR:'/root/.ccache'};
const record={ref,source,out,start:new Date().toISOString(),steps:[],claims:[]};
const save=()=>fs.writeFileSync(out+'/result.json',JSON.stringify(record,null,2));
const read=p=>fs.readFileSync(p,'utf8');
function run(name,args,expected=0){
 const fd=fs.openSync(out+'/'+name+'.log','wx'),argv=[process.execPath,'--test',...args];
 const row={name,argv,cwd:source,env,start:new Date().toISOString()};record.steps.push(row);save();
 const r=spawnSync(argv[0],argv.slice(1),{cwd:source,env,stdio:['ignore',fd,fd],timeout:180000});fs.closeSync(fd);
 Object.assign(row,{rc:r.status,signal:r.signal,error:r.error?.message,end:new Date().toISOString()});save();console.log(name+' rc='+r.status);
 assert.ifError(r.error);assert.equal(r.signal,null);assert.equal(r.status,expected,read(out+'/'+name+'.log'));
}
const held=[];let rc=1;
try{
 for(const [suffix,cpus]of [['cpu','32-35'],['smt','128-131']]){
  const key='backport_compiler_astra_1112-publish-parent-'+suffix;
  const r=spawnSync('bash',['/root/cjtools/measure_claim.sh','claim',key,cpus,'SDK publication regressions'],{env:{...env,MEASURE_OWNER_PID:String(process.pid)},encoding:'utf8'});
  record.claims.push({key,cpus,rc:r.status,stdout:r.stdout,stderr:r.stderr});save();assert.equal(r.status,0);held.push(key);
 }
 const cg='/sys/fs/cgroup'+read('/proc/self/cgroup').trim().split('::').at(-1);
 record.resources=Object.fromEntries(['cpuset.cpus.effective','memory.max','memory.swap.max'].map(k=>[k,read(cg+'/'+k).trim()]));record.limits=read('/proc/self/limits');save();
 assert.equal(record.resources['memory.swap.max'],'0');assert.match(record.limits,/Max core file size\s+0\s+0/);
 assert.equal(spawnSync('git',['rev-parse','HEAD'],{cwd:source,encoding:'utf8'}).stdout.trim(),ref);
 record.reused={candidate:'7ccf69509c40d6a66da3053009152e9aacb88486',results:root+'/publish-parent/attempt1/result.json',steps:['cut-hle','cut-archive-control','hle-recovery']};save();
 run('tools-recovery',['build/test/source-tool-install-interface.test.mjs']);
 run('stdx-cli',['build/test/installed-stdx-cli.test.mjs']);
 // archive paths are independent of component cleanup; the cut control already
 // executes the unchanged retainReplaced=true branch, do not duplicate it.
 const r=spawnSync('git',['diff','--exit-code'],{cwd:source,encoding:'utf8'});record.restored={rc:r.status,stdout:r.stdout,stderr:r.stderr};assert.equal(r.status,0);
 rc=0;
}catch(e){record.error=e.stack;console.error(e);}finally{
 for(const key of held){const r=spawnSync('bash',['/root/cjtools/measure_claim.sh','release',key],{encoding:'utf8'});record.claims.push({key,releaseRc:r.status,stdout:r.stdout,stderr:r.stderr});}
 record.rc=rc;record.end=new Date().toISOString();save();
}
process.exit(rc);

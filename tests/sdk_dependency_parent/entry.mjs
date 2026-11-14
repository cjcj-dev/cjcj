#!/usr/bin/env zx
import fs from 'node:fs';
import path from 'node:path';
import assert from 'node:assert/strict';
import {spawnSync} from 'node:child_process';
import {compilerNativeShim} from '../../ci/bootstrap/native-shim-inputs.mjs';
const source=path.resolve(import.meta.dirname,'../..'),root=path.dirname(source);
const [ref,attempt='attempt1']=process.argv.slice(2);
const out=root+'/dependency-parent/'+attempt,sol='/mnt/cjcj-data/impl_full_sdk_sol_1108/integrated-gc-1114';
fs.mkdirSync(out,{recursive:true});for(const name of ['home','tmp'])fs.mkdirSync(out+'/'+name);
const env={PATH:'/usr/local/bin:/usr/bin:/bin',HOME:out+'/home',TMPDIR:out+'/tmp',LANG:'C.UTF-8',LC_ALL:'C.UTF-8',RELEASE_EVIDENCE_TEST_ROOT:out+'/tmp'};
const record={ref,source,out,start:new Date().toISOString(),steps:[],claims:[]};
const save=()=>fs.writeFileSync(out+'/result.json',JSON.stringify(record,null,2));
const read=p=>fs.readFileSync(p,'utf8');
const json=p=>JSON.parse(read(p));
function run(name,argv,{cwd=source,environment=env,expected=0}={}) {
 const fd=fs.openSync(out+'/'+name+'.log','wx');
 const row={name,argv,cwd,env:environment,start:new Date().toISOString()};record.steps.push(row);save();
 const r=spawnSync(argv[0],argv.slice(1),{cwd,env:environment,stdio:['ignore',fd,fd],timeout:120000});fs.closeSync(fd);
 Object.assign(row,{rc:r.status,signal:r.signal,error:r.error?.message,end:new Date().toISOString()});save();console.log(name+' rc='+r.status);
 assert.ifError(r.error);assert.equal(r.signal,null);assert.equal(r.status,expected,read(out+'/'+name+'.log'));return row;
}
const acquired=[];let rc=1;
try {
 for(const [suffix,cpus]of [['cpu','32-35'],['smt','128-131']]) {
  const key='backport_compiler_astra_1112-dependency-parent-'+suffix;
  const r=spawnSync('bash',['/root/cjtools/measure_claim.sh','claim',key,cpus,'SDK dependency parent regression'],{env:{...env,MEASURE_OWNER_PID:String(process.pid)},encoding:'utf8'});
  record.claims.push({key,cpus,rc:r.status,stdout:r.stdout,stderr:r.stderr});save();assert.equal(r.status,0);acquired.push(key);
 }
 const cg='/sys/fs/cgroup'+read('/proc/self/cgroup').trim().split('::').at(-1);
 record.resources=Object.fromEntries(['cpuset.cpus.effective','memory.max','memory.swap.max'].map(k=>[k,read(cg+'/'+k).trim()]));record.limits=read('/proc/self/limits');
 record.siblings=Object.fromEntries([32,35].map(c=>[c,read(`/sys/devices/system/cpu/cpu${c}/topology/thread_siblings_list`).trim()]));save();
 assert.equal(record.resources['memory.swap.max'],'0');assert.match(record.limits,/Max core file size\s+0\s+0/);
 assert.equal(spawnSync('git',['rev-parse','HEAD'],{cwd:source,encoding:'utf8'}).stdout.trim(),ref);
 run('regressions',[process.execPath,'--test','ci/native-llvm-inputs.test.mjs','ci/bootstrap/sdk-targets.test.mjs','ci/bootstrap/native-workflow.test.mjs']);
 const original=sol+'/sdk-descriptor-2ceb.json',descriptor=json(original),shim=sol+'/shim-2ceb/install';
 record.originalDescriptor=original;record.originalDependencies=descriptor.stdDependencies;save();
 // Preserve the original compiler/H1/stdlib/N selections and complete dependencies.
 // Only outputs and the new explicit shim selection belong to this attempt.
 function prepare(label,alter=()=>{},expected=0) {
  const d=structuredClone(descriptor);d.work=out+'/'+label+'/work';d.install=out+'/'+label+'/install';d.archive=out+'/'+label+'/sdk.tar.gz';
  d.installations.shim={install:shim};alter(d);
  fs.mkdirSync(out+'/'+label,{recursive:true});const file=out+'/'+label+'/descriptor.json';fs.writeFileSync(file,JSON.stringify(d,null,2));
  run(label,[process.execPath,source+'/ci/bootstrap/prepare-bootstrap-plans.mjs'],{expected,environment:{...env,CJCJ_NATIVE_INPUTS:file,CANGJIE_WORKSPACE:out+'/'+label+'/configuration',GITHUB_ENV:''}});
  if(expected)return null;
  const graph=json(out+'/'+label+'/configuration/build-targets.json');
  const input=json(d.work+'/sdk-inputs.json');assert.deepEqual(input.stdDependencies,descriptor.stdDependencies);
  for(const s of graph.stages)for(const c of s.commands||[]) {
   const a=c.argv;
   if(a.includes('--kind')&&a[a.indexOf('--kind')+1]==='std')assert.deepEqual(JSON.parse(a[a.indexOf('--std-dependencies')+1]),descriptor.stdDependencies);
  }
  for(const id of ['stage2','stage3']) {
   const a=graph.stages.find(s=>s.id===id).commands[0].argv;
   assert.equal(a[a.indexOf('--commit')+1],d.compilerCommit);
   if(d.installations.shim)assert.equal(a[a.indexOf('--shim-install')+1],shim);
   else assert.ok(!a.includes('--shim-install'));
  }
  return {d,input,graph};
 }
 const pinFile=source+'/ci/native-llvm-inputs.mjs',before=read(pinFile);
 const cut=before.replace('/^[A-Z][A-Z0-9_]*=/','/^[A-Z_]+=/');assert.notEqual(cut,before);
 fs.writeFileSync(pinFile,cut);
 try {
  const diff=spawnSync('git',['diff','--','ci/native-llvm-inputs.mjs'],{cwd:source,encoding:'utf8'});fs.writeFileSync(out+'/cut.diff',diff.stdout);assert.equal(diff.status,0);
  prepare('cut-pcre2',()=>{},1);assert.match(read(out+'/cut-pcre2.log'),/STD_DEPENDENCY_SOURCE pcre2/);
 }finally{fs.writeFileSync(pinFile,before);}
 const explicit=prepare('explicit');
 const fallback=prepare('default',d=>{delete d.installations.shim;d.compilerCommit='19cf7621b6d26396ffcc0e437908b3a9aee860e6';});
 prepare('wrong-source',d=>{d.installations.shim.install=d.installations.llvm.install;},1);
 assert.match(read(out+'/wrong-source.log'),/NATIVE_SHIM_COMPILER_SOURCE/);
 prepare('wrong-pcre2',d=>{d.stdDependencies.pcre2.commit='0'.repeat(40);},1);
 assert.match(read(out+'/wrong-pcre2.log'),/STD_DEPENDENCY_SOURCE pcre2/);
 // Use the producer's same selector, and then link the actual selected object
 // to N's LLVM. This bounded native consumer does not claim a C2 build.
 for(const [label,row]of [['explicit',explicit],['default',fallback]]) {
  const a=row.graph.stages.find(s=>s.id==='stage2').commands[0].argv;
  const selected=a.includes('--shim-install')?a[a.indexOf('--shim-install')+1]:undefined;
  const nativeInstall=row.input.llvm.install;
  const facts=await compilerNativeShim({install:selected,nativeInstall,compilerCommit:row.input.compiler.commit});
  record[label+'Shim']=facts;save();
  const object=path.join(selected||nativeInstall,facts.object.path),llvm=nativeInstall+'/third_party/llvm/lib/libLLVM-15.so',binary=out+'/'+label+'-consumer';
  run(label+'-link',['/usr/lib/llvm-15/bin/clang++','-O2','-UNDEBUG','-I'+row.d.sources.llvm+'/llvm/include',source+'/tests/sdk_dependency_parent/shim-consumer.cpp',object,llvm,'-ldl','-Wl,-rpath,'+path.dirname(llvm),'-Wl,-Map='+binary+'.map','-o',binary]);
  run(label+'-consumer',[binary]);assert.match(read(out+'/'+label+'-consumer.log'),/SHIM_ARRAY_CONSUMER_REACHED/);
 }
 await assert.rejects(compilerNativeShim({install:shim,nativeInstall:'/mnt/cjcj-data/impl_full_sdk_sol_1108/main-pair-1114/native/install',compilerCommit:descriptor.compilerCommit}),/NATIVE_SHIM_DEPENDENCY_PAIR/);
 record.wrongDependencyPair='NATIVE_SHIM_DEPENDENCY_PAIR';save();
 run('restored-source',['git','diff','--exit-code']);rc=0;
}catch(e){record.error=e.stack;console.error(e);}finally{
 for(const key of acquired){const r=spawnSync('bash',['/root/cjtools/measure_claim.sh','release',key],{encoding:'utf8'});record.claims.push({key,releaseRc:r.status,stdout:r.stdout,stderr:r.stderr});}
 record.rc=rc;record.end=new Date().toISOString();save();
}
process.exit(rc);

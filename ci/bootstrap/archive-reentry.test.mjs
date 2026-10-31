import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import os from 'node:os';
import {fileURLToPath} from 'node:url';
import {spawnSync} from 'node:child_process';
import {createHash} from 'node:crypto';
import {SHIM_SOURCE_COMMITS} from './shim-header-sources.mjs';

const parent=process.env.SDK_FLOW_TEST_ROOT||os.tmpdir();
fs.mkdirSync(parent,{recursive:true});
const root=fs.mkdtempSync(path.join(parent,'archive-reentry-'));
console.log('ARCHIVE_REENTRY_EVIDENCE='+root);
const source=path.resolve(path.dirname(fileURLToPath(import.meta.url)),'../..');
const records=[];
function run(name,argv,cwd=root,env=process.env) {
 const r=spawnSync(argv[0],argv.slice(1),{cwd,env,encoding:'utf8',maxBuffer:8*1024*1024});
 fs.writeFileSync(path.join(root,name+'.log'),(r.stdout||'')+(r.stderr||''));
 records.push({name,argv,cwd,rc:r.status,signal:r.signal,error:r.error?.message??null});
 fs.writeFileSync(path.join(root,'commands.json'),JSON.stringify(records,null,2));
 return {...r,text:(r.stdout||'')+(r.stderr||'')};
}
const digest=file=>createHash('sha256').update(fs.readFileSync(file)).digest('hex');
function archive(name,files) {
 const origin=path.join(root,name+'-input'),file=path.join(root,name+'.tar');
 fs.mkdirSync(origin);
 for(const [rel,bytes] of Object.entries(files)) {
  fs.mkdirSync(path.dirname(path.join(origin,rel)),{recursive:true});fs.writeFileSync(path.join(origin,rel),bytes);
 }
 assert.equal(run(name+'-tar',['tar','-cf',file,'-C',origin,'.']).status,0);
 return {file,sha256:digest(file)};
}

test('public build-shim reentry reaches real CMake after all source archives are moved',()=>{
 const selection={};
 for(const [name,commit] of Object.entries(SHIM_SOURCE_COMMITS)) {
  const files=name==='compiler'?{'schema/CjoFormat.fbs':'table X { value:int; }\nroot_type X;\n'}:
   name==='llvm'?{'llvm/CMakeLists.txt':'cmake_minimum_required(VERSION 3.16)\nproject(ArchiveReentry NONE)\nmessage(FATAL_ERROR "ARCHIVE_REENTRY_CMAKE_REACHED")\n'}:{'source.txt':name};
  selection[name]={commit,root:path.join(root,'materialized-'+name),archive:archive(name,files)};
 }
 const consumer=path.join(root,'consumer');fs.mkdirSync(consumer);
 const env={...process.env,CJCJ_BOOTSTRAP_SHIM_SOURCE_SELECTION:JSON.stringify(selection),
  CJCJ_RUNTIME_REF_OVERRIDE:selection.runtime.commit,CJCJ_ALLOW_RUNTIME_OVERRIDE:'true',CJCJ_NATIVE_LLVM_REF:selection.llvm.commit};
 for(const key of ['CJCJ_BOOTSTRAP_SHIM_SOURCES','CJCJ_BOOTSTRAP_RUNTIME_PIN','CJCJ_BOOTSTRAP_CPP_SRC','CANGJIE_CPP_SRC',
  'CJCJ_SRCBUILD_CONSUMER_SDK','CANGJIE_WORKSPACE','CJCJ_LLVM_SHIM_O'])delete env[key];
 const entry=[process.execPath,path.join(source,'ci/srcbuild/steps/build-shim.mjs')];
 const first=run('public-first',entry,consumer,env);
 assert.equal(first.status,1);assert.match(first.text,/ARCHIVE_REENTRY_CMAKE_REACHED/);
 for(const row of Object.values(selection)) {
  assert.ok(fs.statSync(row.root).isDirectory());fs.renameSync(row.archive.file,row.archive.file+'.moved');
 }
 const again=run('public-package-removed',entry,consumer,env);
 assert.equal(again.status,1);assert.match(again.text,/ARCHIVE_REENTRY_CMAKE_REACHED/);
 assert.doesNotMatch(again.text,/ENOENT|NATIVE_SOURCE_ARCHIVE_DIGEST/);
 const commands=JSON.parse(fs.readFileSync(path.join(consumer,'.srcbuild/cpp/shim-header-commands.json')));
 assert.equal(commands[0].argv[0],'cmake');
 assert.ok(commands[0].argv.includes(path.join(selection.llvm.root,'llvm')));
 console.log('PUBLIC_ARCHIVE_REMOVED_CMAKE_ASSERT_REACHED');
});

test('native stage materializes once, rejects bad first input, and reenters without its archive',()=>{
 const pack=archive('stage',{'cjpm.toml':'[package]\nname="archive-input"\n',
  'runtime_shim/build_shim.mjs':"import os from 'node:os'; console.log('NATIVE_STAGE_PRODUCER_REACHED '+JSON.stringify({jobs:process.env.CANGJIE_BUILD_JOBS,cpus:os.availableParallelism()})); process.exit(17);\n"}),target=path.join(root,'stage-source');
 const entry=[process.execPath,path.join(source,'ci/bootstrap/sdk-native-stage.mjs'),'--kind','compiler','--zx',process.execPath,'--jobs','2','--source',target,
  '--sdk',path.join(root,'no-sdk'),'--output',path.join(root,'no-stage'),
  '--platform',({linux:'linux',darwin:'darwin',win32:'windows'}[process.platform])+'_'+(process.arch==='arm64'?'aarch64':'x86_64'),
  '--commit','a'.repeat(40),'--source-archive',pack.file,'--source-archive-sha256',pack.sha256];
 const stageEnv={...process.env};delete stageEnv.GITHUB_ACTIONS;
 const stageRun=(name,argv)=>run(name,argv,root,stageEnv);
 const invalid=[...entry];invalid[invalid.indexOf('--jobs')+1]='0';
 const wrong=[...entry];wrong[wrong.length-1]='0'.repeat(64);
 const rejected=stageRun('stage-bad-digest',wrong);
 assert.equal(rejected.status,1);assert.match(rejected.text,/NATIVE_SOURCE_ARCHIVE_DIGEST/);assert.equal(fs.existsSync(target),false);
 const first=stageRun('stage-first',entry);
 assert.equal(first.status,17);assert.match(first.text,/NATIVE_STAGE_PRODUCER_REACHED/);assert.match(first.text,/\"jobs\":\"2\"/);assert.ok(fs.existsSync(path.join(target,'cjpm.toml')));
 fs.renameSync(pack.file,pack.file+'.moved');
 const badJobs=stageRun('stage-invalid-jobs',invalid);
 assert.equal(badJobs.status,1);assert.match(badJobs.text,/NATIVE_STAGE_JOBS/);
 const again=stageRun('stage-package-removed',entry);
 assert.equal(again.status,17);assert.match(again.text,/NATIVE_STAGE_PRODUCER_REACHED/);assert.doesNotMatch(again.text,/ENOENT/);
 const automatic=[...entry];automatic.splice(automatic.indexOf('--jobs'),2);
 const autoEnv={...stageEnv};delete autoEnv.KKK2_JOBS;delete autoEnv.CANGJIE_BUILD_JOBS;
 const automaticRun=run('stage-actual-cpu-jobs',automatic,root,autoEnv);
 assert.equal(automaticRun.status,17);assert.ok(automaticRun.text.includes('"jobs":"'+os.availableParallelism()+'"'));
 const missing=[...entry];missing[missing.indexOf('--source')+1]=path.join(root,'stage-never-materialized');
 const absent=stageRun('stage-first-missing-package',missing);
 assert.equal(absent.status,1);assert.match(absent.text,/ENOENT/);assert.doesNotMatch(absent.text,/NATIVE_STAGE_PRODUCER_REACHED/);
 const broken=path.join(root,'broken.tar');fs.writeFileSync(broken,'not a tar archive');
 const partial=[...missing];partial[partial.indexOf('--source-archive')+1]=broken;partial[partial.length-1]=digest(broken);
 const failed=stageRun('stage-extraction-failed',partial);
 assert.notEqual(failed.status,0);assert.match(failed.text,/tar/);assert.equal(fs.existsSync(missing[missing.indexOf('--source')+1]),false);
 assert.ok(fs.readdirSync(root).some(name=>name.startsWith('.stage-never-materialized-')),'failed temporary source retained, never published');
 console.log('NATIVE_STAGE_ARCHIVE_REMOVED_PRODUCER_ASSERT_REACHED');
});

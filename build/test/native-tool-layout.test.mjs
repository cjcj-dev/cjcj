import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';
import {getTarget} from '../lib/targets.mjs';
import {nativeToolBuildPayloads,toolPayloads} from '../srcbuild/tool-layout.mjs';
import {sourceToolPayloads} from '../../ci/release/source-tool-payloads.mjs';
import {toolReadiness} from '../../ci/cangjie-test/tool-readiness.mjs';
import {fileDigest} from '../../ci/bootstrap/sdk-flow.mjs';
// Independent literals from fixed ec1 native CMake producers/install rules.
// Text transport fixtures only: no compiler, DLL, Windows execution or SDK pass.
const layouts=[
 ['linux-x64','cjlint','cjlint/build/build/lib/libcjlint.so','cjlint/dist/lib/libcjlint.so','tools/lib/libcjlint.so'],
 ['darwin-x64','cjlint','cjlint/build/build/lib/libcjlint.dylib','cjlint/dist/lib/libcjlint.dylib','tools/lib/libcjlint.dylib'],
 ['windows-x64','cjlint','cjlint/build/build/bin/libcjlint.dll','cjlint/dist/lib/libcjlint.dll','tools/lib/libcjlint.dll'],
 ['windows-x64','cjprof','cjprof/build/build/src/cjprof.dll','cjprof/dist/lib/cjprof.dll','tools/lib/cjprof.dll'],
 ['windows-x64','cjprof','cjprof/bridge/jni/build/cjprof-jni.dll','cjprof/dist/lib/cjprof-jni.dll','tools/lib/cjprof-jni.dll'],
];
for(const [platform,name] of [...new Map(layouts.map(row=>[row[0]+'/'+row[1],[row[0],row[1]]])).values()])test('native raw/install/release paths: '+platform+' '+name,async t=>{
 const root=await fs.mkdtemp(path.join(os.tmpdir(),'native-layout-'));t.after(()=>fs.rm(root,{recursive:true,force:true}));
 const write=async(rel,body='transport marker')=>{await fs.mkdir(path.dirname(root+'/'+rel),{recursive:true});await fs.writeFile(root+'/'+rel,body);};
 const config={repoPath:()=>root,target:getTarget(platform)};
 {
  const rows=layouts.filter(row=>row[0]===platform&&row[1]===name);
  for(const [,,raw,installed]of rows){await write(raw);await write(installed);}
  const sourceConfig=name==='cjlint'?'config/rules.json':'static/index.html';
  const installedConfig=name==='cjlint'?'config/rules.json':'config/static/index.html';
  await write(name+'/'+sourceConfig);await write(name+'/dist/'+installedConfig);
  const raw=await nativeToolBuildPayloads(config,name);
  console.log('NATIVE_RAW_LIBRARY_TARGET_BEGIN '+platform+' '+name);
  for(const [,,build,,to]of rows) {
   assert((await fs.stat(root+'/'+build)).isFile(),'real declared fixture input exists');
   assert.equal(raw.find(row=>row.to===to)?.from,root+'/'+build,'NATIVE_RAW_LIBRARY_PATH '+platform+' '+name);
  }
  const installed=await toolPayloads(config,name);
  for(const [,,,install,to]of rows) {
   assert.equal(installed.find(row=>row.to===to)?.from,root+'/'+install);
   assert(sourceToolPayloads(name,platform).includes(to));
  }
  assert(raw.some(row=>row.to.startsWith('tools/config/')),'configuration independent control');
  if(name==='cjprof')assert(installed.some(row=>row.to.startsWith('.target-tools/tools/config/')),'body-relative configuration control');
  if(platform==='windows-x64'&&name==='cjlint') {
   await fs.rename(root+'/cjlint/dist/lib/libcjlint.dll',root+'/cjlint/dist/lib/cjlint.dll');
   await assert.rejects(toolPayloads(config,name),/libcjlint\.dll/);
   await fs.rename(root+'/cjlint/dist/lib/cjlint.dll',root+'/cjlint/dist/lib/libcjlint.dll');
   assert((await toolPayloads(config,name)).some(row=>row.to==='tools/lib/libcjlint.dll'));
  }
 }
});

test('Windows readiness consumes installed lib-prefixed cjlint DLL and refuses the obsolete name',async t=>{
 const root=await fs.mkdtemp(path.join(os.tmpdir(),'lint-reader-'));t.after(()=>fs.rm(root,{recursive:true,force:true}));
 const write=async(rel,body='reader transport marker')=>{await fs.mkdir(path.dirname(root+'/'+rel),{recursive:true});await fs.writeFile(root+'/'+rel,body);return {path:rel,sha256:await fileDigest(root+'/'+rel)};};
 const stage={platform:'windows_x86_64',fixture:'record/byte reader only; not executable'};
 await write('STAGE-INPUTS.json',JSON.stringify(stage));
 const artifacts={};
 for(const key of ['compiler','stdCore','runtime','nativeAst']){const row=await write('inputs/'+key);artifacts[key]={...row,sdkRelative:row.path};}
 const rel='tools/bin/cjlint.exe',retained='.target-tools/'+rel;
 const artifact=await write(retained),entry=await write(rel);
 entry.recipe=await write(rel+'.entry',['cjcj-sdk-entry-v1','2',retained,'windows','native-target:x64','third_party/llvm/bin','runtime/lib/windows_x86_64_cjnative','lib/windows_x86_64_cjnative','tools/lib'].join('\n')+'\n');
 const payloads={},built={},payloadFiles={};
 for(const relative of ['tools/lib/libcjlint.dll','tools/config/rules.json']){
  const row=await write(relative);built[relative]={source:'/raw/'+relative,sha256:row.sha256};
  payloads[relative]={source:'/install/'+relative,sha256:row.sha256,build:structuredClone(built[relative])};
  payloadFiles[relative]={sha256:row.sha256,producers:['cjlint']};
 }
 const producer={source:{status:'resolved',repository:'fixture://tools',commit:'a'.repeat(40)},artifact,
  build:{rc:0,platform:stage.platform,inputs:{stage,artifacts},payloads:built,
   dependencies:{json:{repo:'fixture://json',commit:'b'.repeat(40),changes_sha256:'c'.repeat(64)}},nativeConfiguration:{native:{values:{CMAKE_BUILD_TYPE:'Release'}}}},
  install:{rc:0,artifact,payloads}};
 const inputs={files:{[rel]:{sha256:artifact.sha256,artifact,entry,producer}},payloadFiles};
 const save=()=>write('TOOLS-INPUTS.json',JSON.stringify(inputs));await save();
 assert.equal((await toolReadiness(root)).cjlint.ready,true);
 const correct='tools/lib/libcjlint.dll',wrong='tools/lib/cjlint.dll';
 await fs.rename(root+'/'+correct,root+'/'+wrong);
 for(const rows of [built,payloads,payloadFiles]){rows[wrong]=rows[correct];delete rows[correct];}
 await save();const rejected=(await toolReadiness(root)).cjlint;
 assert.equal(rejected.ready,false);assert.match(rejected.reason,/required payload absent: tools\/lib\/libcjlint.dll/);
 await fs.rename(root+'/'+wrong,root+'/'+correct);
 for(const rows of [built,payloads,payloadFiles]){rows[correct]=rows[wrong];delete rows[wrong];}
 await save();assert.equal((await toolReadiness(root)).cjlint.ready,true);
});

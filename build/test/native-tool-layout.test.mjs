import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';
import {getTarget} from '../lib/targets.mjs';
import {nativeToolBuildPayloads,toolPayloads,toolBuildProduct} from '../srcbuild/tool-layout.mjs';
import {sourceToolPayloads} from '../../ci/release/source-tool-payloads.mjs';
// Independent literals from fixed ec1 native CMake producers/install rules.
// Text transport fixtures only: no compiler, DLL, Windows execution or SDK pass.
const layouts=[
 ['linux-x64','cjprof','selected-build/cjprof/libcjprof-cangjie.so','cjprof/dist/lib/libcjprof-cangjie.so','tools/lib/libcjprof-cangjie.so'],
 ['linux-x64','cjprof','selected-build/cjprof/libcjprof-jni.so','cjprof/dist/lib/libcjprof-jni.so','tools/lib/libcjprof-jni.so'],
 ['linux-x64','cjprof','selected-build/cjprof/cjprof.jar','cjprof/dist/share/java/cjprof.jar','tools/share/java/cjprof.jar'],
];
test('Cangjie lint consumes the executable recorded by its normal CJPM producer',async t=>{
 const root=await fs.mkdtemp(path.join(os.tmpdir(),'lint-product-'));t.after(()=>fs.rm(root,{recursive:true,force:true}));
 const config={repoPath:()=>root,buildRoot:root,target:getTarget('linux-x64')};
 const build=root+'/cjlint';await fs.mkdir(build);
 for(const name of ['main','cjlint']) {
  const executable=build+'/target/release/bin/'+name;
  await fs.mkdir(path.dirname(executable),{recursive:true});await fs.writeFile(executable,'normal producer output fixture');
  await fs.writeFile(build+'/product.json',JSON.stringify({executable}));
  assert.equal(toolBuildProduct(config,'cjlint'),executable);
 }
 await fs.rename(build+'/product.json',build+'/product-held.json');
 assert.throws(()=>toolBuildProduct(config,'cjlint'),/ENOENT/,'no guessed filename without producer record');
 await fs.rename(build+'/product-held.json',build+'/product.json');
 assert.equal(toolBuildProduct(config,'cjlint'),build+'/target/release/bin/cjlint');
});
for(const [platform,name] of [...new Map(layouts.map(row=>[row[0]+'/'+row[1],[row[0],row[1]]])).values()])test('native raw/install/release paths: '+platform+' '+name,async t=>{
 const root=await fs.mkdtemp(path.join(os.tmpdir(),'native-layout-'));t.after(()=>fs.rm(root,{recursive:true,force:true}));
 const write=async(rel,body='transport marker')=>{await fs.mkdir(path.dirname(root+'/'+rel),{recursive:true});await fs.writeFile(root+'/'+rel,body);};
 const config={repoPath:()=>root,buildRoot:root+'/selected-build',target:getTarget(platform)};
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

 }
});

test('Cangjie lint transports an isolated analysis application without legacy libraries',async t=>{
 const root=await fs.mkdtemp(path.join(os.tmpdir(),'lint-layout-'));t.after(()=>fs.rm(root,{recursive:true,force:true}));
 const prefix=root+'/installed',config={repoPath:()=>root,buildRoot:root+'/build',target:getTarget('linux-x64')};
 const write=async(rel,body='transport fixture')=>{await fs.mkdir(path.dirname(prefix+'/'+rel),{recursive:true});await fs.writeFile(prefix+'/'+rel,body);};
 for(const rel of ['config/cjlint_rule_list.json','modules/linux_x86_64_cjnative/std.core.cjo','lib/libcangjie-runtime.so','lib/libLLVM-15.so'])await write(rel);
 await fs.mkdir(prefix+'/runtime/lib/linux_x86_64_cjnative',{recursive:true});
 await fs.symlink('../../../lib/libcangjie-runtime.so',prefix+'/runtime/lib/linux_x86_64_cjnative/libcangjie-runtime.so');
 const read=()=>toolPayloads(config,'cjlint',prefix);
 const rows=await read();assert.equal(rows.length,5);
 assert(rows.every(row=>row.to.startsWith('.target-tools/tools/cjlint/')));
 assert.deepEqual(sourceToolPayloads('cjlint'),['.target-tools/tools/cjlint']);
 await write('lib/libcjlint.so');await assert.rejects(read,/CJLINT_RETIRED_LIBRARY/);
 await fs.rm(prefix+'/lib/libcjlint.so');assert.deepEqual(await read(),rows);
 await fs.rename(prefix+'/modules',prefix+'/modules-held');await assert.rejects(read,/ENOENT/);
 await fs.rename(prefix+'/modules-held',prefix+'/modules');assert.deepEqual(await read(),rows);
});

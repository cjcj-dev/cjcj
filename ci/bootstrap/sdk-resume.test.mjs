import test from'node:test';import assert from'node:assert/strict';import fs from'node:fs/promises';import path from'node:path';import {spawnSync}from'node:child_process';import {buildFlow,fileDigest}from'./sdk-flow.mjs';
const parent=process.env.RELEASE_EVIDENCE_TEST_ROOT;if(!parent)throw new Error('RELEASE_EVIDENCE_TEST_ROOT required');await fs.mkdir(parent,{recursive:true});
test('explicit resume consumes the existing native dependency without rebuilding or replacing its bytes',async()=>{
 const root=await fs.mkdtemp(path.join(parent,'native-resume-')),input=path.join(root,'source.c'),binary=path.join(root,'native'),work=path.join(root,'work'),install=path.join(root,'install');
 await fs.writeFile(input,'#include <stdio.h>\nint main(void){puts("42");return 0;}\n');const cc=spawnSync('cc',[input,'-o',binary],{encoding:'utf8'});assert.equal(cc.status,0,cc.stderr);
 const config={work,install,repos:{},finalStage:'b',stages:[{id:'a',copies:[{from:binary,to:'bin/result'}]},{id:'b',depends:['a'],output:install,copies:[{from:'${output.a}',to:''}]}],test:{commands:[{argv:[process.execPath,'-e',`const r=require('node:child_process').spawnSync(process.argv[1],[],{encoding:'utf8'});console.log('RESUMED_NATIVE_TARGET_ASSERTION_REACHED',r.status,r.stdout.trim());require('node:assert/strict').equal(r.status,0);require('node:assert/strict').equal(r.stdout.trim(),'42');`,'${install}/bin/result']}]}};
  const initial=await buildFlow(config,{through:'a'}),dependency=initial.stages[0].output,before=await fileDigest(path.join(dependency,'bin/result'));
  const changed=structuredClone(config);
  changed.stages[0].commands=[{argv:[process.execPath,'-e','process.exit(99)']}];
  await assert.rejects(buildFlow(changed,{from:'b',through:'b',packageOutput:false}),/WORK_INPUT_MISMATCH/);
  assert.equal(await fileDigest(path.join(dependency,'bin/result')),before);
  const resumed=await buildFlow(config,{from:'b',through:'b',packageOutput:false});
  assert.equal(resumed.status,'COMPLETE');assert.equal(resumed.stages[0].reuse.reason,'explicit --from dependency');assert.equal(resumed.commands.length,1);
  assert.equal(await fileDigest(path.join(install,'bin/result')),before);assert.equal(await fileDigest(path.join(dependency,'bin/result')),before);
});

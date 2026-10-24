#!/usr/bin/env zx
// Public SDK CLI replaces the retired numbered shell steps. These five
// transport fixtures do not qualify LLVM, a native tool or a complete SDK.
import crypto from 'node:crypto';
import fs from 'node:fs';
import path from 'node:path';
import assert from 'node:assert/strict';
import {spawnSync} from 'node:child_process';
import {fileURLToPath} from 'node:url';
import {cleanupOnSignals} from './entry-common.mjs';
const self=fileURLToPath(import.meta.url),repo=path.resolve(path.dirname(self),'..');
const digest=bytes=>crypto.createHash('sha256').update(bytes).digest('hex');
function observe(root,manifest) {
  const expected=JSON.parse(fs.readFileSync(manifest,'utf8'));
  const observed=Object.fromEntries(Object.keys(expected).map(name=>{
    const file=path.join(root,'fixed-llc',name);
    return [name,fs.existsSync(file)?digest(fs.readFileSync(file)):null];
  }));
  console.log('ACQUIRE_TARGET_ASSERT_REACHED '+JSON.stringify(observed));
  assert.deepEqual(observed,expected,'srcbuild must publish the five verified fixed-tool payloads');
}
export async function acquireControl(work) {
  fs.mkdirSync(work); // NEW_WORK is exclusive; never overwrite old evidence.
  const records=[];
  function run(argv,label) {
    const result=spawnSync(argv[0],argv.slice(1),{cwd:repo,env:process.env,encoding:'utf8'});
    const output=(result.stdout||'')+(result.stderr||'');
    fs.writeFileSync(path.join(work,label+'.log'),output);
    records.push({label,argv,cwd:repo,rc:result.status,signal:result.signal,error:result.error?.message??null});
    fs.writeFileSync(path.join(work,'commands.json'),JSON.stringify(records,null,2)+'\n');
    return {rc:result.status,output};
  }
  const driver=path.join(repo,'ci/bootstrap/sdk-flow.mjs'),original=fs.readFileSync(driver);
  assert.equal(run(['git','diff','--exit-code','--','ci/bootstrap/sdk-flow.mjs'],'before').rc,0);
  fs.writeFileSync(path.join(work,'sdk-flow.saved'),original);
  fs.writeFileSync(path.join(work,'source-identities.json'),JSON.stringify(Object.fromEntries(
    ['build/cli.mjs','ci/bootstrap/sdk-flow.mjs','ci/bootstrap/sdk-source.mjs'].map(file=>
      [file,digest(fs.readFileSync(path.join(repo,file)))])),null,2)+'\n');
  const depot=path.join(work,'depot'),expected={};
  fs.mkdirSync(path.join(depot,'fixed-llc'),{recursive:true});
  for(const name of ['llc.gz','opt.gz','ld.lld.gz','cjselfhost_llvmshim.o','llvm-tools.manifest']) {
    const bytes=Buffer.from(`G1 transport fixture: ${name}\n`);
    fs.writeFileSync(path.join(depot,'fixed-llc',name),bytes);expected[name]=digest(bytes);
  }
  const manifest=path.join(work,'expected.json'),archive=path.join(work,'input.tar');
  fs.writeFileSync(manifest,JSON.stringify(expected,null,2)+'\n');
  assert.equal(run(['tar','-cf',archive,'-C',depot,'.'],'archive').rc,0);
  const sha256=digest(fs.readFileSync(archive));
  const cleanup=()=>{fs.writeFileSync(driver,original);assert.deepEqual(fs.readFileSync(driver),original);};
  const removeSignalHandlers=cleanupOnSignals(cleanup);
  try {
    for(const [arm,expectedRc] of [['green',0],['cut',1],['restored',0]]) {
      const root=path.join(work,arm),source=path.join(root,'source'),install=path.join(root,'installed');
      const call='const owners = await copyOutputs(pending, recipe.copies || []);';
      assert.equal(original.toString().split(call).length,2);
      fs.writeFileSync(driver,arm==='cut'?original.toString().replace(call,
        'const owners = {}; // finite acquisition control: disconnect actual installation copy'):original);
      if(arm==='cut')assert.equal(run(['diff','-u',path.join(work,'sdk-flow.saved'),driver],'acquire-cut.diff').rc,1);
      const config={work:root,install,repos:{tuple:{root:source,commit:'b'.repeat(40),tree:'c'.repeat(40),
        archive:{file:archive,sha256}}},finalStage:'acquired',stages:[{id:'acquired',output:install,
          copies:[{from:'${repo.tuple}/fixed-llc',to:'fixed-llc'}]}]};
      // Archive identity is its selected digest. Commit/tree here are finite
      // declarations, never claimed as a real LLVM revision.
      const configFile=path.join(work,arm+'.json');fs.writeFileSync(configFile,JSON.stringify(config));
      const result=run([process.execPath,path.join(repo,'build/cli.mjs'),'sdk','--config',configFile,'--no-package'],arm+'-driver');
      assert.equal(result.rc,0,result.output);
      const state=JSON.parse(fs.readFileSync(path.join(root,'build-result.json'),'utf8'));
      assert.equal(state.status,'COMPLETE');assert.equal(state.completedThrough,'acquired');
      // Same traversal still verifies/extracts all five source payloads in cut.
      const control=run([process.execPath,self,'observe',source,manifest],arm+'-source-control');
      assert.equal(control.rc,0,control.output);
      const target=run([process.execPath,self,'observe',install,manifest],arm+'-target');
      assert.match(target.output,/ACQUIRE_TARGET_ASSERT_REACHED/);
      assert.equal(target.rc,expectedRc,target.output);
      if(expectedRc)assert.match(target.output,/ERR_ASSERTION/);
    }
    console.log('ACQUIRE_CONTROL target=0/1/0 independent_archive_source=0/0/0; fixture only');
  } finally {
    try{cleanup();}finally{removeSignalHandlers();}
    assert.equal(run(['git','diff','--exit-code','--','ci/bootstrap/sdk-flow.mjs'],'restored.diff').rc,0);
  }
}
const entryIndex=process.argv.findIndex((arg,index)=>index>0&&path.resolve(arg)===self);
if(entryIndex>0) {
  const [mode,...args]=process.argv.slice(entryIndex+1);
  if(mode==='observe')observe(args[0],args[1]);
  else {assert(mode&&args.length===0,'usage: test-srcbuild-acquire-wiring.mjs NEW_WORK');await acquireControl(path.resolve(mode));}
}

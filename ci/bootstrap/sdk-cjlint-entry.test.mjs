import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs/promises';
import path from 'node:path';
import {spawnSync} from 'node:child_process';
import {toolPayloads} from '../../build/srcbuild/tool-layout.mjs';
import {installationRecipe} from './sdk-targets.mjs';
import {installEntries} from './sdk-install-entries.mjs';
import {copyOutputs,fileDigest} from './sdk-flow.mjs';

const input=process.env.CJCJ_CJLINT_TEST_SDK;
test('public cjlint selects its private application root without a modules override',
 {skip:!input || process.platform!=='linux' || process.arch!=='x64'},async()=>{
  const parent=process.env.RELEASE_EVIDENCE_TEST_ROOT;
  assert(parent,'RELEASE_EVIDENCE_TEST_ROOT required');
  await fs.mkdir(parent,{recursive:true});
  const work=await fs.mkdtemp(path.join(parent,'cjlint-entry-'));
  // The cut/restoration driver may reuse its own unchanged installed payload.
  const root=process.env.CJCJ_CJLINT_TEST_PREFIX??path.join(work,'SDK with spaces');
  const producer=path.join(input,'.target-tools/tools/cjlint');
  const raw=path.join(producer,'bin/cjlint'),publicFile=path.join(root,'tools/bin/cjlint');
  const retained=path.join(root,'.target-tools/tools/cjlint/bin/cjlint');
  const rows=[{producer:'cjlint',name:'cjlint',from:raw,to:'tools/bin/cjlint'}];
  const payloads=await toolPayloads({toolsProducerSources:{cjlint:producer}},'cjlint',producer);
  const recipe=installationRecipe({platform:'linux_x86_64'},{tools:{rows,payloads}});
  const original=await fileDigest(raw);
  if(await fs.stat(retained).catch(()=>null)) {
   assert.equal(await fileDigest(retained),original,'reuse only the unchanged tool');
   await fs.rename(retained,publicFile);
  }else await copyOutputs(root,recipe.copies);
  const records=[];
  await installEntries({root,build:path.join(work,'entry-build'),platform:'linux_x86_64',groups:recipe.entries,records});
  await fs.writeFile(path.join(work,'install-commands.json'),JSON.stringify(records,null,2));
  assert.equal(await fileDigest(retained),original);
  assert.equal(await fs.stat(path.join(root,'tools/modules')).catch(()=>null),null,'no public modules workaround');
  const env={...process.env,CANGJIE_HOME:path.join(work,'wrong home'),LD_LIBRARY_PATH:'/invalid',LD_DEBUG:'libs'};
  for(const key of ['LD_DEBUG_OUTPUT','LD_PRELOAD','LD_AUDIT'])delete env[key];
  const results=[];
  async function check(name,args,expected,verify=()=>{}) {
   const argv=[publicFile,...args],r=spawnSync(argv[0],argv.slice(1),{cwd:work,env,encoding:'utf8',timeout:60000,maxBuffer:4*1024*1024});
   await fs.writeFile(path.join(work,name+'.stdout'),r.stdout??'');
   await fs.writeFile(path.join(work,name+'.stderr'),r.stderr??'');
   const failures=[];
   try{assert.equal(r.status,expected,'PUBLIC_CJLINT_'+name+'\n'+r.stderr);assert.equal(r.signal,null);await verify(r);}
   catch(error){failures.push(error.message);}
   results.push({name,argv,cwd:work,rc:r.status,signal:r.signal,error:r.error?.message??null,failures});
  }
  for(const [name,value,types] of [
   ['default-modules','var value: Int64 = 42\n value',['G_VAR_01_prefer_immutable_var']],
   ['clean-control','let value: Int64 = 42\n value',[]],
  ]) {
   const dir=path.join(work,name),report=path.join(dir,'report.json');
   await fs.mkdir(path.join(dir,'src'),{recursive:true});
   await fs.mkdir(path.join(dir,'config'));
   await fs.writeFile(path.join(dir,'src/main.cj'),'func api(): Int64 { '+value+' }\n');
   await fs.writeFile(path.join(dir,'config/cjlint_rule_list.json'),JSON.stringify({RuleList:['G.VAR.01']}));
   await check(name,['-f',path.join(dir,'src'),'-c',dir,'-o',report,'-r','json'],0,async r=>{
    assert.deepEqual(JSON.parse(await fs.readFile(report,'utf8')).map(x=>x.defectType),types,'REAL_FRONTEND_DIAGNOSTICS');
    assert(r.stderr.includes('calling init: '+path.join(root,'.target-tools/tools/cjlint/lib/libcangjie-runtime.so')),'PRIVATE_EXECUTION_RUNTIME');
   });
  }
  await check('help-control',['-h'],0,r=>assert.match(r.stdout,/cjlint/));
  await check('error-return',['--unknown','-h'],1,r=>assert.match(r.stderr,/unknown|Unknown|invalid|Invalid/));
  await fs.writeFile(path.join(work,'results.json'),JSON.stringify({input,root,rawSha256:original,
   launcherSha256:await fileDigest(publicFile),results},null,2));
  console.log('CJLINT_PUBLIC_APPLICATION_ROOT_TARGET_REACHED',JSON.stringify(results));
  assert.deepEqual(results.flatMap(row=>row.failures.map(error=>({name:row.name,error}))),[]);
 });

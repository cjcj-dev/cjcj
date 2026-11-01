import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs/promises';
import path from 'node:path';
import {spawnSync} from 'node:child_process';
import {installEntries} from './sdk-install-entries.mjs';
import {installationRecipe} from './sdk-targets.mjs';
import {fileDigest} from './sdk-flow.mjs';

// Integration input: an already installed, source-built cjfmt. Never rebuild it.
const input=process.env.CJCJ_CJFMT_TEST_SDK;
test('installed cjfmt keeps configuration home and isolates execution libraries',
 {skip:!input || process.platform!=='linux' || process.arch!=='x64'},async()=>{
  const parent=process.env.RELEASE_EVIDENCE_TEST_ROOT;
  assert(parent,'RELEASE_EVIDENCE_TEST_ROOT required');
  await fs.mkdir(parent,{recursive:true});
  const work=await fs.mkdtemp(path.join(parent,'cjfmt-entry-')),root=path.join(work,'SDK with spaces');
  const home=path.join(work,'caller home'),runtime='runtime/lib/linux_x86_64_cjnative';
  await fs.mkdir(path.join(root,'tools/bin'),{recursive:true});
  await fs.mkdir(path.join(root,'tools/config'),{recursive:true});
  await fs.mkdir(path.join(home,'tools/config'),{recursive:true});
  await fs.mkdir(path.join(home,runtime),{recursive:true});
  const raw=path.join(input,'.target-tools/tools/bin/cjfmt');
  await fs.copyFile(raw,path.join(root,'tools/bin/cjfmt'));
  await fs.cp(path.join(input,runtime),path.join(root,runtime),{recursive:true});
  const config=await fs.readFile(path.join(input,'tools/config/cangjie-format.toml'),'utf8');
  assert.match(config,/indentWidth = 4/);
  await fs.writeFile(path.join(root,'tools/config/cangjie-format.toml'),config);
  await fs.writeFile(path.join(home,'tools/config/cangjie-format.toml'),config.replace('indentWidth = 4','indentWidth = 2'));
  await fs.writeFile(path.join(work,'explicit.toml'),config.replace('indentWidth = 4','indentWidth = 3'));
  await fs.writeFile(path.join(work,'basic.cj'),'main(){println(7)}\n');
  // If the entry admits caller loader paths, these cannot be loaded as ELF.
  for(const name of ['libcangjie-runtime.so','libboundscheck.so','libcangjie-trace.so'])
   await fs.writeFile(path.join(home,runtime,name),'caller library must not be loaded\n');
  // An ordinary target entry remains bound to the installed resource home.
  await fs.copyFile('/usr/bin/env',path.join(root,'tools/bin/environment-control'));
  const rows=['cjfmt','environment-control'].map(name=>({name,producer:name}));
  const recipe=installationRecipe({platform:'linux_x86_64'},{tools:{rows,payloads:[]}}),records=[];
  await installEntries({root,build:path.join(work,'entry-build'),platform:'linux_x86_64',groups:recipe.entries,records});
  await fs.writeFile(path.join(work,'install-commands.json'),JSON.stringify(records,null,2));
  assert.equal(await fileDigest(raw),await fileDigest(path.join(root,'.target-tools/tools/bin/cjfmt')));
  const env={...process.env,CANGJIE_HOME:home,LD_LIBRARY_PATH:path.join(home,runtime),
   LD_PRELOAD:path.join(home,runtime,'libcangjie-runtime.so'),LD_AUDIT:path.join(home,runtime,'libboundscheck.so'),LD_DEBUG:'libs'};
  const results=[];
  for(const [name,args,width,homeValue] of [
   ['missing',['-c',path.join(work,'absent.toml')],2,home],
   ['unreadable',['-c',home],2,home],
   ['explicit',['-c',path.join(work,'explicit.toml')],3,home],
   ['default',[],4,undefined],
  ]) {
   const output=path.join(work,name+'.cj'),childEnv={...env};
   if(homeValue===undefined)delete childEnv.CANGJIE_HOME;
   const argv=[path.join(root,'tools/bin/cjfmt'),'-f',path.join(work,'basic.cj'),'-o',output,...args];
   const r=spawnSync(argv[0],argv.slice(1),{env:childEnv,encoding:'utf8',timeout:60000});
   await fs.writeFile(path.join(work,name+'.stdout'),r.stdout??'');
   await fs.writeFile(path.join(work,name+'.stderr'),r.stderr??'');
   const actual=await fs.readFile(output,'utf8').catch(()=>null),failures=[];
   try {
    assert.equal(r.status,0,r.stderr);assert.equal(r.signal,null);
    assert.equal(actual,`main() {\n${' '.repeat(width)}println(7)\n}\n`,'CONFIG_HOME_'+name);
    if(['missing','unreadable'].includes(name))assert.match(r.stdout,/Warning: cannot read format configuration:/);
    for(const lib of ['libcangjie-runtime.so','libboundscheck.so'])
     assert(r.stderr.includes('calling init: '+path.join(root,runtime,lib)),'SELECTED_RUNTIME_'+lib);
    assert(!r.stderr.includes(home),'CALLER_LOADER_ISOLATION');
   }catch(error){failures.push(error.message);}
   results.push({name,argv,rc:r.status,signal:r.signal,error:r.error?.message??null,actual,failures});
  }
  const controlEnv={...env};delete controlEnv.LD_DEBUG;
  const control=spawnSync(path.join(root,'tools/bin/environment-control'),[],{env:controlEnv,encoding:'utf8'});
  const fields=Object.fromEntries(control.stdout.trim().split('\n').map(line=>{const n=line.indexOf('=');return [line.slice(0,n),line.slice(n+1)];}));
  const failures=[];
  try{assert.equal(control.status,0,control.stderr);assert.equal(fields.CANGJIE_HOME,root);
   assert.equal(fields.LD_LIBRARY_PATH,recipe.entries[0].libraries.map(rel=>path.join(root,rel)).join(':'));
   assert.equal(fields.LD_PRELOAD,undefined);assert.equal(fields.LD_AUDIT,undefined);
  }catch(error){failures.push(error.message);}
  results.push({name:'ordinary-entry-control',rc:control.status,signal:control.signal,stdout:control.stdout,stderr:control.stderr,failures});
  await fs.writeFile(path.join(work,'results.json'),JSON.stringify({input,root,rawSha256:await fileDigest(raw),launcherSha256:await fileDigest(path.join(root,'tools/bin/cjfmt')),results},null,2));
  console.log('CJFMT_PUBLIC_ENTRY_TARGET_REACHED',JSON.stringify(results));
  assert.deepEqual(results.flatMap(row=>row.failures.map(error=>({name:row.name,error}))),[]);
 });

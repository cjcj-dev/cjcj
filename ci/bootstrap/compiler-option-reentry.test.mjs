#!/usr/bin/env zx
// Script-entry regression only: the compiler command is a bounded observer,
// never a substitute compiler product. No CJ/LLVM build or SDK installation.
import test from 'node:test';import assert from 'node:assert/strict';
import fs from 'node:fs/promises';import path from 'node:path';
import {spawnSync} from 'node:child_process';import {createHash} from 'node:crypto';
import {pathToFileURL} from 'node:url';
const code=process.env.OPTION_STAGE_SOURCE||path.resolve(import.meta.dirname,'../..');
const output=process.env.RELEASE_EVIDENCE_TEST_ROOT;
if(!output||!path.isAbsolute(output))throw Error('explicit evidence root required');
const {configureOptionVisibility}=await import(pathToFileURL(path.join(code,'ci/bootstrap/compiler-option-visibility.mjs')));
const manifest='[package]\nname = "option"\ncompile-option = "--cfg CANGJIE_VISIBLE_OPTIONS_ONLY=true"\n';
const records=[];
async function write(p,s){await fs.mkdir(path.dirname(p),{recursive:true});await fs.writeFile(p,s);}
async function fixture(name){const root=path.join(output,name);await fs.mkdir(root,{recursive:true});return root;}

const h1='83901791548856f0458f3e3e38c4c1ab7ac496c5',previous='8e9c40c38408cfe5d6b79aaf5f7ae3570b4b36ef';
const legacyFiles=['Option.cj','OptionAction.cj','OptionTable.cj'];
function blob(rev,file){
 const r=spawnSync('git',['-C',code,'show',rev+':packages/option/'+file]);
 assert.equal(r.status,0,r.stderr.toString());return r.stdout;
}
async function legacySource(source,rev){
 for(const file of ['cjpm.toml',...legacyFiles.map(name=>'src/'+name)])
  await write(path.join(source,'packages/option',file),blob(rev,file));
}

test('public H1 stage selects actual bytes on first build and stale-false default reentry',async()=>{
 const root=await fixture('stage'),source=root+'/source',sdk=root+'/sdk',host=root+'/host';
 const option=source+'/packages/option/cjpm.toml';
 await write(source+'/cjpm.toml','[workspace]\ncompile-option = "-O1"\n');
 const pkg=source+'/packages/cjc/cjpm.toml';
 const lib='third_party/llvm/lib/libLLVM-15.so';
 const packageManifest='[package]\nlink-option = "${CANGJIE_HOME}/'+lib+'"\n';
 await write(pkg,packageManifest);
 await write(sdk+'/'+lib,'N library path; never loaded by the observer');
 await write(source+'/runtime_shim/keep','fixture');
 await write(source+'/target/release/cache-control','keep existing cache');
 const object='third_party/llvm/fixed-llc/cjselfhost_llvmshim.o',bytes=Buffer.from('fixture shim');
 await write(sdk+'/'+object,bytes);
 const sha='a'.repeat(40);
 await write(sdk+'/BUILD-INPUTS.json',JSON.stringify({commits:{shim:sha,compiler:sha,llvm:sha},nativeShim:{source:{commit:sha},compiler:{commit:sha},llvm:{commit:sha},object:{path:object,bytes:bytes.length,sha256:createHash('sha256').update(bytes).digest('hex')}}}));
 const nm=root+'/tools/nm',cc=root+'/tools/observe-cc.mjs';
 await write(nm,`#!${process.execPath}\nconsole.log('0000 T CJ_MRT_CjRuntimeInitWithConfigV1');\n`);await fs.chmod(nm,0o755);
 await write(cc,`#!${process.execPath}\nimport fs from 'node:fs';fs.writeFileSync(process.env.OPTION_OBSERVED,fs.readFileSync(${JSON.stringify(option)}));process.exit(73);\n`);await fs.chmod(cc,0o755);
 for(const [name,before,selected,expected] of [['first-true','true','true','true'],['stale-false-default','false',undefined,'true'],['explicit-false','true','false','false'],
  ['pinned-h1',null,'true',null]]) {
  if(name==='pinned-h1')await legacySource(source,h1);
  else await write(option,manifest.replace('=true','='+before));
  const original=await fs.readFile(option,'utf8');
  const observed=root+'/'+name+'.observed',argv=[process.execPath,code+'/ci/bootstrap/sdk-native-stage.mjs','--kind','h1','--source',source,'--sdk',sdk,'--host',host,'--output',root+'/'+name,'--platform','linux_x86_64','--jobs','1','--heap','1GB','--cc',cc,...(selected===undefined?[]:['--visible-options-only',selected])];
  const r=spawnSync(argv[0],argv.slice(1),{cwd:root,env:{...process.env,PATH:root+'/tools:'+process.env.PATH,OPTION_OBSERVED:observed},encoding:'utf8',maxBuffer:4e6});
  records.push({name,argv,rc:r.status,signal:r.signal,stdout:r.stdout,stderr:r.stderr});await write(root+'/commands.json',JSON.stringify(records,null,2));
  assert.equal(r.status,73,r.stderr);assert.equal(r.signal,null);
  const actual=await fs.readFile(observed,'utf8');
  assert.equal(await fs.readFile(option,'utf8'),original,'exception restores exact incoming bytes');
  assert.equal(await fs.readFile(pkg,'utf8'),packageManifest);
  await assert.rejects(fs.lstat(source+'/runtime_shim/h1-libLLVM-15.so'),{code:'ENOENT'});
  assert.equal(await fs.readFile(source+'/target/release/cache-control','utf8'),'keep existing cache');
  console.log('STAGE_OPTION_BYTES '+name+' '+JSON.stringify(actual));
  if(name==='pinned-h1')assert.equal(actual,original,'legacy H1 must reach the compiler without changing its manifest');
  else assert.match(actual,new RegExp('CANGJIE_VISIBLE_OPTIONS_ONLY='+expected+'"'),'actual compiler-command input must match requested/default policy');
 }
});

test('unknown or ambiguous configuration never falls through to default true',async()=>{
 const root=await fixture('invalid'),file=root+'/packages/option/cjpm.toml';
 for(const text of [manifest.replace('=true','=off'),manifest.replace('[package]','[target]'),
  manifest+'# --cfg CANGJIE_VISIBLE_OPTIONS_ONLY=false\n',
  manifest.replace('=true','=true --cfg CANGJIE_VISIBLE_OPTIONS_ONLY=false')]) {
  await write(file,text);
  await assert.rejects(configureOptionVisibility(root,true),/CONFIGURATION_UNSUPPORTED/);
  assert.equal(await fs.readFile(file,'utf8'),text);
 }
});

for(const rev of [previous,h1])test('legacy compatibility requires the entire true implementation '+rev,async()=>{
 const root=await fixture('legacy-'+rev),src=path.join(root,'packages/option/src');
 const unsupported={message:'COMPILER_OPTION_CONFIGURATION_UNSUPPORTED'};
 await legacySource(root,rev);
 await (await configureOptionVisibility(root,true))();
 await assert.rejects(configureOptionVisibility(root,false),unsupported);
 for(const name of legacyFiles){
  const file=path.join(src,name),original=await fs.readFile(file);
  await fs.appendFile(file,' ');
  await assert.rejects(configureOptionVisibility(root,true),unsupported);
  await fs.writeFile(file,original);
 }
 const config=path.join(src,'BuildConfiguration.cj');
 await write(config,'');
 await assert.rejects(configureOptionVisibility(root,true),unsupported);
 await fs.unlink(config);
 const option=path.join(src,'Option.cj');
 const original=blob(rev,'src/Option.cj').toString();
 await fs.writeFile(option,original.replace('CANGJIE_VISIBLE_OPTIONS_ONLY: Bool = true','CANGJIE_VISIBLE_OPTIONS_ONLY: Bool = false'));
 await assert.rejects(configureOptionVisibility(root,true),unsupported);
 await fs.writeFile(option,blob(rev===h1?previous:h1,'src/Option.cj'));
 await assert.rejects(configureOptionVisibility(root,true),unsupported);
 await fs.writeFile(option,blob(rev,'src/Option.cj'));
 await fs.unlink(path.join(src,'OptionTable.cj'));
 await assert.rejects(configureOptionVisibility(root,true),unsupported);
});

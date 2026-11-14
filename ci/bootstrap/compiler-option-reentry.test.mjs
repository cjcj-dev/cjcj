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

test('public H1 stage selects actual bytes on first build and stale-false default reentry',async()=>{
 const root=await fixture('stage'),source=root+'/source',sdk=root+'/sdk',host=root+'/host';
 const option=source+'/packages/option/cjpm.toml';
 await write(source+'/cjpm.toml','[workspace]\ncompile-option = "-O1"\n');
 await write(source+'/packages/cjc/cjpm.toml','[package]\nlink-option = ""\n');
 await write(source+'/runtime_shim/keep','fixture');
 await write(source+'/target/release/cache-control','keep existing cache');
 const object='third_party/llvm/fixed-llc/cjselfhost_llvmshim.o',bytes=Buffer.from('fixture shim');
 await write(sdk+'/'+object,bytes);
 const sha='a'.repeat(40);
 await write(sdk+'/BUILD-INPUTS.json',JSON.stringify({commits:{shim:sha,compiler:sha,llvm:sha},nativeShim:{source:{commit:sha},compiler:{commit:sha},llvm:{commit:sha},object:{path:object,bytes:bytes.length,sha256:createHash('sha256').update(bytes).digest('hex')}}}));
 const nm=root+'/tools/nm',cc=root+'/tools/observe-cc.mjs';
 await write(nm,`#!${process.execPath}\nconsole.log('0000 T CJ_MRT_CjRuntimeInitWithConfigV1');\n`);await fs.chmod(nm,0o755);
 await write(cc,`#!${process.execPath}\nimport fs from 'node:fs';fs.writeFileSync(process.env.OPTION_OBSERVED,fs.readFileSync(${JSON.stringify(option)}));process.exit(73);\n`);await fs.chmod(cc,0o755);
 for(const [name,before,selected,expected] of [['first-true','true','true','true'],['stale-false-default','false',undefined,'true'],['explicit-false','true','false','false']]) {
  const original=manifest.replace('=true','='+before);
  await write(option,original);
  const observed=root+'/'+name+'.observed',argv=[process.execPath,code+'/ci/bootstrap/sdk-native-stage.mjs','--kind','h1','--source',source,'--sdk',sdk,'--host',host,'--output',root+'/'+name,'--platform','linux_x86_64','--jobs','1','--heap','1GB','--cc',cc,...(selected===undefined?[]:['--visible-options-only',selected])];
  const r=spawnSync(argv[0],argv.slice(1),{cwd:root,env:{...process.env,PATH:root+'/tools:'+process.env.PATH,OPTION_OBSERVED:observed},encoding:'utf8',maxBuffer:4e6});
  records.push({name,argv,rc:r.status,signal:r.signal,stdout:r.stdout,stderr:r.stderr});await write(root+'/commands.json',JSON.stringify(records,null,2));
  assert.equal(r.status,73,r.stderr);assert.equal(r.signal,null);
  const actual=await fs.readFile(observed,'utf8');
  assert.equal(await fs.readFile(option,'utf8'),original,'exception restores exact incoming bytes');
  assert.equal(await fs.readFile(source+'/target/release/cache-control','utf8'),'keep existing cache');
  console.log('STAGE_OPTION_BYTES '+name+' '+JSON.stringify(actual));
  assert.match(actual,new RegExp('CANGJIE_VISIBLE_OPTIONS_ONLY='+expected+'"'),'actual compiler-command input must match requested/default policy');
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

test('legacy compatibility requires actual known true implementations',async()=>{
 const root=await fixture('legacy');await write(root+'/packages/option/cjpm.toml','[package]\ncompile-option = ""\n');
 for(const file of ['Option.cj','OptionAction.cj','OptionTable.cj']) {
  const r=spawnSync('git',['-C',code,'show','8e9c40c38408cfe5d6b79aaf5f7ae3570b4b36ef:packages/option/src/'+file],{encoding:'utf8'});assert.equal(r.status,0,r.stderr);
  await write(root+'/packages/option/src/'+file,r.stdout);
 }
 await (await configureOptionVisibility(root,true))();
 await assert.rejects(configureOptionVisibility(root,false),/CONFIGURATION_UNSUPPORTED/);
 const file=root+'/packages/option/src/Option.cj';const original=await fs.readFile(file,'utf8');
 await fs.writeFile(file,original.replace('CANGJIE_VISIBLE_OPTIONS_ONLY: Bool = true','CANGJIE_VISIBLE_OPTIONS_ONLY: Bool = false'));
 await assert.rejects(configureOptionVisibility(root,true),/CONFIGURATION_UNSUPPORTED/);
 await fs.writeFile(file,original);await fs.rm(root+'/packages/option/src/OptionTable.cj');
 await assert.rejects(configureOptionVisibility(root,true),/CONFIGURATION_UNSUPPORTED/);
});

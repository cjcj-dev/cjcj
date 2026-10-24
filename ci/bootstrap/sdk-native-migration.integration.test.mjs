#!/usr/bin/env zx
// Real received H/schema inputs exercise installation and compiler/cjpm
// interfaces. H remains the reference compiler; this is not SDK selfhosting.
import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs/promises';
import path from 'node:path';
import {spawnSync} from 'node:child_process';
import {copyOutputs, fileDigest, buildFlow, archiveInstall} from './sdk-flow.mjs';
import {createBootstrapTargets, FIXED_INPUTS} from './sdk-targets.mjs';
import {readHostToolchainPin} from '../host-toolchain-pin.mjs';
import {verifyCompiler} from './compiler_identity.mjs';
import {helloInstall} from './sdk-hello.mjs';
const request=JSON.parse(await fs.readFile(process.env.SDK_MIGRATION_INPUTS,'utf8'));
const parent=request.work;
await fs.mkdir(parent,{recursive:true});
const platform='linux_x86_64',tuple=platform+'_cjnative';
const make=async name=>fs.mkdtemp(path.join(parent,name+'-'));
const inputRow=(commit,name)=>({commit,tree:'a'.repeat(40),repository:request[name],install:request[name],configuration:{interfaceOnly:true},buildResult:request[name]+'/BUILD-INPUTS.json'});
const configuration=createBootstrapTargets({platform,work:path.join(parent,'work'),install:path.join(parent,'install'),
 host:{install:request.host,version:readHostToolchainPin(platform).replace(/^nightly-/,'')},
 llvm:inputRow(FIXED_INPUTS.llvm,'llvm'),runtime:inputRow(FIXED_INPUTS.runtime,'runtime'),ast:inputRow(FIXED_INPUTS.compiler,'ast'),
 h1:inputRow(FIXED_INPUTS.h1,'h1'),compiler:inputRow('b'.repeat(40),'compiler'),stdlib:inputRow(FIXED_INPUTS.runtime,'runtime'),tools:{privateRoot:'/unused'}});

test('real H and AST schema projection has one producer and preserves conflict rejection',async()=>{
 const root=await make('schema');
 const copies=configuration.stages.find(s=>s.id==='stage0-run').copies;
 // Consume the production H-root and AST-schema selections, with their real
 // file contents. Other native outputs belong to the separately gated SDK flow.
 const selected=[copies.find(c=>c.owner==='H'&&c.to===''),copies.find(c=>c.owner==='schema')];
 let error;try{await copyOutputs(root,selected);}catch(e){error=e;}
 console.log('SCHEMA_OWNERSHIP_TARGET_ASSERTION_REACHED '+JSON.stringify({error:error?.message,selected}));
 assert.equal(error,undefined,'H root and AST schema must have disjoint output ownership');
 const output=path.join(root,'schema/StdAstFormat.fbs');
 let actual;try{actual=await fileDigest(output);}catch(e){actual=e.code;}
 console.log('AST_SCHEMA_CONSUMER_TARGET_ASSERTION_REACHED '+JSON.stringify({output,actual}));
 assert.equal(actual,await fileDigest(path.join(request.ast,'schema/StdAstFormat.fbs')),'installed schema must be the actual AST output');
 await assert.rejects(copyOutputs(root,[selected[1]]),/INSTALL_CONFLICT schema\//,'ordinary duplicate installation is still rejected');
});

async function referenceInstall(label){
 const root=await make(label),sdk=path.join(root,'install');
 const expected=await fileDigest(path.join(request.host,'bin/cjc'));
 // The same install/entry/metadata producer used by bootstrap performs this
 // reference projection. The independent expected hash comes from received H.
 await buildFlow({work:path.join(root,'flow'),install:sdk,finalStage:'reference-interface',repos:{},
  stages:[{id:'reference-interface',output:sdk,copies:[
   {from:request.host,to:'',exclude:['.cjv','bin/cjc','bin/cjc-frontend'],owner:'reference H'},
   {from:path.join(request.host,'bin/cjc'),to:'bin/cjcj-stage1',owner:'reference compiler'}],
  entries:[{directory:'bin',retain:'libexec/compiler',names:['cjcj-stage1'],
   libraries:['runtime/lib/'+tuple,'lib/'+tuple,'third_party/llvm/lib','tools/lib']}],
  links:{'bin/cjc':'cjcj-stage1','bin/cjc-frontend':'cjcj-stage1'},
  metadata:{phase:'reference-interface',platform,compilerFile:'libexec/compiler/cjcj-stage1'}}],test:{}}, {packageOutput:false});
 return {root,sdk,expected};
}
test('actual installed compiler identity reaches bootstrap language input admission',async()=>{
 const {root,sdk,expected}=await referenceInstall('identity');
 let record,error;try{record=await verifyCompiler(sdk,expected);}catch(e){error=e;}
 console.log('INSTALLED_COMPILER_IDENTITY_TARGET_ASSERTION_REACHED '+JSON.stringify({expected,actual:record?.compilerSha256,error:error?.message}));
 assert.equal(error,undefined,'native entry resolves the independently expected producer');
 const runner=new URL('../cangjie-test/run.py',import.meta.url).pathname;
 const result=spawnSync('python3',[runner,sdk,path.join(root,'language-output'),'--inputs',path.join(root,'missing-inputs'),
  '--arm','bootstrap','--bootstrap-compiler-sha256',expected],{encoding:'utf8'});
 console.log('LANGUAGE_IDENTITY_CONSUMER_TARGET_ASSERTION_REACHED '+JSON.stringify({rc:result.status,stderr:result.stderr}));
 assert.equal(result.status,2);assert.match(result.stderr,/missing input:/,'real bootstrap runner must pass compiler identity before checking language inputs');
 await assert.rejects(verifyCompiler(sdk,'0'.repeat(64)),/independent bootstrap producer mismatch/);
 const entry=path.join(sdk,'bin/cjcj-stage1.entry'),before=await fs.readFile(entry,'utf8');
 await fs.writeFile(entry,before.replace('libexec/compiler/cjcj-stage1','.host/bin/cjc'));
 await assert.rejects(verifyCompiler(sdk,expected),/entry producer mismatch/);
 await fs.writeFile(entry,before);
});
test('real installed H compiler and default cjpm compile/run hello before and after archive relocation',async()=>{
 const {root,sdk}=await referenceInstall('hello');
 let result,error;try{result=await helloInstall({sdk,work:path.join(root,'hello'),platform});}catch(e){error=e;}
 console.log('REAL_CJPM_CONFIGURATION_TARGET_ASSERTION_REACHED '+JSON.stringify({error:error?.message,compiled:result?.compiled,packaged:result?.packaged}));
 assert.equal(error,undefined,'generated hello package must be accepted by the actual cjpm');
 assert.equal(result.compiled.stdout.trim(),'Hello, Cangjie');assert.equal(result.packaged.stdout.trim(),'Hello, Cangjie');
 const archived=await archiveInstall({install:sdk,archive:path.join(root,'reference.tar.gz'),test:{commands:[{argv:[process.execPath,
  new URL('./sdk-hello.mjs',import.meta.url).pathname,'--sdk','${install}','--work','${work}','--platform',platform]}]},vars:{work:path.join(root,'unpacked-test')},records:[]});
 console.log('REAL_INSTALL_ARCHIVE_TARGET_ASSERTION_REACHED '+JSON.stringify(archived));
 assert.match(archived.sha256,/^[a-f0-9]{64}$/);
});

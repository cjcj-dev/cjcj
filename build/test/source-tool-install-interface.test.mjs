#!/usr/bin/env zx
// Actual install callers; tool and third-party outputs are controlled
// interface inputs. Only the launcher is compiled as a real native product.
import fs from 'node:fs/promises';
import path from 'node:path';
import test from 'node:test';
import assert from 'node:assert/strict';
import {spawnSync} from 'node:child_process';
import {buildConfig} from '../lib/config.mjs';
import {installSourceTools} from '../srcbuild/install-tools.mjs';
import {installHleDependencies} from '../srcbuild/hle-dependencies.mjs';
import {hlePayloadFixture} from './hle-payload-fixture.mjs';
const parent=process.env.RELEASE_EVIDENCE_TEST_ROOT;
if(!parent)throw new Error('RELEASE_EVIDENCE_TEST_ROOT required');
await fs.mkdir(parent,{recursive:true});
const write=async(file,value,mode=0o644)=>{await fs.mkdir(path.dirname(file),{recursive:true});await fs.writeFile(file,value,{mode});};
test('A8 controlled HLE inputs and nine installed tool interfaces retain configuration',async()=>{
 const work=await fs.mkdtemp(path.join(parent,'a8-install-')),workspace=path.join(work,'workspace');
 const config=buildConfig({workspace,buildRoot:path.join(work,'buildtools'),cangjieVersion:'1.2.3',consumerSdk:path.join(workspace,'software/cangjie'),officialSdkRoot:path.join(work,'official'),toolsPhase:'install'});
 const sdk=config.consumerSdk,tools=config.repoPath('tools');
 const rows=[['cjpm','cjpm/dist/cjpm'],['cjfmt','cjfmt/dist/bin/cjfmt'],['hle','hyperlangExtension/target/bin/main'],['LSPServer','cangjie-language-server/output/bin/LSPServer'],['cjcov','cjcov/dist/cjcov'],['cjtrace-recover','cjtrace-recover/dist/bin/cjtrace-recover'],['cjlint','cjlint/dist/bin/cjlint'],['cjprof','cjprof/dist/bin/cjprof'],['cjcompat','cjcompat/dist/bin/cjcompat']];
 for(const [name,relative]of rows){await write(path.join(tools,relative),'#!'+process.execPath+'\nconsole.log(process.env.ENTRY_ARGV_PROBE ? JSON.stringify({args:process.argv.slice(2),cwd:process.cwd()}) : '+JSON.stringify(name+':42')+');\n',0o755);await write(path.join(sdk,'tools/bin',name),'old '+name);await write(path.join(config.officialSdkRoot,'tools/bin',name),'official interface');}
 await write(path.join(sdk,'tools/config/other.toml'),'preserved');
 for(const rel of ['cjlint/dist/lib/libcangjie-runtime.so','cjlint/dist/runtime/lib/linux_x86_64_cjnative/libcangjie-runtime.so','cjlint/dist/modules/std.core.cjo','cjlint/dist/config/cjlint_rule_list.json','cjprof/dist/lib/libcjprof-cangjie.so','cjprof/dist/lib/libcjprof-jni.so','cjprof/dist/share/java/cjprof.jar','cjprof/dist/config/static/index.html'])await write(path.join(tools,rel),'explicit interface payload '+rel);
 await write(path.join(tools,'cjfmt/dist/config/cangjie-format.toml'),'new format');
 await write(path.join(tools,'cjpm/dist/cangjie-repo.toml'),'new repository');
 const parser=path.join(tools,'hyperlangExtension/src/dtsparser');
 await write(path.join(parser,'analysis.js'),'controlled parser source');
 await write(path.join(parser,'package.json'),JSON.stringify({dependencies:{typescript:'npm:typescript@4.9.5','https-proxy-agent':'7.0.6'}}));
 await write(path.join(parser,'source.cj'),'excluded source');
 const dependencyRoot=path.join(work,'dependencies');hlePayloadFixture(dependencyRoot);
 const input={platform:'linux_x86_64',node:{path:process.execPath,source:'controlled native Node input',version:process.version},modules:{path:path.join(dependencyRoot,'tools/dtsparser/node_modules'),source:'controlled npm boundary',version:'fixture'},cjbind:{path:process.execPath,source:'controlled executable boundary, not actual cjbind',version:'v1.1.0-alpha.53.1'}};
 await installHleDependencies({toolsRoot:tools,sdk,platform:'linux_x86_64',input});
 const consume=async pending=>{for(const [name]of rows){const r=spawnSync(path.join(pending,'tools/bin',name),[],{encoding:'utf8'});assert.equal(r.status,0,r.stderr);assert.equal(r.stdout.trim(),name+':42');}};
 const installed=await installSourceTools(config,undefined,{consume});
 const recorded=JSON.parse(await fs.readFile(path.join(sdk,'TOOLS-INPUTS.json'),'utf8'));
 assert.equal(await fs.readFile(path.join(sdk,'.target-tools/tools/config/static/index.html'),'utf8'),'explicit interface payload cjprof/dist/config/static/index.html');
 assert.equal(recorded.files['tools/bin/cjprof'].producer.source.status,'unresolved','fixture payloads do not acquire target qualification');
 assert.equal(recorded.buildSelection.phase,'install');
 assert.equal(recorded.buildSelection.builtThisInvocation,'none');
 assert.equal(recorded.buildSelection.reusedExistingOutputs.length,9);
 for(const [name]of rows){const result=spawnSync(path.join(sdk,'tools/bin',name),[],{encoding:'utf8'});console.log('A8_NATIVE_INSTALL_TARGET_ASSERTION_REACHED',name,result.status,result.stdout.trim());assert.deepEqual({rc:result.status,out:result.stdout.trim()},{rc:0,out:name+':42'});}
 assert.equal(await fs.readFile(path.join(sdk,'tools/config/other.toml'),'utf8'),'preserved');
 assert.equal(await fs.readFile(path.join(sdk,'tools/config/cangjie-repo.toml'),'utf8'),'new repository');
 assert.equal(await fs.readFile(path.join(sdk,'tools/dtsparser/analysis.js'),'utf8'),'controlled parser source');
 const caller=path.join(work,'unrelated caller');await fs.mkdir(caller);
 function probe(root,name,args){const r=spawnSync(path.join(root,'tools/bin',name),args,{cwd:caller,env:{...process.env,ENTRY_ARGV_PROBE:'1'},encoding:'utf8'});assert.equal(r.status,0,r.stderr);const got=JSON.parse(r.stdout);assert.equal(got.cwd,caller);return got.args;}
 const defaults=root=>['-b',root+'/tools/dtsparser/node_modules/.bin/cjbind','-j',root+'/tools/dtsparser/analysis.js','-r',root+'/tools/dtsparser/node_modules/typescript'];
 assert.deepEqual(probe(sdk,'hle',['-i','relative input','-o','relative output']),[...defaults(sdk),'-i','relative input','-o','relative output']);
 for(const explicit of [['-b','relative cjbind','-j','relative parser','-r','relative typescript'],['-cbtool','-jparser','-rtypescript'],['-b=tool','-j=parser','-r=typescript']])assert.deepEqual(probe(sdk,'hle',explicit),explicit);
 for(const operand of [['-i','-b'],['--clang-args','-b'],['--module-name','-j']])assert.deepEqual(probe(sdk,'hle',operand),[...defaults(sdk),...operand]);
 // std.argopt tries the entire long name before short clusters, including a
 // single dash. Required values may themselves contain help/dependency flags.
 for(const dash of ['-','--']){
  for(const name of ['clang-args','module-name']){
   for(const value of ['-pthread','-b','-j','-r','-h','--help']){
    for(const operand of [[dash+name,value],[dash+name+'='+value]])
     assert.deepEqual(probe(sdk,'hle',operand),[...defaults(sdk),...operand]);
   }
  }
  for(const name of ['lib','no-detect-include-path']){
   const args=[dash+name,'-i','relative input'];
   assert.deepEqual(probe(sdk,'hle',args),[...defaults(sdk),...args]);
  }
  assert.deepEqual(probe(sdk,'hle',[dash+'help']),[dash+'help']);
 }
 for(const operand of [['-ci','-h'],['-i-h'],['--','-b','-h']])
  assert.deepEqual(probe(sdk,'hle',operand),[...defaults(sdk),...operand]);
 assert.deepEqual(probe(sdk,'hle',['-ch']),['-ch']);
 assert.deepEqual(probe(sdk,'hle',['--help']),['--help']);
 assert.deepEqual(probe(sdk,'cjpm',['-i','input']),['-i','input'],'other native entries retain argv');
 const moved=sdk+'-relocated';await fs.rename(sdk,moved);
 try{assert.deepEqual(probe(moved,'hle',['-i','relative input']),[...defaults(moved),'-i','relative input']);}
 finally{await fs.rename(moved,sdk);}
 await installSourceTools(config,undefined,{consume});
 for(const [name]of rows){const r=spawnSync(path.join(sdk,'tools/bin',name),[],{encoding:'utf8'});assert.equal(r.status,0);assert.equal(r.stdout.trim(),name+':42','installed public entry survives reentry');}
 const foreignRecipe=path.join(sdk,'tools/bin/cjpm.entry'),savedRecipe=await fs.readFile(foreignRecipe,'utf8');
 try{await fs.writeFile(foreignRecipe,savedRecipe.replace('.target-tools/tools/bin/cjpm','.target-tools/tools/bin/foreign'));await assert.rejects(installSourceTools(config,undefined,{consume}),/SOURCE_TOOL_OWNERSHIP cjpm/);}
 finally{await fs.writeFile(foreignRecipe,savedRecipe);}
 const nodeResult=spawnSync(path.join(sdk,'tools/bin/node'),['--version'],{encoding:'utf8'});assert.equal(nodeResult.stdout.trim(),process.version);
 // Packaging is exercised by the real-SDK integration, not these interface doubles.
});

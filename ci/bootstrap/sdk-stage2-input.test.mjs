#!/usr/bin/env zx
import test from 'node:test';import assert from 'node:assert/strict';
import fs from 'node:fs/promises';import path from 'node:path';
import {stage2Input} from './sdk-stage2-input.mjs';
import {stage2Fixture} from './stage2-input-fixture.mjs';
import {validateSourceInputs,installedFinalStd} from './sdk-inputs.mjs';
test('C2 input preserves original compiler/parent/std facts without claiming the old installed gate passed',async()=>{
 const f=await stage2Fixture();const row=await stage2Input(f.supplied,f.input);
 assert.equal(row.compilerCommit,f.facts.commit);assert.equal(row.parentSha256,f.facts.parentSha256);
 assert.equal(row.stdSha256,f.facts.stdSha256);assert.equal('status' in row,false);
 const changed={...f.input,ast:f.input.compiler,stage2:row};await validateSourceInputs(changed);
 await f.write('sdk/libexec/compiler/cjcj-stage1','changed');
 await assert.rejects(validateSourceInputs(changed),/C2_REUSE_PRODUCT_IDENTITY/);
});
test('failed original C2 compilation is not promoted by reuse',async()=>{
 const f=await stage2Fixture();await fs.writeFile(f.supplied.buildResult,JSON.stringify({rc:1}));
 await assert.rejects(stage2Input(f.supplied,f.input),/C2_REUSE_PRODUCER_MISMATCH/);
});
test('C2 reuse rejects different H1, std, LLVM and runtime headers',async()=>{
 for(const [file,text,error]of [['H1/build-inputs.json','{}',/C2_REUSE_H1_SOURCE/],['std/PROVENANCE.txt','changed',/C2_REUSE_PRODUCT_IDENTITY/],['N/third_party/llvm/lib/libLLVM-15.so','changed',/C2_REUSE_LLVM_IDENTITY/],['R/include/RuntimeConfig.h','changed',/C2_REUSE_RUNTIME_HEADER/]]){
  const f=await stage2Fixture();await f.write(file,text);await assert.rejects(stage2Input(f.supplied,f.input),error);
 }
});
test('runtime change with unchanged std sources is explicit; changed std sources require rebuilding',async()=>{
 const f=await stage2Fixture();await f.write('runtime.txt','lock change');f.git('add','runtime.txt');f.git('commit','-qm','test: runtime-only source');
 f.input.runtime.commit=f.git('rev-parse','HEAD');assert.ok(await stage2Input(f.supplied,f.input));
 await f.write('stdlib/source.cj','new std source');f.git('add','stdlib');f.git('commit','-qm','test: different std source');f.input.runtime.commit=f.git('rev-parse','HEAD');
 await assert.rejects(stage2Input(f.supplied,f.input),/C2_REUSE_STD_SOURCE/);
});
test('missing C2 source inputs fail rather than selecting an active HEAD',async()=>{
 const f=await stage2Fixture();await assert.rejects(stage2Input({...f.supplied,buildResult:undefined},f.input),/C2_REUSE_LOCATIONS_REQUIRED/);
 await fs.rm(path.join(f.supplied.install,'share/cjcj'),{recursive:true});
 await assert.rejects(stage2Input(f.supplied,f.input),/ENOENT/);
});
test('ordinary CJPM source-build is an explicit C2 input without fabricated compiler-inputs',async()=>{
 const f=await stage2Fixture();
 await fs.rm(path.join(f.root,'sdk/compiler-inputs.json'));
 await f.write('source/cjpm.toml','[package]\nname="ordinary"\n');
 const sourceProduct=path.join(f.root,'producer/target/release/bin/cjcj::cjc');
 const command=path.join(f.root,'producer/workspace.command.json');
 const buildResult=path.join(f.root,'producer/workspace.result.json');
 await f.write('sdk/STAGE-INPUTS.json',JSON.stringify({
   phase:'source-build',platform:'linux_x86_64',compilerFile:'libexec/compiler/cjcj-stage1',
   compilerCommit:f.facts.commit,runtimeCommit:f.input.runtime.commit,
   compilerSha256:f.facts.compilerSha256,
   selection:{targetComponents:{
     compiler:{repository:'https://github.com/cjcj-dev/cjcj.git',commit:f.facts.commit},
     std:{repository:'https://github.com/cjcj-dev/cangjie-runtime.git',commit:f.input.runtime.commit,
       install:path.join(f.root,'removed-original-std')}}}
 }));
 await f.write('producer/workspace.command.json',JSON.stringify({
   argv:['cjpm','build','--target-dir',path.join(f.root,'producer/target')],cwd:path.join(f.root,'source')
 }));
 await f.write('producer/workspace.result.json',JSON.stringify({rc:0,signal:null}));
 const row=await stage2Input({
   mode:'ordinary-cjpm',install:path.join(f.root,'sdk'),bootstrapStd:path.join(f.root,'std'),
   stdSourceInstall:path.join(f.root,'std'),
   buildResult,command,sourceRoot:path.join(f.root,'source'),sourceProduct
 },f.input);
 assert.equal(row.mode,'ordinary-cjpm');
 assert.equal('compilerInputs' in row,false);
 assert.equal(row.compilerSha256,f.facts.compilerSha256);
 assert.equal(row.command,path.resolve(command));
 assert.deepEqual(row.compilerSource,{repository:'https://github.com/cjcj-dev/cjcj.git',commit:f.facts.commit,
   sourceRoot:path.join(f.root,'source'),product:sourceProduct,
   install:path.join(f.root,'sdk/libexec/compiler/cjcj-stage1'),file:'libexec/compiler/cjcj-stage1'});
 assert.deepEqual(row.stdSource.repository,'https://github.com/cjcj-dev/cangjie-runtime.git');
 assert.equal(row.stdSourceInstall,path.resolve(path.join(f.root,'std')));
 assert.deepEqual(await stage2Input(row,f.input),row);
 assert.equal(row.stdSha256,await (await import('../srcbuild/lib/final-compiler.mjs')).stdIdentity(path.join(f.root,'std')));
 const host=await f.write('host/bin/cjc',`#!${process.execPath}\nconsole.log('Cangjie Compiler: 1.3.0-alpha.20261009001050 (cjnative)');\n`);
 await fs.chmod(host,0o755);
 const validated={...f.input,ast:f.input.compiler,stage2:row,
   host:{install:path.join(f.root,'host'),version:'1.3.0-alpha.20261009001050'}};
 await validateSourceInputs(validated);
 await assert.rejects(validateSourceInputs({...validated,host:{...validated.host,version:'1.3.0-alpha.20261025001053'}}),/NATIVE_COMPONENT_ACTUAL_HOST/);
 // Only the unused H1 macro contract is irrelevant to an ordinary producer.
 // Keep the fixed Git object check and all consumed-compiler checks intact.
 await f.write('packages/macro/src/InvokeUtil.cj','obsolete H1 macro source');
 f.git('add','packages/macro/src/InvokeUtil.cj');f.git('commit','-qm','test: obsolete H1 macro source');
 const obsolete={...f.input.h1,commit:f.git('rev-parse','HEAD'),tree:f.git('rev-parse','HEAD^{tree}')};
 await validateSourceInputs({...validated,h1:obsolete});
 await assert.rejects(validateSourceInputs({...validated,h1:{...obsolete,tree:f.input.h1.tree}}),/NATIVE_SOURCE_TREE h1/);
 await assert.rejects(validateSourceInputs({...validated,h1:obsolete,stage2:undefined}),/NATIVE_MACRO_SOURCE h1/);
 await assert.rejects(validateSourceInputs({...validated,h1:obsolete,stage2:{...row,mode:undefined}}),/NATIVE_MACRO_SOURCE h1/);
 await assert.rejects(validateSourceInputs({...validated,compiler:obsolete}),/NATIVE_MACRO_SOURCE compiler/);
});
test('explicit final std reuse retains completed native commands and rejects failed production',async()=>{
 const f=await stage2Fixture(),install=path.join(f.root,'std');
 await f.write('std/modules/linux_x86_64_cjnative/std/std.core.cjo','module');
 await f.write('std/PROVENANCE.txt',`STD_SOURCE_COMMIT = ${f.facts.commit}\nBUILT_BY_CJC = ${f.facts.commit}\nCOLOURED = true\n`);
 const rows=[{argv:['python3','-I','build.py','build'],cwd:f.root,rc:0,signal:null},
  {argv:['python3','-I','build.py','install','--prefix',install],cwd:f.root,rc:0,signal:null}];
 const commands=await f.write('std.commands.json',JSON.stringify(rows));
 const input={...f.input,stdlib:f.input.runtime,stage2:{compilerCommit:f.facts.commit}};
 const row=await installedFinalStd({install,commands},input);
 assert.deepEqual(row,{install,commands});
 assert.deepEqual(await installedFinalStd(row,input),row);
 rows[0].rc=1;await f.write('std.commands.json',JSON.stringify(rows));
 await assert.rejects(installedFinalStd(row,input),/FINAL_STD_REUSE_PRODUCER/);
 rows[0].rc=0;rows[1].argv[5]=install+'-other';
 await f.write('std.commands.json',JSON.stringify(rows));
 await assert.rejects(installedFinalStd(row,input),/FINAL_STD_REUSE_PRODUCER/);
});

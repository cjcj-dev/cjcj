#!/usr/bin/env zx
import test from 'node:test';import assert from 'node:assert/strict';
import fs from 'node:fs/promises';import path from 'node:path';
import {stage2Input} from './sdk-stage2-input.mjs';
import {stage2Fixture} from './stage2-input-fixture.mjs';
import {validateSourceInputs} from './sdk-inputs.mjs';
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
 await fs.rm(path.join(f.supplied.install,'share/cjcj/runtime_shim/cjc_runtime_config.o'));
 await assert.rejects(stage2Input(f.supplied,f.input),/ENOENT/);
});

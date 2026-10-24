import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs/promises';
import path from 'node:path';
import {spawnSync} from 'node:child_process';
import {nativePair} from './native-runtime-input.mjs';
const parent = process.env.RELEASE_EVIDENCE_TEST_ROOT;
if(!parent)throw new Error('RELEASE_EVIDENCE_TEST_ROOT required');
const runtime='79b34798d0f4696f9fe5a3708981539466ecd35b',llvm='db51a4c7ebb6903e9f997d3b35d52f3577810385';
test('explicit native pair requires both source objects and the actual host version',()=>{
 assert.equal(nativePair({}),null);
 assert.throws(()=>nativePair({CJCJ_NATIVE_LLVM_REF:llvm}),/EXPLICIT_PAIR_REQUIRED/);
 assert.throws(()=>nativePair({CJCJ_NATIVE_LLVM_REF:llvm,CJCJ_NATIVE_RUNTIME_REF:runtime}),/EXPLICIT_HOST_REQUIRED/);
 assert.deepEqual(nativePair({CJCJ_NATIVE_LLVM_REF:llvm,CJCJ_NATIVE_RUNTIME_REF:runtime,CJCJ_NATIVE_HOST_VERSION:'1.3.0-alpha.20260925001050'}),
  {llvm,runtime,hostVersion:'1.3.0-alpha.20260925001050'});
});
test('real component CLI checks source pair and native install members before the mandatory native CPP record',async()=>{
 await fs.mkdir(parent,{recursive:true});const root=await fs.mkdtemp(path.join(parent,'native-runtime-input-')),sdk=root+'/runtime';
 const write=async(relative,value)=>{await fs.mkdir(path.dirname(sdk+'/'+relative),{recursive:true});await fs.writeFile(sdk+'/'+relative,value);};
 await write('SOURCE_SHA',runtime+'\n');
 // Controlled status precondition, deliberately missing the language result.
 // This fixture is rejected and never qualifies a runtime or a gate run.
 await write('share/runtime-build/runtime/CMakebuild/gc-unit.status','GATE=PASS\nGATE_RC=0\nLANGUAGE_TESTS=NOT_RUN\n');
 for(const rel of ['runtime/lib/linux_x86_64_cjnative/libcangjie-runtime.so','runtime/lib/linux_x86_64_cjnative/libboundscheck.so','lib/linux_x86_64_cjnative/libcangjie-runtime.a'])await write(rel,'finite unqualified component');
 const record={runtime_sha:runtime,paired_llvm_sha:llvm,platform:'linux_x86_64',version:'fixture',build_type:'release',language_test_mode:'defer'};
 async function recordInput(extra={}){await write('NATIVE-INPUTS.json',JSON.stringify({...record,...extra}));}
 const descriptor={root:sdk,platform:'linux_x86_64',llvmCommit:llvm,runtimeCommit:runtime,hostVersion:'1.3.0-alpha.20260925001050',work:root+'/work'};
 const input=root+'/input.json';await fs.writeFile(input,JSON.stringify(descriptor));
 const run=async label=>{const result=spawnSync(process.execPath,[new URL('./native-runtime-input.mjs',import.meta.url).pathname,input],{encoding:'utf8'});await fs.writeFile(root+'/'+label+'.log',result.stdout+result.stderr);await fs.writeFile(root+'/'+label+'.rc',String(result.status));console.log('NATIVE_RUNTIME_CLI '+label+' rc='+result.status+' root='+root);assert.equal(result.status,1);return result;};
 await recordInput();const normal=await run('normal');assert.match(normal.stderr,/LANGUAGE_DEFERRED missing/);
 await recordInput({paired_llvm_sha:'c'.repeat(40)});assert.match((await run('pair-cut')).stderr,/COMPONENT_IDENTITY/);
 await recordInput();await fs.rename(sdk+'/runtime/lib/linux_x86_64_cjnative/libboundscheck.so',sdk+'/runtime/lib/linux_x86_64_cjnative/libboundscheck.so.saved');assert.match((await run('member-cut')).stderr,/ENOENT/);
 await fs.rename(sdk+'/runtime/lib/linux_x86_64_cjnative/libboundscheck.so.saved',sdk+'/runtime/lib/linux_x86_64_cjnative/libboundscheck.so');
 await recordInput();assert.match((await run('restored')).stderr,/LANGUAGE_DEFERRED missing/);
 assert.doesNotMatch(normal.stdout,/COMPONENT_ACCEPTED/);
});

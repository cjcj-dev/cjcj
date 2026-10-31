import assert from 'node:assert/strict';
import {spawnSync} from 'node:child_process';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import test from 'node:test';
import {resolveShimSources,selectShimSources} from './shim-header-sources.mjs';
import {readSourcePins} from '../native-llvm-inputs.mjs';
import {prepareCppHeaders} from './prepare_cpp_headers.mjs';

function git(args) {const r=spawnSync('git',args,{encoding:'utf8'});assert.equal(r.status,0,r.stderr);return r.stdout.trim();}
function fixture() {
 const root=fs.mkdtempSync(path.join(os.tmpdir(),'cpp-headers-identity-')),source=path.join(root,'source');
 git(['init','-q',source]);fs.mkdirSync(path.join(source,'schema'));
 fs.writeFileSync(path.join(source,'schema/CjoFormat.fbs'),'table Actual {}');
 // Small native projects exercise the formal configure/build/generate/copy
 // entry. They are command consumers, not LLVM or FlatBuffers qualification.
 fs.mkdirSync(path.join(source,'llvm/include'),{recursive:true});fs.mkdirSync(path.join(source,'include'));
 fs.writeFileSync(path.join(source,'llvm/include/finite.h'),'// finite LLVM input\n');
 fs.writeFileSync(path.join(source,'include/finite.h'),'// finite flatbuffers input\n');
 fs.writeFileSync(path.join(source,'llvm/CMakeLists.txt'),'cmake_minimum_required(VERSION 3.16)\nproject(FiniteHeaders NONE)\nadd_custom_target(intrinsics_gen COMMAND ${CMAKE_COMMAND} -E make_directory ${CMAKE_BINARY_DIR}/include)\n');
 fs.writeFileSync(path.join(source,'CMakeLists.txt'),'cmake_minimum_required(VERSION 3.16)\nproject(FiniteFlatc C)\nadd_executable(flatc flatc.c)\n');
 fs.writeFileSync(path.join(source,'flatc.c'),'#include <stdio.h>\n#include <string.h>\nint main(int argc,char **argv){char name[4096];for(int i=1;i+1<argc;i++)if(!strcmp(argv[i],"-o")){snprintf(name,sizeof(name),"%s/CjoFormat_generated.h",argv[i+1]);FILE *f=fopen(name,"w");if(!f)return 3;fputs("// finite schema command consumer\\n",f);return fclose(f);}return 2;}\n');
 git(['-C',source,'add','.']);git(['-C',source,'-c','user.name=Zxilly','-c','user.email=zxilly@outlook.com','commit','-qm','source input']);
 const commit=git(['-C',source,'rev-parse','HEAD']);
 const rows=Object.fromEntries(['compiler','llvm','runtime','flatbuffers'].map(name=>[name,{root:source,commit}]));
 const env={...process.env,CJCJ_BOOTSTRAP_SHIM_SOURCE_SELECTION:JSON.stringify(rows)};
 delete env.CJCJ_BOOTSTRAP_SHIM_SOURCES;
 return {root,source,commit,rows,env};
}
test('prepare_cpp_headers rejects a foreign compiler identity before configuration',async()=>{
 const {root,rows,env}=fixture();rows.compiler.commit='0'.repeat(40);
 env.CJCJ_BOOTSTRAP_SHIM_SOURCE_SELECTION=JSON.stringify(rows);
 await assert.rejects(resolveShimSources(root,env),/NATIVE_SOURCE_COMMIT/);
 assert.equal(fs.existsSync(path.join(root,'build')),false);
});
test('selected compiler repository identity is checked rather than relabeled',async()=>{
 const {root,rows,env}=fixture();rows.compiler.repository='/unrelated/repository';
 env.CJCJ_BOOTSTRAP_SHIM_SOURCE_SELECTION=JSON.stringify(rows);
 await assert.rejects(resolveShimSources(root,env),/SHIM_SOURCE_REPOSITORY compiler/);
});
test('default header source selection uses the production compiler pin and requires fetch for an absent checkout',async()=>{
 const {root,env}=fixture();delete env.CJCJ_BOOTSTRAP_SHIM_SOURCE_SELECTION;
 const selected=selectShimSources(root,env);
 assert.equal(selected.compiler.repository,readSourcePins().source.COMPILER_SRC_URL);
 assert.equal(selected.compiler.commit,readSourcePins().source.COMPILER_REF);
 await assert.rejects(resolveShimSources(root,env,{fetch:false}),/SHIM_SOURCE_LOCATION_REQUIRED compiler/);
});
test('header source runtime and target LLVM must match the actual selected pair',async()=>{
 const {root,commit,env}=fixture();
 Object.assign(env,{CJCJ_NATIVE_RUNTIME_REF:commit,CJCJ_NATIVE_LLVM_REF:'0'.repeat(40)});
 delete env.CJCJ_RUNTIME_REF_OVERRIDE;delete env.CJCJ_ALLOW_RUNTIME_OVERRIDE;
 delete env.CJCJ_NATIVE_RUNTIME_ARTIFACT;delete env.CJCJ_BOOTSTRAP_RUNTIME_PIN;
 await assert.rejects(prepareCppHeaders(root,undefined,env),/SHIM_HEADERS_LLVM_PAIR/);
 assert.equal(fs.existsSync(path.join(root,'build')),false);
 const rows=JSON.parse(env.CJCJ_BOOTSTRAP_SHIM_SOURCE_SELECTION);rows.runtime.commit='0'.repeat(40);
 env.CJCJ_BOOTSTRAP_SHIM_SOURCE_SELECTION=JSON.stringify(rows);
 await assert.rejects(prepareCppHeaders(root,undefined,env),/SHIM_HEADERS_RUNTIME_PAIR/);
 assert.equal(fs.existsSync(path.join(root,'build')),false);
 rows.runtime.commit=commit;env.CJCJ_NATIVE_LLVM_REF=commit;
 env.CJCJ_BOOTSTRAP_SHIM_SOURCE_SELECTION=JSON.stringify(rows);
 const normal=await prepareCppHeaders(root,undefined,env);
 assert.equal(normal.sources.llvm.commit,commit);assert.ok(normal.commands.every(row=>row.rc===0));
 assert.ok(fs.existsSync(path.join(root,'build/build/schema/flatbuffers/CjoFormat_generated.h')));
 env.CJCJ_NATIVE_LLVM_REF='0'.repeat(40);
 await assert.rejects(prepareCppHeaders(root,undefined,env),/SHIM_HEADERS_LLVM_PAIR/);
 const independent=await resolveShimSources(root,env);assert.equal(independent.compiler.commit,commit);
 env.CJCJ_NATIVE_LLVM_REF=commit;
 const restored=await prepareCppHeaders(root,undefined,env);assert.ok(restored.commands.every(row=>row.rc===0));
 console.log('SHIM_HEADERS_LLVM_PAIR_TARGET_AND_RECOVERY_REACHED');
});

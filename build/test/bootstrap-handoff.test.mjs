import test from'node:test';import assert from'node:assert/strict';import fs from'node:fs/promises';import path from'node:path';import {spawnSync}from'node:child_process';
import {prepareBootstrapHandoff,assertBootstrapCompiler}from'../../ci/srcbuild/lib/bootstrap-handoff.mjs';
import {verifyCompiler,compilerProducer}from'../../ci/bootstrap/compiler_identity.mjs';
import {installCompiler}from'../../ci/fixtures/compiler-install.mjs';
import {fileDigest,atomicJson}from'../../ci/bootstrap/sdk-flow.mjs';
const parent=process.env.RELEASE_EVIDENCE_TEST_ROOT;if(!parent)throw new Error('RELEASE_EVIDENCE_TEST_ROOT required');await fs.mkdir(parent,{recursive:true});
async function fixture(){
 const root=await fs.mkdtemp(path.join(parent,'handoff-')),work=path.join(root,'work'),sdk=path.join(root,'consumer'),source=path.join(root,'source'),tuple='linux_x86_64_cjnative';
 const original=path.join(root,'compiler.c'),producer=path.join(root,'native-compiler');await fs.writeFile(original,'#include <stdio.h>\nint main(void){puts("native compiler input identity");return 0;}\n');
 const compile=spawnSync('cc',[original,'-o',producer],{encoding:'utf8'});assert.equal(compile.status,0,compile.stderr);
 const stage2=path.join(work,'sdk-stage2');await installCompiler(stage2,producer);
 await atomicJson(path.join(stage2,'STAGE-INPUTS.json'),{phase:'stage2',compilerFile:'bin/cjcj-stage1',compilerSha256:await fileDigest(producer)});
 for(const [rel,data]of Object.entries({['lib/'+tuple+'/libcangjie-std-core.a']:'std input bytes',['modules/'+tuple+'/std/std.core.cjo']:'module input bytes','share/cjcj/runtime_shim/cjselfhost_llvmshim.o':'LLVM shim input','share/cjcj/runtime_shim/cjc_runtime_config.o':'runtime config input'})){
  await fs.mkdir(path.dirname(path.join(stage2,rel)),{recursive:true});await fs.writeFile(path.join(stage2,rel),data);}
 return {root,work,sdk,source,tuple,stage2,producer,producerSha256:await fileDigest(producer)};
}
test('stage2 target handoff preserves compiler, full std and actual shim inputs',async()=>{
 const f=await fixture(),r=await prepareBootstrapHandoff(f);
 assert.equal(await fileDigest(await compilerProducer(f.sdk)),f.producerSha256);
 assert.equal(await fs.readFile(path.join(f.sdk,'modules',f.tuple,'std/std.core.cjo'),'utf8'),'module input bytes');
 assert.equal(await fs.readFile(path.join(f.source,'runtime_shim/cjselfhost_llvmshim.o'),'utf8'),'LLVM shim input');
 assert.equal(r.stdOutput.coreSha256,await fileDigest(path.join(f.stage2,'lib',f.tuple,'libcangjie-std-core.a')));
 const command=path.join(f.sdk,'bin/cjc');await assertBootstrapCompiler({...f,command});
 const child=spawnSync(command,[],{encoding:'utf8'});console.log('HANDOFF_NATIVE_RESULT',child.status,child.stdout.trim());assert.equal(child.status,0);assert.equal(child.stdout.trim(),'native compiler input identity');
});
for(const mutation of ['source','installed','alias','missing'])test('handoff rejects changed compiler input: '+mutation,async()=>{
 const f=await fixture();await prepareBootstrapHandoff(f);const command=path.join(f.sdk,'bin/cjc');
 if(mutation==='source')await fs.appendFile(f.producer,'changed');
 if(mutation==='installed')await fs.appendFile(path.join(f.sdk,'bin/cjcj-stage1'),'changed');
 if(mutation==='missing')await fs.rm(path.join(f.sdk,'bin/cjcj-stage1'));
 if(mutation==='alias'){await fs.rm(command);await fs.symlink('../compiler.c',command);}
 await assert.rejects(assertBootstrapCompiler({...f,command}));
});
test('canonical compiler aliases reject frontend substitution and obsolete binaries',async()=>{
 const f=await fixture();await verifyCompiler(f.stage2,f.producerSha256);
 const frontend=path.join(f.stage2,'bin/cjc-frontend');await fs.rm(frontend);await fs.copyFile(f.producer,frontend);
 await assert.rejects(verifyCompiler(f.stage2,f.producerSha256),/same-directory/);
 await fs.rm(frontend);await fs.symlink('cjcj-stage1',frontend);await fs.writeFile(path.join(f.stage2,'bin/cjc-upstream-oracle'),'obsolete');
 await assert.rejects(verifyCompiler(f.stage2,f.producerSha256),/stale compiler/);
});
test('missing producer cannot consume an unrelated existing install',async()=>{
 const f=await fixture();await fs.rm(f.stage2,{recursive:true});await fs.mkdir(f.sdk,{recursive:true});await fs.writeFile(path.join(f.sdk,'unrelated'),'keep');
 await assert.rejects(prepareBootstrapHandoff(f),{code:'ENOENT'});assert.equal(await fs.readFile(path.join(f.sdk,'unrelated'),'utf8'),'keep');
});

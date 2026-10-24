#!/usr/bin/env zx
// Read-only consumption of an actually completed installation and its original
// flow record. This tests installed native libraries, not bootstrap --from.
// No predecessor records, relocated configurations or SDK copies are created.
import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs/promises';
import path from 'node:path';
import {spawnSync} from 'node:child_process';
import crypto from 'node:crypto';
import {fileDigest, privateRoot, readJson, atomicJson} from './sdk-flow.mjs';
import {sdkPlatform} from './sdk-platform.mjs';

const inputsFile=process.env.SDK_NATIVE_LIBRARIES_INPUTS;
const root=await privateRoot(process.env.SDK_NATIVE_LIBRARIES_ROOT || '');
const completed=process.env.SDK_NATIVE_LIBRARIES_COMPLETED;
const targetsFile=process.env.SDK_NATIVE_LIBRARIES_TARGETS;
if(!inputsFile||!process.env.SDK_NATIVE_LIBRARIES_ROOT||!completed||!targetsFile)
  throw new Error('SDK_NATIVE_LIBRARIES_INPUTS/ROOT/COMPLETED/TARGETS required');
if(process.env.SDK_NATIVE_LIBRARIES_COPIED)throw new Error('relocated/copied predecessors are not original completed flow evidence');
const original=await readJson(inputsFile), native=sdkPlatform(original.platform);
if(original.platform!=='linux_x86_64')throw new Error('finite native library consumer requires linux_x86_64');
const tuple=native.tuple;
const run=(file,args,options={})=>spawnSync(file,args,{encoding:'utf8',maxBuffer:8*1024*1024,...options});
const targets=await readJson(targetsFile);
assert.equal(path.resolve(completed),targets.work,'use the original flow directory');
assert.deepEqual(targets.bootstrapInputs,original,'original inputs must match the completed configuration');
const built=await readJson(path.join(completed,'build-result.json'));
assert.equal(built.status,'COMPLETE','original completed production record required');
assert.equal(built.configuration,crypto.createHash('sha256').update(JSON.stringify(targets)).digest('hex'));
const installed=built.stages.find(stage=>stage.id==='stage1-initial');
assert.ok(installed?.output && installed.owners,'real stage1-initial production row required');
const sdk=await privateRoot(installed.output);
for(const entry of [completed,sdk,original.host.install,original.llvm.install,original.runtime.install,original.ast.install]) {
  const inputRoot=path.resolve(entry);
  assert.ok(root!==inputRoot&&!root.startsWith(inputRoot+path.sep)&&!inputRoot.startsWith(root+path.sep),
    'link outputs must not overlap any input domain');
}
console.log('COMPLETED_INSTALLATION_INPUT',JSON.stringify({targetsFile,inputsFile,completed,sdk,configuration:built.configuration}));
await fs.mkdir(root,{recursive:true});
await fs.mkdir(path.join(root,'tmp'),{recursive:true});
const env={...process.env,TMPDIR:path.join(root,'tmp')};
const c=path.join(root,'divide.c');
await fs.writeFile(c,'#include <stdio.h>\nextern __int128 __divti3(__int128, __int128);\nint main(void) { volatile __int128 a=84,b=2; printf("%lld\\n", (long long)__divti3(a,b)); return 0; }\n');
async function linkAndRun(label,lib){
  const binary=path.join(root,label);
  const argv=['-O0',c,'-L'+lib,'-Wl,--trace','-lclang_rt-builtins','-o',binary];
  const link=run('/usr/bin/clang',argv,{env});
  await atomicJson(path.join(root,label+'-link.json'),{file:'/usr/bin/clang',argv,rc:link.status,stdout:link.stdout,stderr:link.stderr});
  // No existence guard can hide this target assertion. Missing installation
  // reaches it with the real linker rc and diagnostics.
  console.log('NATIVE_LIBRARY_LINK_ASSERTION_REACHED '+JSON.stringify({label,rc:link.status,stdout:link.stdout,stderr:link.stderr}));
  assert.equal(link.status,0,label+': installed native builtins must satisfy the real link');
  assert.ok(link.stdout.includes(path.join(lib,'libclang_rt-builtins.a')),label+': linker must consume the installed archive');
  const execution=run(binary,[]);
  await atomicJson(path.join(root,label+'-run.json'),{file:binary,rc:execution.status,stdout:execution.stdout,stderr:execution.stderr,sha256:await fileDigest(binary)});
  assert.equal(execution.status,0,execution.stderr);assert.equal(execution.stdout.trim(),'42');
}
test('host builtins control remains linked from H',async()=>{
  await linkAndRun('host-control',path.join(sdk,'.host/lib',tuple));
  assert.equal(await fileDigest(path.join(sdk,'.host/lib',tuple,'libclang_rt-builtins.a')),
    await fileDigest(path.join(original.host.install,'lib',tuple,'libclang_rt-builtins.a')));
});
test('target builtins link and native installed set come from N, with std/AST ownership preserved',async()=>{
  await linkAndRun('target',path.join(sdk,'lib',tuple));
  const installed=built.stages.find(s=>s.id==='stage1-initial');
  for(const name of (await fs.readdir(path.join(original.llvm.install,'lib',tuple))).filter(n=>!['libcangjie-ast-support.a','libboundscheck-static.a'].includes(n))){
    const rel='lib/'+tuple+'/'+name;
    const observed=await fileDigest(path.join(sdk,rel)),expected=await fileDigest(path.join(original.llvm.install,rel));
    console.log('NATIVE_LIBRARY_ORIGIN_ASSERTION_REACHED '+JSON.stringify({rel,observed,expected,owner:installed.owners[rel]}));
    assert.equal(observed,expected,rel);assert.equal(installed.owners[rel],'N',rel);
  }
  for(const [name,owner,source]of [
    ['libcangjie-ast-support.a','AST',path.join(original.ast.install,'libcangjie-ast-support.a')],
    ['libboundscheck-static.a','std',path.join(completed,'targets/std-bootstrap/lib',tuple,'libboundscheck-static.a')],
    ['libcangjie-std-core.a','std',path.join(completed,'targets/std-bootstrap/lib',tuple,'libcangjie-std-core.a')]]){
    const rel='lib/'+tuple+'/'+name;assert.equal(installed.owners[rel],owner);
    assert.equal(await fileDigest(path.join(sdk,rel)),await fileDigest(source),rel);
  }
  assert.notEqual(await fileDigest(path.join(sdk,'lib',tuple,'libclang_rt-builtins.a')),
    await fileDigest(path.join(sdk,'.host/lib',tuple,'libclang_rt-builtins.a')),'N and H are distinct real archives');
});

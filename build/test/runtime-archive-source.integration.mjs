#!/usr/bin/env zx
// Finite native provenance producer/consumer: real generated object, SO and ar.
// This is not a complete runtime, SDK or ABI test.
import fs from 'node:fs/promises';
import path from 'node:path';
import assert from 'node:assert/strict';
import {spawnSync} from 'node:child_process';
import {fileDigest} from '../../ci/bootstrap/sdk-flow.mjs';
import {installedInputs} from '../../ci/srcbuild/lib/installed-inputs.mjs';
import {runtimeInputsForArtifact,recordRuntimeInputs} from '../lib/runtime-source-inputs.mjs';
import {writeToolchainIdentity,TOOLCHAIN_IDENTITY_ARTIFACTS} from '../lib/toolchain-identity.mjs';
import {contentSignals} from '../lib/package-lineage.mjs';
import {writeInstalledReleaseManifest} from '../lib/release-manifest.mjs';
const base=process.env.RELEASE_EVIDENCE_TEST_ROOT,generator=process.env.CJCJ_TEST_RUNTIME_GENERATOR;
if(!base||!generator)throw new Error('runtime archive test requires evidence root and fixed generator');
await fs.mkdir(base,{recursive:true});
const work=await fs.mkdtemp(path.join(base,'runtime-archive-')),repository=path.join(work,'objects'),materialized=path.join(work,'materialized');
const records=[];
async function run(argv,{cwd,rc=0}={}){
 const r=spawnSync(argv[0],argv.slice(1),{cwd,encoding:'utf8',env:{...process.env,CJ_RUNTIME_COMMIT:'e'.repeat(40)},maxBuffer:8*1024*1024});
 records.push({argv,cwd,rc:r.status,signal:r.signal,stdout:r.stdout,stderr:r.stderr});
 await fs.writeFile(path.join(work,'commands.json'),JSON.stringify(records,null,2));
 assert.equal(r.status,rc,r.stderr);return r;
}
const write=async(file,text)=>{await fs.mkdir(path.dirname(file),{recursive:true});await fs.writeFile(file,text);};
await write(path.join(repository,'runtime/CMakeLists.txt'),'# finite provenance fixture\n');
await write(path.join(repository,'runtime/src/mask.c'),'unsigned long g_cjLoadBadMask = 42;\n');
await write(path.join(repository,'runtime/build/cmake/GenerateRuntimeProvenance.cmake'),await fs.readFile(generator));
await run(['git','init',repository]);await run(['git','-C',repository,'add','.']);
await run(['git','-C',repository,'-c','user.name=Zxilly','-c','user.email=zxilly@outlook.com','commit','-m','finite runtime source fixture']);
const commit=(await run(['git','-C',repository,'rev-parse','HEAD'])).stdout.trim();
await run(['git','-C',repository,'archive','--output='+path.join(work,'source.tar'),commit]);
await fs.mkdir(materialized);await run(['tar','-xf',path.join(work,'source.tar'),'-C',materialized]);
const tuple='linux_x86_64_cjnative',shared='runtime/lib/'+tuple+'/libcangjie-runtime.so',archive='lib/'+tuple+'/libcangjie-runtime.a';
async function build(root,label){
 const out=path.join(work,label),install=path.join(out,'install');await fs.mkdir(out,{recursive:true});
 const sourceRoot=path.join(root,'runtime'),generated=path.join(out,'RuntimeProvenance.cpp');
 await run(['cmake','-DREPOSITORY_DIR='+root,'-DSOURCE_DIR='+sourceRoot,'-DOUTPUT_FILE='+generated,'-P',path.join(sourceRoot,'build/cmake/GenerateRuntimeProvenance.cmake')]);
 await run(['c++','-fPIC','-c',generated,'-o',path.join(out,'provenance.o')]);
 await run(['cc','-fPIC','-c',path.join(sourceRoot,'src/mask.c'),'-o',path.join(out,'mask.o')]);
 await fs.mkdir(path.dirname(path.join(install,shared)),{recursive:true});await fs.mkdir(path.dirname(path.join(install,archive)),{recursive:true});
 await run(['c++','-shared',path.join(out,'provenance.o'),path.join(out,'mask.o'),'-o',path.join(install,shared)]);
 await run(['ar','rcs',path.join(install,archive),path.join(out,'provenance.o'),path.join(out,'mask.o')]);
 return {kind:'runtime',repository,commit,sourceRoot,install,artifacts:[shared,archive],configuration:{fixture:'native generated provenance/mask only'},platform:'linux_x86_64',work:path.join(out,'check')};
}
const input=await build(materialized,'archive'),gitInput=await build(repository,'git');
const entry=new URL('../../ci/bootstrap/sdk-native-input-check.mjs',import.meta.url).pathname;
const check=(value,options)=>run([process.execPath,entry,JSON.stringify(value)],options);
if(process.env.CJCJ_OLD_SDK_ROOT){
 const old=path.join(process.env.CJCJ_OLD_SDK_ROOT,'ci/bootstrap/sdk-native-input-check.mjs');
 const r=await run([process.execPath,old,JSON.stringify({...input,work:path.join(work,'old-check')})],{rc:1});
 assert.match(r.stdout,/RUNTIME_PAIR_ASSERTION_REACHED/);assert.match(r.stderr,/RUNTIME_PAIR_SOURCE_STAMP/);
 await run([process.execPath,old,JSON.stringify({...gitInput,work:path.join(work,'old-git-check')})]);
}
await recordRuntimeInputs({...input,work:input.install});
await recordRuntimeInputs({...gitInput,work:gitInput.install});
await check(input);await check(gitInput);
await fs.copyFile(path.join(input.work,'RUNTIME-INPUTS.json'),path.join(input.install,'RUNTIME-INPUTS.json'));
const facts=JSON.parse(await fs.readFile(path.join(input.install,'RUNTIME-INPUTS.json')));
assert.equal(facts.source.commit,commit);assert.match(facts.embedded_stamp,/^CJRT-COMMIT:src-[0-9a-f]{64}$/);
assert.notEqual(facts.embedded_stamp,'CJRT-COMMIT:'+commit);
const binary=await fs.readFile(path.join(input.install,shared));assert.ok(binary.includes(Buffer.from('CJRT-DECLARED:'+'e'.repeat(40))));
assert.ok(contentSignals(binary).includes('CJRT-COMMIT'));
await runtimeInputsForArtifact(input.install,facts.artifacts[0],{repository,commit,stamp:facts.embedded_stamp});
const rows=[];
for(const spec of TOOLCHAIN_IDENTITY_ARTIFACTS){
 if(spec.optional)continue;
 const rel=spec.component==='runtime'?shared:'fixture/'+spec.name,stamp=spec.component==='runtime'?facts.embedded_stamp:spec.prefix+':'+commit;
 if(spec.component!=='runtime')await write(path.join(input.install,rel),'controlled other identity boundary\0'+stamp+'\0');
 rows.push({component:spec.component,source:{status:'resolved',repository,commit},artifact:{path:rel,sha256:await fileDigest(path.join(input.install,rel))},embedded_stamp:stamp,
 ...(spec.component==='runtime'?{build:facts.build}:{})});
}
await writeToolchainIdentity({stage:input.install,releaseRows:rows});
const collected=await installedInputs(input.install,'linux_x86_64');assert.equal(collected.components.find(x=>x.component==='runtime').embedded_stamp,facts.embedded_stamp);
const release=await writeInstalledReleaseManifest({stage:input.install,platform:'linux_x86_64',...collected});
const releaseRuntime=release.rows.find(row=>row.component==='runtime');
assert.equal(releaseRuntime.source.commit,commit);assert.equal(releaseRuntime.embedded_stamp,facts.embedded_stamp);
assert.equal(releaseRuntime.artifact.path,shared);assert.equal(releaseRuntime.artifacts.length,2);
const original=await fs.readFile(path.join(materialized,'runtime/src/mask.c'));
await fs.appendFile(path.join(materialized,'runtime/src/mask.c'),'// changed after build\n');
await recordRuntimeInputs({...input,work:path.join(work,'changed-producer')});
assert.deepEqual(JSON.parse(await fs.readFile(path.join(work,'changed-producer/RUNTIME-INPUTS.json'))),facts);
assert.equal('source_materialization' in facts.build,false,'record observes products, not a new source certification');
// Consumer reads retained production facts and bytes; the old source path is diagnostic only.
await check({...input,work:path.join(work,'changed-source-consumer')});
await check({...gitInput,work:path.join(work,'independent-git-control')});
await fs.writeFile(path.join(materialized,'runtime/src/mask.c'),original);await check({...input,work:path.join(work,'restored-check')});
const staticBytes=await fs.readFile(path.join(input.install,archive));await fs.appendFile(path.join(input.install,archive),'changed');
await assert.rejects(installedInputs(input.install,'linux_x86_64'),/RUNTIME_SOURCE_PAIR_BYTES/);
await fs.writeFile(path.join(input.install,archive),staticBytes);await installedInputs(input.install,'linux_x86_64');
await fs.writeFile(path.join(base,'archive-case.json'),JSON.stringify(input));
console.log('RUNTIME_ARCHIVE_BINDING_TARGET_REACHED '+JSON.stringify({work,commit,stamp:facts.embedded_stamp,generator:await fileDigest(generator),commands:records.length}));

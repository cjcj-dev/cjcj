#!/usr/bin/env zx
// Public source-build CLI with a controlled native tool producer. The small
// executable is real; this does not claim an LSP/C2/full SDK functional test.
import fs from 'node:fs/promises';
import path from 'node:path';
import assert from 'node:assert/strict';
import {spawnSync} from 'node:child_process';
import {fileDigest,archiveInstall} from '../../ci/bootstrap/sdk-flow.mjs';
import {buildConfig} from '../lib/config.mjs';
import {toolBuildInputs} from '../srcbuild/tool-build-inputs.mjs';
import {installSourceTools} from '../srcbuild/install-tools.mjs';
import {installHleDependencies} from '../srcbuild/hle-dependencies.mjs';
import {hlePayloadFixture} from './hle-payload-fixture.mjs';
import {installedInputs} from '../../ci/srcbuild/lib/installed-inputs.mjs';
import {writeInstalledReleaseManifest,verifyInstalledReleaseManifest} from '../lib/release-manifest.mjs';
const base=process.env.RELEASE_EVIDENCE_TEST_ROOT;
if(!base)throw new Error('tool facts integration needs evidence root');
const root=await fs.mkdtemp(path.join(base,'tool-facts-')),workspace=path.join(root,'workspace'),tools=path.join(workspace,'cjcj-tools'),sdk=path.join(root,'sdk');
const write=async(file,data)=>{await fs.mkdir(path.dirname(file),{recursive:true});await fs.writeFile(file,data);};
const records=[];
async function command(argv,options={}){
 const r=spawnSync(argv[0],argv.slice(1),{encoding:'utf8',maxBuffer:8*1024*1024,...options});
 records.push({argv,rc:r.status,signal:r.signal,stdout:r.stdout,stderr:r.stderr});await write(path.join(root,'commands.json'),JSON.stringify(records,null,2));
 return r;
}
async function git(...args){const r=await command(['git','-C',tools,...args]);assert.equal(r.status,0,r.stderr);return r.stdout.trim();}
await write(path.join(tools,'packages/lsp/main.c'),'#include <stdio.h>\nint main(void){puts("42");return 0;}\n');
await write(path.join(tools,'packages/lsp/build/build.mjs'),'throw Error("finite root producer owns this test");\n');
await write(path.join(tools,'build.mjs'),`import fs from 'node:fs';import path from 'node:path';import {spawnSync} from 'node:child_process';
const a=process.argv.slice(2),value=k=>a[a.indexOf(k)+1];if(a[0]!=='build'||value('--tool')!=='lsp')throw Error('fixture public argv');
const out=path.join(value('--build-root'),'lsp/server/target/release/bin/main');fs.mkdirSync(path.dirname(out),{recursive:true});
const r=spawnSync('cc',[new URL('./packages/lsp/main.c',import.meta.url).pathname,'-o',out],{stdio:'inherit'});fs.writeFileSync(path.join(value('--build-root'),'lsp/server-build-command.json'),JSON.stringify({rc:r.status,signal:r.signal,fixture:'bounded public producer; not actual LSP',argv:process.argv}));
if(r.error)throw r.error;process.exitCode=r.status??1;
`);
await git('init');await git('add','.');await git('-c','user.name=Zxilly','-c','user.email=zxilly@outlook.com','commit','-m','finite native tool source');
const commit=await git('rev-parse','HEAD'),repository='file://'+tools;
await git('remote','add','origin',repository);
await write(path.join(workspace,'.source-selection.json'),JSON.stringify({tools:{url:repository,tag:commit}}));
// Real native bytes stand in for unrelated SDK inputs. No Cangjie invocation
// or ABI assertion is performed by this bounded producer-record test.
for(const rel of ['bin/cjcj-stage1','lib/linux_x86_64_cjnative/libcangjie-std-core.a','runtime/lib/linux_x86_64_cjnative/libcangjie-runtime.so']){
 await fs.mkdir(path.dirname(path.join(sdk,rel)),{recursive:true});await fs.copyFile('/usr/bin/true',path.join(sdk,rel));
}
await write(path.join(sdk,'STAGE-INPUTS.json'),JSON.stringify({compilerFile:'bin/cjcj-stage1',compilerSha256:await fileDigest(path.join(sdk,'bin/cjcj-stage1')),fixture:'not a Cangjie SDK'}));
const env={...process.env,CJCJ_SRCBUILD_CONSUMER_SDK:sdk};
delete env.CANGJIE_BUILD_DRY_RUN;
if(!env.CJCJ_OFFICIAL_SDK_ROOT)throw new Error('tool facts integration requires the real plain host SDK loader input');
const cli=process.env.CJCJ_TOOL_FACTS_CLI||new URL('../cli.mjs',import.meta.url).pathname;
const args=[process.execPath,cli,'--workspace',workspace,'--build-root',path.join(root,'buildtools'),'--target','linux-x64','--host-profile','kkk2','--build-type','release','--tools-phase','build','--tools-build-set','lsp','--jobs','2','--tools-json-build','/fixture/json','--tools-compiler-libs','/fixture/frontend','--tools-runtime-config','/fixture/config.o','--tools-llvm-shim','/fixture/shim.o','--tools-llvm-library','/fixture/libLLVM.so','build','tools'];
const built=await command(args,{env});assert.equal(built.status,0,built.stderr);
console.log('PUBLIC_PRODUCER_OUTPUT_REACHED');
const record=path.join(workspace,'build/tools/lsp/build-inputs.json'),facts=JSON.parse(await fs.readFile(record,'utf8'));
assert.equal(facts.source.commit,commit);assert.equal(facts.source.repository,repository);assert.equal(facts.build.rc,0);
assert.equal(facts.build.argv[facts.build.argv.indexOf('--tool')+1],'lsp');assert.equal(facts.build.argv[facts.build.argv.indexOf('--jobs')+1],'2');
const product=path.join(root,'buildtools/lsp/server/target/release/bin/main');
assert.equal(facts.artifact.sha256,await fileDigest(product));
const value=await command([product]);assert.equal(value.status,0);assert.equal(value.stdout.trim(),'42');
const config=buildConfig({workspace,buildRoot:path.join(root,'buildtools'),targetKey:'linux-x64',buildType:'release'});
await toolBuildInputs(config,'lsp',product);
// An install-only invocation with a newer selected pin still describes the old
// producer. Neither its source nor its build configuration is overwritten.
await write(path.join(tools,'later-source'),'next object');await git('add','later-source');await git('-c','user.name=Zxilly','-c','user.email=zxilly@outlook.com','commit','-m','next source selection');
const later=await git('rev-parse','HEAD');assert.notEqual(later,commit);
const reused=await toolBuildInputs(config,'lsp',product);assert.equal(reused.source.commit,commit);
const bytes=await fs.readFile(product);await fs.appendFile(product,'changed');
await assert.rejects(toolBuildInputs(config,'lsp',product),/TOOL_BUILD_INPUT_MISMATCH/);
await fs.writeFile(product,bytes);assert.equal((await toolBuildInputs(config,'lsp',product)).source.commit,commit);
await fs.rename(record,record+'.original');
assert.equal((await toolBuildInputs(config,'lsp',product)).source.status,'unresolved');
await fs.rename(record+'.original',record);
if(process.env.CJCJ_TOOL_FACTS_INSTALL==='1'){
 await write(path.join(tools,'packages/lsp/dist/bin/cangjie-lsp'),await fs.readFile(product));
 await fs.chmod(path.join(tools,'packages/lsp/dist/bin/cangjie-lsp'),0o755);
 for(const rel of ['packages/lsp/dist/lib/libcangjie-runtime.so','packages/cjhead/dist/bin/cjhead','packages/cjhead/dist/lib/libcangjie-runtime.so','packages/cjhead/dist/share/README'])await write(path.join(tools,rel),'explicit unrelated fixture');
 await fs.copyFile('/usr/bin/true',path.join(tools,'packages/cjhead/dist/bin/cjhead'));
 await fs.chmod(path.join(tools,'packages/cjhead/dist/bin/cjhead'),0o755);
 await fs.mkdir(path.join(config.buildRoot,'hle/bin'),{recursive:true});await fs.copyFile('/usr/bin/true',path.join(config.buildRoot,'hle/bin/main'));
 // Carry the actual CLI-produced record and binary through the real installer.
 // Other tools/HLE payloads are explicitly controlled inputs, not six-tool PASS.
 for(const rel of ['packages/cjpm/dist/bin/cjpm','packages/cjfmt/dist/bin/cjfmt','packages/hle/target/bin/main',
   'packages/cjcov/dist/bin/cjcov','packages/cjtrace-recover/dist/bin/cjtrace-recover','packages/cjlint/dist/bin/cjlint','packages/cjprof/dist/bin/cjprof','packages/cjcompat/dist/bin/cjcompat']){
   await fs.mkdir(path.dirname(path.join(tools,rel)),{recursive:true});await fs.copyFile('/usr/bin/true',path.join(tools,rel));
 }
 for(const rel of ['packages/cjlint/dist/lib/libcangjie-runtime.so','packages/cjlint/dist/runtime/lib/linux_x86_64_cjnative/libcangjie-runtime.so','packages/cjlint/dist/modules/std.core.cjo','packages/cjlint/dist/config/cjlint_rule_list.json','packages/cjprof/dist/lib/libcjprof-cangjie.so','packages/cjprof/dist/lib/libcjprof-jni.so','packages/cjprof/dist/share/java/cjprof.jar','packages/cjprof/dist/config/static/index.html'])await write(path.join(tools,rel),'explicit unrelated payload fixture');
 await write(path.join(tools,'packages/cjfmt/dist/config/cangjie-format.toml'),'fixture formatter configuration');
 await write(path.join(tools,'packages/cjpm/dist/config/cangjie-repo.toml'),'fixture repository configuration');
 const parser=path.join(tools,'packages/hle/src/dtsparser');
 await write(path.join(parser,'analysis.js'),'// controlled parser boundary');
 await write(path.join(parser,'package.json'),JSON.stringify({dependencies:{typescript:'npm:typescript@4.9.5','https-proxy-agent':'7.0.6'}}));
 const deps=path.join(root,'dependencies');hlePayloadFixture(deps);
 await installHleDependencies({toolsRoot:tools,sdk,platform:'linux_x86_64',input:{platform:'linux_x86_64',
  node:{path:'/usr/bin/true',source:'native executable format fixture; not Node behavior',version:'fixture'},
  modules:{path:path.join(deps,'tools/dtsparser/node_modules'),source:'controlled npm boundary',version:'fixture'},
  cjbind:{path:'/usr/bin/true',source:'native executable format fixture; not cjbind behavior',version:'v1.1.0-alpha.53.1'}}});
 await installSourceTools(config,sdk,{consume:async pending=>{const actual=await command([path.join(pending,'tools/bin/LSPServer')]);assert.equal(actual.status,0,actual.stderr);assert.equal(actual.stdout.trim(),'42');}});
 // Unrelated SDK-shaped inputs above do not claim compiler provenance. Retain
 // that explicit unresolved boundary in the package facts test.
 await fs.rename(path.join(sdk,'STAGE-INPUTS.json'),path.join(root,'controlled-sdk-input.json'));
 const gathered=await installedInputs(sdk,'linux_x86_64'),lsp=gathered.components.find(row=>row.component==='LSPServer');
 for(const name of ['cjpm','cjfmt','hle','LSPServer','cjcov','cjtrace-recover','cjlint','cjprof','cjcompat','cjhead'])
   assert(gathered.components.some(row=>row.component===name),'installed component '+name);
 for(const [name,directory]of [['LSPServer','lsp'],['cjlint','cjlint'],['cjhead','cjhead']]){
   const actual=path.join(sdk,'.target-tools/tools',directory,'bin',name),held=actual+'.held';
   assert.equal(gathered.components.find(row=>row.component===name).artifact.path,'.target-tools/tools/'+directory+'/bin/'+name);
   const legacy=path.join(sdk,'.target-tools/tools/bin',name);
   await fs.mkdir(path.dirname(legacy),{recursive:true});await fs.copyFile(actual,legacy);
   await fs.rename(actual,held);
   try{
     await assert.rejects(installedInputs(sdk,'linux_x86_64'),error=>error.code==='ENOENT'&&error.path===actual);
     if(name!=='LSPServer'){
       const control=await command([path.join(sdk,'tools/bin/LSPServer')]);
       assert.equal(control.status,0);assert.equal(control.stdout.trim(),'42');
     }
   }finally{await fs.rename(held,actual);}
   assert.equal((await installedInputs(sdk,'linux_x86_64')).components.find(row=>row.component===name).artifact.path,'.target-tools/tools/'+directory+'/bin/'+name);
 }
 assert.equal(lsp.source.commit,commit);assert.equal(lsp.artifact.sha256,facts.artifact.sha256);
 assert.equal(gathered.components.find(row=>row.component==='hle').source.status,'unresolved');
 const manifest=await writeInstalledReleaseManifest({stage:sdk,platform:'linux_x86_64',...gathered});
 const manifestLsp=manifest.rows.find(row=>row.component==='tool-LSPServer');
 assert.equal(manifestLsp.source.commit,commit);assert.deepEqual(manifestLsp.artifact,lsp.artifact);
 await assert.rejects(verifyInstalledReleaseManifest({stage:sdk,platform:'linux_x86_64',...gathered}),/source.status is unresolved/);
 const retained=path.join(sdk,lsp.artifact.path),retainedBytes=await fs.readFile(retained);
 await fs.appendFile(retained,'cut');await assert.rejects(installedInputs(sdk,'linux_x86_64'),/INSTALLED_INPUT_BYTES/);
 await fs.writeFile(retained,retainedBytes);await installedInputs(sdk,'linux_x86_64');
 const checker=path.join(root,'unpacked.mjs');
 await write(checker,`import {installedInputs} from ${JSON.stringify(new URL('../../ci/srcbuild/lib/installed-inputs.mjs',import.meta.url).href)};\nimport assert from 'node:assert/strict';\nimport fs from 'node:fs/promises';\nimport {spawnSync} from 'node:child_process';\nconst root=process.argv[2],row=(await installedInputs(root,'linux_x86_64')).components.find(x=>x.component==='LSPServer');\nassert.equal(row.source.commit,${JSON.stringify(commit)});const release=(await fs.readFile(root+'/RELEASE-MANIFEST.jsonl','utf8')).trim().split('\\n').map(x=>JSON.parse(x)).find(x=>x.component==='tool-LSPServer');assert.equal(release.source.commit,row.source.commit);assert.deepEqual(release.artifact,row.artifact);const r=spawnSync(root+'/tools/bin/LSPServer',[],{encoding:'utf8'});assert.equal(r.status,0,r.stderr);assert.equal(r.stdout.trim(),'42');console.log('UNPACKED_TOOL_FACTS_REACHED');\n`);
 await fs.rename(tools,tools+'.parked');
 try{
   await archiveInstall({install:sdk,archive:path.join(root,'tools-interface.tar.gz'),format:'tar.gz',
    test:{commands:[{argv:[process.execPath,checker,'${install}']}]},vars:{work:root},records:[]});
 }finally{await fs.rename(tools+'.parked',tools);}
 console.log('INSTALLED_ARCHIVED_TOOL_FACTS_TARGET_REACHED');
}
console.log('PUBLIC_TOOL_BUILD_FACTS_TARGET_REACHED '+JSON.stringify({root,commit,later,artifact:facts.artifact}));

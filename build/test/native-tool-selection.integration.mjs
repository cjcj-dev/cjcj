#!/usr/bin/env zx
// A small native producer and real install/entry/reader chain. The C program
// is an interface fixture, never a qualified LSP or Cangjie SDK.
import fs from 'node:fs/promises';
import path from 'node:path';
import {fileURLToPath} from 'node:url';
import {spawnSync} from 'node:child_process';
import assert from 'node:assert/strict';
import {getTarget} from '../lib/targets.mjs';
import {beginToolBuild,finishToolBuild,finishToolInstall} from '../srcbuild/tool-build-inputs.mjs';
import {installSourceTools} from '../srcbuild/install-tools.mjs';
import {toolOutputs} from '../srcbuild/tool-layout.mjs';
const parent=process.env.RELEASE_EVIDENCE_TEST_ROOT;
if(!parent)throw Error('RELEASE_EVIDENCE_TEST_ROOT required');
const work=await fs.mkdtemp(path.join(parent,'native-selection-'));
const workspace=path.join(work,'workspace'),tools=path.join(workspace,'tools'),sdk=path.join(work,'sdk'),records=[];
const write=async(file,data)=>{await fs.mkdir(path.dirname(file),{recursive:true});await fs.writeFile(file,data);};
const json=async file=>JSON.parse(await fs.readFile(file,'utf8'));
async function run(label,argv,cwd=work) {
 const r=spawnSync(argv[0],argv.slice(1),{cwd,env:process.env,encoding:'utf8',maxBuffer:1024*1024});
 records.push({label,argv,cwd,pid:r.pid,rc:r.status,signal:r.signal,error:r.error?.message});
 await write(path.join(work,label+'.stdout'),r.stdout??'');await write(path.join(work,label+'.stderr'),r.stderr??'');
 await write(path.join(work,'commands.json'),JSON.stringify(records,null,2));assert.equal(r.status,0,label+': '+r.stderr);return r.stdout;
}
const config={workspace,softwareDir:work,buildRoot:path.join(work,'buildtools'),buildType:'release',cangjieVersion:'fixture',toolsPhase:'install',
 target:getTarget('linux-x64'),repoPath:()=>tools,repo:()=>({url:'file://'+tools})};
const stage={platform:'linux_x86_64',compilerFile:'bin/cjcj-stage1',compilerCommit:'1'.repeat(40),runtimeCommit:'2'.repeat(40),fixture:'not a Cangjie SDK'};
const sdkFiles={compiler:'bin/cjcj-stage1',stdCore:'lib/linux_x86_64_cjnative/libcangjie-std-core.a',runtime:'runtime/lib/linux_x86_64_cjnative/libcangjie-runtime.so',nativeAst:'tools/lib/libcangjie-lsp.so'};
for(const [key,rel]of Object.entries(sdkFiles))await write(path.join(sdk,rel),'original '+key);
await write(path.join(sdk,'STAGE-INPUTS.json'),JSON.stringify(stage));
await write(path.join(tools,'packages/lsp/main.c'),'#include <stdio.h>\nint main(void){puts("native fixture:42");return 0;}\n');
await run('git-init',['git','init','-q',tools]);
await run('git-add',['git','add','.'],tools);
await run('git-commit',['git','-c','user.name=Zxilly','-c','user.email=zxilly@outlook.com','commit','-qm','native interface fixture'],tools);
const product=path.join(tools,'packages/lsp/dist/bin/cangjie-lsp');await fs.mkdir(path.dirname(product),{recursive:true});
const argv=['cc',path.join(tools,'packages/lsp/main.c'),'-o',product];
const before=await beginToolBuild(config,'lsp',{argv,env:{CANGJIE_HOME:sdk},sdk});
await run('native-build',argv);await finishToolBuild(config,'lsp',before,product);
await finishToolInstall(config,'lsp',product,['upstream LSP output install (same directory)']);
const original=await json(path.join(workspace,'build/tools/lsp/build-inputs.json'));
for(const row of toolOutputs(config))if(row.producer!=='lsp') {
 await fs.mkdir(path.dirname(row.from),{recursive:true});await fs.copyFile(product,row.from);
}
for(const rel of ['packages/cjpm/dist/config/cangjie-repo.toml','packages/cjfmt/dist/config/cangjie-format.toml',"packages/lsp/dist/lib/libcangjie-runtime.so","packages/cjhead/dist/lib/libcangjie-runtime.so","packages/cjhead/dist/share/readme","packages/cjlint/dist/lib/libcangjie-runtime.so","packages/cjlint/dist/runtime/lib/linux_x86_64_cjnative/libcangjie-runtime.so","packages/cjlint/dist/modules/std.core.cjo","packages/cjlint/dist/config/cjlint_rule_list.json",
 'packages/cjprof/dist/lib/libcjprof-cangjie.so','packages/cjprof/dist/lib/libcjprof-jni.so','packages/cjprof/dist/share/java/cjprof.jar','packages/cjprof/dist/config/static/index.html'])await write(path.join(tools,rel),'unqualified other-tool fixture');
for(const rel of ['tools/dtsparser/DEPENDENCIES.json','tools/bin/node','tools/dtsparser/node_modules/.bin/cjbind'])await write(path.join(sdk,rel),'unqualified HLE fixture');
const cli=fileURLToPath(new URL('../../ci/cangjie-test/tool-readiness.mjs',import.meta.url));
const read=async label=>JSON.parse(await run(label,[process.execPath,cli,sdk]));
await installSourceTools(config,sdk,{consume:async pending=>assert.equal((await run('pending-consumer-'+records.length,[path.join(pending,'tools/bin/LSPServer')])).trim(),'native fixture:42')});
let observed=await read('same-build');assert.equal(observed.LSPServer.ready,true,observed.LSPServer.reason);
assert.equal(observed.cjpm.ready,false,'unresolved CJ producer independent control');
console.log('UNRESOLVED_CJ_INDEPENDENT_CONTROL_PASS');
const current={...stage,compilerCommit:'3'.repeat(40),runtimeCommit:'4'.repeat(40)};
await write(path.join(sdk,'STAGE-INPUTS.json'),JSON.stringify(current));
for(const key of ['compiler','stdCore','runtime'])await write(path.join(sdk,sdkFiles[key]),'new '+key);
await installSourceTools(config,sdk);
let facts=await json(path.join(sdk,'TOOLS-INPUTS.json'));
console.log('NORMAL_INSTALL_SELECTION_ASSERTION_REACHED');
assert.deepEqual(facts.files['tools/bin/LSPServer'].producer,original,'original build/install facts unchanged');
assert.deepEqual(facts.installationInputs?.stage,current,'normal installer records destination separately');
observed=await read('new-selection');
assert.equal(observed.LSPServer.available,true,observed.LSPServer.reason);
assert.equal(observed.LSPServer.ready,false,'install is not a macro/runtime consumer');
assert.equal(observed.LSPServer.applicability.status,'NOT_CONSUMED');
assert.deepEqual(observed.LSPServer.applicability.changedRuntimeInputs,['compiler','stdCore','runtime']);
assert.equal(observed.cjpm.ready,false,'unresolved CJ producer remains rejected');
await write(path.join(sdk,'STAGE-INPUTS.json'),JSON.stringify({...current,runtimeCommit:'5'.repeat(40)}));
observed=await read('wrong-runtime-selection');
assert.equal(observed.LSPServer.ready,false);assert.equal(observed.LSPServer.available,false);
assert.match(observed.LSPServer.reason,/installed SDK selection differs: runtimeCommit/);
await write(path.join(sdk,'STAGE-INPUTS.json'),JSON.stringify(current));
assert.equal((await run('public-native-entry',[path.join(sdk,'tools/bin/LSPServer')])).trim(),'native fixture:42');
assert.equal((await read('ordinary-execution-not-macro')).LSPServer.ready,false,'ordinary native execution cannot qualify macro/runtime edges');
// The actual SDK graph must be able to execute the current business command
// after installation admission. NOT_CONSUMED is not a circular prerequisite.
const consumer=path.join(work,'consume.mjs');
await write(consumer,`import {toolReadiness} from ${JSON.stringify(new URL('../../ci/cangjie-test/tool-readiness.mjs',import.meta.url).href)};
import assert from 'node:assert/strict';import {spawnSync} from 'node:child_process';
const sdk=process.argv[2],r=(await toolReadiness(sdk)).LSPServer;
assert.equal(r.available,true,r.reason);assert.equal(r.ready,false);
const p=spawnSync(sdk+'/tools/bin/LSPServer',[],{encoding:'utf8'});
console.log('PUBLIC_CURRENT_CONSUMER_TARGET',JSON.stringify({rc:p.status,signal:p.signal,stdout:p.stdout}));
assert.equal(p.status,0);assert.equal(p.stdout.trim(),'native fixture:42');
`);
const graph={work:path.join(work,'flow'),install:sdk,platform:'linux_x86_64',repos:{},
 stages:[{id:'existing-installation',output:sdk}],finalStage:'existing-installation',
 test:{required:['TOOLS-INPUTS.json'],commands:[{argv:[process.execPath,consumer,'${install}']}]}};
await write(path.join(work,'graph.json'),JSON.stringify(graph));
const sdkBuild=fileURLToPath(new URL('../../ci/bootstrap/sdk-build.mjs',import.meta.url));
await run('public-sdk-consume',[process.execPath,sdkBuild,'--config',path.join(work,'graph.json'),'--no-package']);
assert.equal((await read('after-public-consume')).LSPServer.ready,false,'ordinary fixture command is not full macro qualification');
for(const key of ['nativeAst','runtime']) {
 const file=path.join(sdk,sdkFiles[key]),bytes=await fs.readFile(file);await fs.writeFile(file,'wrong actual dependency');
 try {const bad=await read('bad-'+key);assert.equal(bad.LSPServer.available,false);assert.equal(bad.LSPServer.ready,false);assert.match(bad.LSPServer.reason,/installed bytes differ/);}
 finally {await fs.writeFile(file,bytes);}
}
const moved=sdk+'-moved';await fs.rename(sdk,moved);
try {
 const r=JSON.parse(await run('relocated',[process.execPath,cli,moved]));
 assert.equal(r.LSPServer.available,true);assert.equal(r.LSPServer.ready,false);
}finally {await fs.rename(moved,sdk);}
await installSourceTools(config,sdk);
assert.equal((await read('reinstalled')).LSPServer.available,true);
assert.deepEqual((await json(path.join(sdk,'TOOLS-INPUTS.json'))).files['tools/bin/LSPServer'].producer,original);
console.log('NATIVE_SELECTION_FINITE_PASS '+work);

#!/usr/bin/env zx
// Nine small source-built Cangjie products exercise the SDK tool installer.
// These are interface fixtures, not the complete fixed cangjie_tools programs.
import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs/promises';
import path from 'node:path';
import {spawnSync} from 'node:child_process';
import {hlePayloadFixture} from './hle-payload-fixture.mjs';
import {installSourceTools} from '../srcbuild/install-tools.mjs';
import {installEntries} from '../../ci/bootstrap/sdk-install-entries.mjs';
import {copyOutputs,fileDigest} from '../../ci/bootstrap/sdk-flow.mjs';
import {sdkEnvironment} from '../../ci/bootstrap/sdk-platform.mjs';
import {getTarget} from '../lib/targets.mjs';
import {collectContentFindings,listPackagedArtifacts,PACKAGED_TOOL_NAMES} from '../lib/package-lineage.mjs';
const inputs=JSON.parse(await fs.readFile(process.env.SDK_MIGRATION_INPUTS,'utf8'));
await fs.mkdir(inputs.work,{recursive:true});
const root=await fs.mkdtemp(path.join(inputs.work,'source-tools-')),sdk=path.join(root,'software/cangjie'),source=path.join(root,'tools');
await copyOutputs(sdk,[{from:inputs.host,to:'',exclude:['.cjv'],owner:'reference H'}]);
await installEntries({root:sdk,build:path.join(root,'host-entry'),groups:[{directory:'tools/bin',retain:'.host-tools/tools/bin',
 names:['cjpm','cjfmt','hle','LSPServer','cjcov','cjtrace-recover','cjlint','cjprof','cjcompat'],libraries:['runtime/lib/linux_x86_64_cjnative','lib/linux_x86_64_cjnative','third_party/llvm/lib','tools/lib']}],records:[],platform:'linux_x86_64'});
const products=[['cjpm','cjpm/dist/cjpm'],['cjfmt','cjfmt/dist/bin/cjfmt'],['hle','hyperlangExtension/target/bin/main'],
 ['LSPServer','cangjie-language-server/output/bin/LSPServer'],['cjcov','cjcov/dist/cjcov'],['cjtrace-recover','cjtrace-recover/dist/bin/cjtrace-recover'],['cjlint','cjlint/dist/bin/cjlint'],['cjprof','cjprof/dist/bin/cjprof'],['cjcompat','cjcompat/dist/bin/cjcompat']];
const expected={};
for(const [name,rel]of products){
 const output=path.join(source,rel),input=path.join(root,name+'.cj');await fs.mkdir(path.dirname(output),{recursive:true});
 await fs.writeFile(input,`main() { println("${name}:42") }\n`);
 const result=spawnSync(path.join(inputs.host,'bin/cjc'),[input,'-o',output],{encoding:'utf8',env:sdkEnvironment(inputs.host,'linux_x86_64')});
 console.log('SOURCE_TOOL_FIXTURE_BUILD '+JSON.stringify({name,argv:[input,'-o',output],rc:result.status,stderr:result.stderr}));
 assert.equal(result.status,0,result.stderr);expected[name]=await fileDigest(output);
}
await fs.mkdir(path.join(source,'cjfmt/dist/config'),{recursive:true});await fs.writeFile(path.join(source,'cjfmt/dist/config/cangjie-format.toml'),'native = true\n');
await fs.mkdir(path.join(source,'hyperlangExtension/src/dtsparser'),{recursive:true});await fs.writeFile(path.join(source,'hyperlangExtension/src/dtsparser/index.js'),'export const installed = true;\n');
await fs.writeFile(path.join(source,'hyperlangExtension/src/dtsparser/source.cj'),'fixture source excluded from SDK\n');
// Payload-copy boundaries only: these markers are never loaded as libraries
// and cannot qualify native/JNI products. The nine actual fixture executables
// above still exercise the public installed launcher and lineage rejection.
for(const rel of ['cjpm/dist/cangjie-repo.toml','cjlint/dist/lib/libcjlint.so','cjlint/dist/config/cjlint_rule_list.json','cjprof/dist/lib/libcjprof.so','cjprof/dist/lib/libcjprof-jni.so','cjprof/dist/config/static/index.html']) {
 const file=path.join(source,rel);await fs.mkdir(path.dirname(file),{recursive:true});await fs.writeFile(file,'controlled transport boundary '+rel);
}
hlePayloadFixture(sdk);
await fs.writeFile(path.join(sdk,'tools/dtsparser/DEPENDENCIES.json'),JSON.stringify({fixture:'unqualified transport inputs'}));
const config={workspace:root,softwareDir:path.join(root,'software'),repoPath:()=>source,target:getTarget('linux-x64')};
await installSourceTools(config);
for(const [name]of products)test('source-built '+name+' is the installed public tool result',async()=>{
 const binary=path.join(sdk,'tools/bin',name),result=spawnSync(binary,[],{encoding:'utf8'});
 console.log('SOURCE_TOOL_RESULT_TARGET_ASSERTION_REACHED '+JSON.stringify({name,rc:result.status,stdout:result.stdout}));
 assert.equal(result.status,0,result.stderr);assert.equal(result.stdout.trim(),name+':42');
 const raw=path.join(sdk,'.target-tools/tools/bin',name);
 assert.equal(await fileDigest(raw),expected[name],'installed product retains actual independently captured build bytes');
});
test('lineage reads actual source-built tool bytes and still rejects unstamped interface fixtures',async()=>{
 const files=await listPackagedArtifacts(sdk);
 for(const name of PACKAGED_TOOL_NAMES)assert.ok(files.includes(path.join(sdk,'.target-tools/tools/bin',name)),'lineage must consume retained product '+name);
 // These three fixtures are CJ stand-ins for native C++ producers. Their actual
 // source/install qualification belongs to the nine-tool reader, not CJ dye.
 // The preceding nine real launcher tests still check every transported body.
 const findings=await collectContentFindings(sdk,new Set());
 const toolFindings=findings.filter(row=>row.file.includes('/.target-tools/tools/bin/'));
 console.log('SOURCE_TOOL_DYE_TARGET_ASSERTION_REACHED '+JSON.stringify(toolFindings));
 assert.equal(toolFindings.length,PACKAGED_TOOL_NAMES.length,'unstamped CJ fixture products must not become qualified by a launcher');
 for(const row of toolFindings)assert.ok(row.reasons.some(reason=>reason.includes('missing rebuilt dye')));
});

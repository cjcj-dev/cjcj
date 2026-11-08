// Finite public deploy -> native H1 contract regression; no SDK qualification.
import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import {spawnSync} from 'node:child_process';
import {createHash} from 'node:crypto';
const parent=process.env.SDK_H1_TEST_ROOT;
assert(parent,'SDK_H1_TEST_ROOT required');
const stage=path.resolve('ci/bootstrap/sdk-native-stage.mjs');
const deploy=path.resolve('ci/bootstrap/deploy-native-tools.mjs');
test('public Linux H1 uses deployed shell contract, host domain and restores temporary source edits',()=>{
 fs.mkdirSync(parent,{recursive:true});const root=fs.mkdtempSync(path.join(parent,'h1-'));
 const write=(file,text)=>{fs.mkdirSync(path.dirname(file),{recursive:true});fs.writeFileSync(file,text);};
 const run=(name,argv,env=process.env)=>{
  const result=spawnSync(argv[0],argv.slice(1),{env,encoding:'utf8'});
  write(root+'/'+name+'.stdout',result.stdout||'');write(root+'/'+name+'.stderr',result.stderr||'');
  write(root+'/'+name+'.json',JSON.stringify({argv,rc:result.status,signal:result.signal}));return result;
 };
 const ok=(name,argv)=>{const r=run(name,argv);assert.equal(r.status,0,r.stdout+r.stderr);return r.stdout.trim();};
 const commit=(dir,name)=>{ok(name+'-init',['git','init','-q',dir]);ok(name+'-add',['git','-C',dir,'add','.']);
  ok(name+'-commit',['git','-C',dir,'-c','user.name=Zxilly','-c','user.email=zxilly@outlook.com','commit','-qm','Finite H1 CLI regression']);
  return ok(name+'-head',['git','-C',dir,'rev-parse','HEAD']);};
 const source=root+'/source',tools=root+'/tools',host=root+'/host',sdk=root+'/native';
 const before='[package]\ncompile-option = "-O0"\n';write(source+'/cjpm.toml',before);
 const sourceCommit=commit(source,'source');
 write(tools+'/ts/src/sharedbuild/cjcj-stage1.sh',`#!/usr/bin/env bash
set -euo pipefail
node --input-type=module <<'NODE'
import fs from 'node:fs';import path from 'node:path';
const e=process.env;
fs.writeFileSync(path.join(e.SB_SOURCE,'cjpm.toml'),'temporary producer compile option');
console.log('H1_SHELL_PRODUCER_REACHED');
if(e.H1_FIXTURE_FAIL==='1')process.exit(17);
fs.writeFileSync(path.join(e.SB_OUTPUT,'cjcj-stage1'),'finite product, not a compiler');
fs.mkdirSync(path.join(e.SB_OUTPUT,'release'));
fs.writeFileSync(path.join(e.SB_OUTPUT,'contract.json'),JSON.stringify({env:e,parameters:JSON.parse(fs.readFileSync(e.SB_PARAMETERS)),shim:fs.readFileSync(path.join(e.SB_INPUTS,'llvm-shim.o'),'utf8')}));
NODE
`);
 const toolsCommit=commit(tools,'tools'),privateTools=root+'/private';
 ok('deploy',[process.execPath,deploy,tools,toolsCommit,privateTools]);
 const deployed=JSON.parse(fs.readFileSync(privateTools+'/BUILD-INPUTS.json'));
 assert.equal(deployed.commit,toolsCommit);assert.deepEqual(Object.keys(deployed.files),['ts/src/sharedbuild/cjcj-stage1.sh']);
 const object='third_party/llvm/fixed-llc/cjselfhost_llvmshim.o',bytes='finite selected N shim';write(sdk+'/'+object,bytes);
 const hash=text=>createHash('sha256').update(text).digest('hex');
 const nativeShim={source:{commit:sourceCommit},compiler:{commit:'a'.repeat(40)},llvm:{commit:'b'.repeat(40)},object:{path:object,bytes:Buffer.byteLength(bytes),sha256:hash(bytes)}};
 write(sdk+'/BUILD-INPUTS.json',JSON.stringify({commits:{shim:sourceCommit,compiler:'a'.repeat(40),llvm:'b'.repeat(40)},nativeShim}));
 const argv=output=>[process.execPath,stage,'--kind','h1','--source',source,'--commit',sourceCommit,'--sdk',sdk,'--runtime',root+'/runtime','--host',host,'--private-tools',privateTools,'--output',output,'--platform','linux_x86_64','--jobs','1','--heap','1GB'];
 const output=root+'/output',r=run('h1',argv(output));assert.equal(r.status,0,r.stdout+r.stderr);
 const contract=JSON.parse(fs.readFileSync(output+'.h1/out/contract.json'));
 assert.equal(contract.env.CANGJIE_HOME,host,'H1_MUST_EXECUTE_IN_HOST_DOMAIN');
 assert.ok(contract.env.PATH.startsWith(host+'/bin:'+host+'/tools/bin:'+host+'/third_party/llvm/bin:'));
 assert.ok(contract.env.LD_LIBRARY_PATH.startsWith(host+'/runtime/lib/linux_x86_64_cjnative:'));
 assert.equal(contract.env.CANGJIE_BUILD_JOBS,'1');assert.equal(contract.env.SB_SHA,sourceCommit);assert.equal(contract.env.SB_OPTIMIZATION,'O1');
 assert.equal(contract.env.SB_NATIVE_ROOT,undefined);assert.equal(contract.env.SB_PARAMETERS_JSON,undefined);
 assert.deepEqual(contract.parameters,{compile_flags:''});assert.equal(contract.shim,bytes,'H1_MUST_CONSUME_SELECTED_NATIVE_SHIM');
 assert.equal(fs.readFileSync(output+'/bin/cjcj-stage1','utf8'),'finite product, not a compiler');
 assert.equal(fs.existsSync(output+'/bin/release'),false);assert.equal(fs.readFileSync(source+'/cjpm.toml','utf8'),before);
 const commands=JSON.parse(fs.readFileSync(output+'.commands.json'));assert.equal(commands.length,1);assert.equal(commands[0].rc,0);
 assert.deepEqual(commands[0].argv,['bash',privateTools+'/ts/src/sharedbuild/cjcj-stage1.sh']);
 const facts=JSON.parse(fs.readFileSync(output+'/bin/build-inputs.json'));assert.equal(facts.source,sourceCommit);assert.equal(facts.native,sdk);assert.equal(facts.host,host);assert.deepEqual(facts.nativeShim,nativeShim);assert.equal(facts.sha256,hash('finite product, not a compiler'));
 assert.equal(facts.sourceChanges['cjpm.toml'].beforeSha256,hash(before));
 const failed=run('h1-failed',argv(root+'/failed'),{...process.env,H1_FIXTURE_FAIL:'1'});
 assert.equal(failed.status,17,failed.stdout+failed.stderr);assert.match(failed.stdout,/H1_SHELL_PRODUCER_REACHED/);
 assert.equal(fs.readFileSync(source+'/cjpm.toml','utf8'),before,'H1_SOURCE_MUST_RESTORE_AFTER_FAILURE');
 assert.equal(JSON.parse(fs.readFileSync(root+'/failed.commands.json'))[0].rc,17);
 console.log('H1_PUBLIC_SHELL_CONTRACT_AND_RESTORATION_REACHED');
});

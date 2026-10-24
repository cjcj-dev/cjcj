#!/usr/bin/env zx
// Cold formal bootstrap entry. Requires actual host/tuple inputs plus reachable
// Cjo header sources; this test does not manufacture SDKs or source identities.
import fs from 'node:fs';
import path from 'node:path';
import assert from 'node:assert/strict';
import {spawnSync} from 'node:child_process';
const repo=path.resolve(import.meta.dirname,'../..');
const work=path.resolve(process.argv[2]||'');
if(!process.argv[2]||fs.existsSync(work))throw Error('new private work directory required');
fs.mkdirSync(work,{recursive:true});
const cpp=path.join(work,'bootstrap-inputs/cjo-shim-headers'),consumer=path.join(work,'consumer');
fs.mkdirSync(consumer);
fs.cpSync(path.join(repo,'runtime_shim'),path.join(consumer,'runtime_shim'),{recursive:true,
 filter:file=>!file.endsWith('.o')});
const env={...process.env,CJCJ_BOOTSTRAP_INPUTS_WORK:path.join(work,'bootstrap-inputs'),
 GITHUB_ENV:path.join(work,'bootstrap.env'),CJCJ_COMMIT:spawnSync('git',['-C',repo,'rev-parse','HEAD'],{encoding:'utf8'}).stdout.trim()};
env.CJCJ_BOOTSTRAP_CJCJ_SHA=env.CJCJ_COMMIT;
for(const name of ['CJCJ_BOOTSTRAP_CPP_SRC','CANGJIE_CPP_SRC','CJCJ_LLVM_SHIM_O'])delete env[name];
const records=[];
function run(label,argv,extra={}) {
 const r=spawnSync(argv[0],argv.slice(1),{cwd:repo,env:{...env,...extra},encoding:'utf8'});
 fs.writeFileSync(path.join(work,label+'.log'),r.stdout+r.stderr);
 records.push({label,argv,rc:r.status,signal:r.signal});fs.writeFileSync(path.join(work,'commands.json'),JSON.stringify(records,null,2));
 return r;
}
const shim=['npx','--yes','zx@8',path.join(consumer,'runtime_shim/build_shim.mjs')];
const before=run('before',shim,{CANGJIE_CPP_SRC:cpp});assert.notEqual(before.status,0);
assert.match(before.stderr,/selected shim header directory missing/);
const prepared=run('prepare',[process.execPath,path.join(repo,'ci/release/prepare_bootstrap_inputs.mjs')]);
assert.equal(prepared.status,0,prepared.stderr);
assert.ok(fs.readFileSync(env.GITHUB_ENV,'utf8').split('\n').includes('CJCJ_BOOTSTRAP_CPP_SRC='+cpp));
const built=run('after',shim,{CANGJIE_CPP_SRC:cpp});assert.equal(built.status,0,built.stderr);
const symbols=run('symbols',['nm','--defined-only',path.join(consumer,'runtime_shim/cjselfhost_llvmshim.o')]);
assert.equal(symbols.status,0);assert.match(symbols.stdout,/\bLLVMGlobalObjectAddStringAttribute$/m);
console.log('COLD_SHIM_TEST_PASS work='+work);

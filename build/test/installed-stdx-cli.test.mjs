import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import {spawnSync} from 'node:child_process';
import {fixture} from './fixtures/stdx-native.mjs';
const cli=path.resolve(import.meta.dirname,'../cli.mjs');
const tuple='linux_x86_64_cjnative';
function write(file,text,mode=0o644){fs.mkdirSync(path.dirname(file),{recursive:true});fs.writeFileSync(file,text,{mode});}
function run(cmd,args,options={}){const r=spawnSync(cmd,args,{encoding:'utf8',...options});assert.equal(r.status,0,r.stdout+'\n'+r.stderr);return r;}

test('public stdx entry installs into SDK and the next public build consumes that installation', t=>{
 const {root,sdk,stdx,env,args:base}=fixture(t);
 const args=[...base,'build','stdx'];
 run(process.execPath,args,{env});
 console.log('STDX_INSTALL_ASSERT_REACHED');
 for(const kind of ['static','dynamic']) {
  const installed=path.join(sdk,'stdx',tuple,kind,'stdx/stdx.base.cjo');
  assert.ok(fs.existsSync(installed), 'public native install must create SDK stdx payload');
  assert.equal(fs.readFileSync(installed,'utf8'),'from native install');
 }
 // An unrelated old producer output must not be selected by the public build.
 write(path.join(stdx,'target',tuple,'static/stdx/stdx.base.cjo'),'old producer');
 run(process.execPath,args,{env});
 console.log('STDX_CONSUMER_ASSERT_REACHED');
 const selected=fs.readFileSync(path.join(root,'consumer.jsonl'),'utf8').trim().split('\n').map(JSON.parse);
 assert.equal(selected[0],'');assert.equal(selected[1],path.join(sdk,'stdx',tuple,'static/stdx'));
});

test('public package entry rejects missing installed full stdx before creating an archive', t=>{
 const root=fs.mkdtempSync(path.join(os.tmpdir(),'missing-stdx-'));t.after(()=>fs.rmSync(root,{recursive:true,force:true}));
 const sdk=path.join(root,'sdk');fs.mkdirSync(sdk);
 const r=spawnSync(process.execPath,[cli,'--workspace',root,'--build-root',root,'--host-profile','kkk2','package'],
  {encoding:'utf8',env:{...process.env,CJCJ_SRCBUILD_CONSUMER_SDK:sdk}});
 assert.notEqual(r.status,0);assert.match(r.stderr,/package.stdx/);
 assert.equal(fs.existsSync(path.join(root,'software')),true);
 assert.equal(fs.readdirSync(path.join(root,'software')).length,0);
});

test('public Windows cross stdx entry sends installation to the target SDK', t=>{
 const root=fs.mkdtempSync(path.join(os.tmpdir(),'windows-stdx-'));t.after(()=>fs.rmSync(root,{recursive:true,force:true}));
 write(path.join(root,'cangjie_stdx/build.py'),'# dry-run source fixture\n');
 const r=spawnSync(process.execPath,[cli,'--workspace',root,'--build-root',root,'--target','windows-x64','build','stdx'],
  {encoding:'utf8',env:{...process.env,CANGJIE_BUILD_DRY_RUN:'1',CJCJ_SRCBUILD_HOST_PROFILE:'generic',CJCJ_SRCBUILD_CONSUMER_SDK:''}});
 assert.equal(r.status,0,r.stdout+'\n'+r.stderr);
 assert.match(r.stderr,new RegExp('build.py install --prefix '+path.join(root,'software/cangjie/stdx')));
 assert.doesNotMatch(r.stderr,/build.py install --prefix .*cangjie_compiler\/output\/stdx/);
});


test('public stdx consumer failure preserves previous payload and facts then same argv recovers', t=>{
 const f=fixture(t);const argv=[...f.args,'build','stdx'];
 run(process.execPath,argv,{env:f.env});
 const old=fs.readFileSync(path.join(f.sdk,'share/cjcj/build-inputs/stdx.json'));
 const marker=path.join(f.sdk,'stdx','old-success');fs.writeFileSync(marker,'usable');
 const failed=spawnSync(process.execPath,argv,{env:{...f.env,FIXTURE_FAIL_CONSUMER:'79'},encoding:'utf8'});
 assert.notEqual(failed.status,0);assert.match(failed.stderr,/TARGET_FAILED rc=79/);
 assert.equal(fs.readFileSync(marker,'utf8'),'usable');
 assert.deepEqual(fs.readFileSync(path.join(f.sdk,'share/cjcj/build-inputs/stdx.json')),old);
 run(process.execPath,argv,{env:f.env});assert.equal(fs.existsSync(marker),false);
 console.log('STDX_CONSUMER_ROLLBACK_AND_RECOVERY_REACHED');
});

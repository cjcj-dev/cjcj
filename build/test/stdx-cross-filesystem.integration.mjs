#!/usr/bin/env zx
// Real device boundary and public build/sdk-build calls with a tiny native
// fixture. Never copy or modify a real SDK or another owner's workspace.
import fs from 'node:fs';
import path from 'node:path';
import assert from 'node:assert/strict';
import {spawnSync} from 'node:child_process';
import {fixture,write} from './fixtures/stdx-native.mjs';
import {STDX_BUILD_INPUTS} from '../srcbuild/stdx-build-inputs.mjs';
const evidence=process.env.RELEASE_EVIDENCE_TEST_ROOT,data=process.env.STDX_CROSS_DATA_ROOT;
if(!evidence||!data)throw Error('owned evidence and STDX_CROSS_DATA_ROOT required');
fs.mkdirSync(data,{recursive:true});
assert.notEqual(fs.statSync(data).dev,fs.statSync(evidence).dev,'test must cross real filesystems');
const temporary=process.env.TMPDIR;process.env.TMPDIR=data;
const f=fixture({after(){}});process.env.TMPDIR=temporary;
write(path.join(evidence,'workspace.txt'),f.root+'\n');
write(path.join(evidence,'devices.json'),JSON.stringify({workspace:fs.statSync(f.root).dev,installation:fs.statSync(evidence).dev}));
const records=[];
function call(label,argv,extra={}) {
 const r=spawnSync(argv[0],argv.slice(1),{env:{...f.env,...extra},encoding:'utf8',maxBuffer:2*1024*1024});
 records.push({label,argv,pid:r.pid,rc:r.status,signal:r.signal,error:r.error?.message});
 write(path.join(evidence,label+'.stdout'),r.stdout||'');write(path.join(evidence,label+'.stderr'),r.stderr||'');
 write(path.join(evidence,'commands.json'),JSON.stringify(records,null,2));return r;
}
const ok=r=>assert.equal(r.status,0,r.stdout+'\n'+r.stderr);
const sdkBuild=new URL('../../ci/bootstrap/sdk-build.mjs',import.meta.url).pathname;
ok(call('same-device-control',[process.execPath,...f.args,'build','stdx']));
console.log('STDX_SAME_DEVICE_INDEPENDENT_CONTROL_PASS');
const previous=fs.readFileSync(path.join(f.sdk,STDX_BUILD_INPUTS));
write(path.join(evidence,'original-stdx.json'),previous);
write(path.join(f.sdk,'include/native.h'),'/* already built native header */\n');
write(path.join(f.sdk,'unchanged-input'),'existing SDK predecessor\n');
const install=path.join(evidence,'sdk'),headers=path.join(f.root,'tools-native-headers'),oldWork=path.join(evidence,'original-flow');
const argv=[process.execPath,...f.args,'build','stdx'];
const old={work:oldWork,install,repos:{},env:{...f.env,CJCJ_SRCBUILD_CONSUMER_SDK:install},finalStage:'later-tools',stages:[
 {id:'tools-input-selection',output:f.root,commands:[{argv:[process.execPath,'-e',"require('node:fs').appendFileSync(process.argv[1],'selection\\n')",path.join(evidence,'selection-runs')]}]},
 {id:'tools-sdk-input',depends:['tools-input-selection'],output:install,copies:[{from:f.sdk,to:''}],test:{required:['bin/cjc','unchanged-input']}},
 {id:'tools-native-headers',depends:['tools-sdk-input'],output:headers,copies:[{from:path.join(install,'include'),to:'include'}],test:{required:['include/native.h']}},
 {id:'tools-stdx',depends:['tools-native-headers'],output:path.join(install,'stdx'),commands:[{argv,cwd:f.root}]},
 {id:'later-tools',depends:['tools-stdx'],output:install,commands:[{argv:[process.execPath,'-e','process.exit(99)']}]}
]};
const oldFile=path.join(evidence,'original-config.json');write(oldFile,JSON.stringify(old,null,2));
const first=call('cross-first-failure',[process.execPath,sdkBuild,'--config',oldFile,'--through','tools-stdx','--no-package'],{FIXTURE_FAIL_BUILD:'1'});
console.log('STDX_CROSS_INVALIDATION_ASSERT_REACHED');
assert.equal(first.status,1,first.stderr);assert.match(first.stderr,/\(exit=23\)/,'must reach build.py, never EXDEV');
const oldFailed=fs.readFileSync(path.join(oldWork,'build-result.json'));
assert.equal(JSON.parse(oldFailed).status,'FAILED');assert.equal(JSON.parse(oldFailed).stages.length,3);
write(path.join(evidence,'original-FAILED.json'),oldFailed);
const facts=path.join(install,STDX_BUILD_INPUTS),factDir=path.dirname(facts);
assert.equal(fs.existsSync(facts),false,'prior success invalidated after failed build');
const archived=fs.readdirSync(factDir).filter(name=>name.startsWith('stdx.json.previous-'));
assert.equal(archived.length,1);assert.deepEqual(fs.readFileSync(path.join(factDir,archived[0])),previous);
assert.equal(fs.readdirSync(path.join(f.root,'build/stdx')).some(name=>name.includes('.installed-previous-')),false);
console.log('STDX_OLD_FACTS_PRESERVED_ASSERT_REACHED');
const inode=fs.statSync(path.join(install,'unchanged-input')).ino,headerInode=fs.statSync(path.join(headers,'include/native.h')).ino;
// A new fixed executor/configuration gets a new small work/result directory.
// Existing public reuse keeps already installed outputs and their tests, while
// ordinary source selection still runs. The old configuration/FAILED is intact.
const config=path.join(evidence,'recovery-config.json'),generator=process.env.STDX_RECOVERY_CONFIG_GENERATOR;
if(!generator)throw Error('fixed STDX_RECOVERY_CONFIG_GENERATOR handoff required');
ok(call('prepare-recovery',[process.execPath,generator,oldFile,config,new URL('../../',import.meta.url).pathname.replace(/\/$/,''),path.join(evidence,'recovery-flow')]));
const next=JSON.parse(fs.readFileSync(config));
const run=(label,extra={},from=false,file=config)=>call(label,[process.execPath,sdkBuild,'--config',file,...(from?['--from','tools-stdx']:[]),'--through','tools-stdx','--no-package'],extra);
ok(run('same-install-recovery'));
assert.equal(fs.statSync(path.join(install,'unchanged-input')).ino,inode);assert.equal(fs.statSync(path.join(headers,'include/native.h')).ino,headerInode);
assert.deepEqual(fs.readFileSync(path.join(oldWork,'build-result.json')),oldFailed);
assert.equal(fs.readFileSync(oldFile,'utf8'),JSON.stringify(old,null,2));
assert.equal(JSON.parse(fs.readFileSync(path.join(next.work,'build-result.json'))).completedThrough,'tools-stdx');
console.log('STDX_PUBLIC_RECOVERY_NO_COPY_ASSERT_REACHED');
const beforeInstallFailure=fs.readFileSync(facts);
const failed=run('install-failure',{FIXTURE_FAIL_INSTALL:'1'},true);
assert.equal(failed.status,1);assert.match(failed.stderr,/\(exit=24\)/);assert.equal(fs.existsSync(facts),false);
write(path.join(evidence,'install-FAILED.json'),fs.readFileSync(path.join(next.work,'build-result.json')));
assert(fs.readdirSync(factDir).some(name=>name.startsWith('stdx.json.previous-')&&fs.readFileSync(path.join(factDir,name)).equals(beforeInstallFailure)));
const built=JSON.parse(fs.readFileSync(path.join(f.root,'build/stdx/build-inputs.json')));assert.equal(built.build.rc,0);assert.equal(built.install,undefined);
ok(run('from-failed-install',{},true));
const newFacts=fs.readFileSync(facts);
ok(call('incremental-cache',[process.execPath,...f.args,'--stdx-build-mode','incremental','build','stdx'],{CJCJ_SRCBUILD_CONSUMER_SDK:install}));
assert(fs.readdirSync(factDir).some(name=>name.startsWith('stdx.json.previous-')&&fs.readFileSync(path.join(factDir,name)).equals(newFacts)));
const buildDir=path.join(f.stdx,'build_temp/build');
assert(fs.readdirSync(buildDir).some(name=>name.startsWith('install_manifest.txt.previous-')));
const bad=structuredClone(next);bad.env.CANGJIE_BUILD_JOBS='1';const badFile=path.join(evidence,'mismatched-config.json');write(badFile,JSON.stringify(bad));
const mismatch=run('configuration-control',{},true,badFile);assert.equal(mismatch.status,1);assert.match(mismatch.stderr,/WORK_INPUT_MISMATCH/);
const marker=path.join(install,'unchanged-input');fs.renameSync(marker,marker+'.parked');
try {const missing=run('missing-predecessor',{},true);assert.equal(missing.status,1);assert.match(missing.stderr,/unchanged-input/);}finally{fs.renameSync(marker+'.parked',marker);}
ok(run('predecessor-restored',{},true));
assert.equal(fs.statSync(marker).ino,inode);assert.deepEqual(fs.readFileSync(path.join(oldWork,'build-result.json')),oldFailed);
console.log('STDX_CROSS_FILESYSTEM_FINITE_PASS first=1 build-failure=1 install-failure=1 reuse=1 from=1 cache=1 configuration-refusal=1 predecessor-refusal=1');

#!/usr/bin/env zx
import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import {spawnSync} from 'node:child_process';
import {load as loadYaml} from '../vendor/js-yaml/js-yaml.mjs';
const repo=path.resolve(import.meta.dirname,'../..');
const workflow=loadYaml(fs.readFileSync(path.join(repo,'.github/workflows/build-release-package.yml'),'utf8'));
const entry=workflow.jobs.package.steps.find(step=>step.run?.includes('ci/release/package-key.mjs'));
assert.ok(entry,'formal release package identity entry');
const argv=entry.run.trim().split(/\s+/);assert.equal(argv.shift(),'node');
function fixture(t,name){fs.mkdirSync(process.env.RELEASE_EVIDENCE_TEST_ROOT||os.tmpdir(),{recursive:true});const root=fs.mkdtempSync(path.join(process.env.RELEASE_EVIDENCE_TEST_ROOT||os.tmpdir(),'sdk-producer-'+name+'-'));if(!process.env.RELEASE_EVIDENCE_TEST_ROOT)t.after(()=>fs.rmSync(root,{recursive:true,force:true}));return root;}
function run(root,label,args,env={}){const result=spawnSync(process.execPath,args,{cwd:repo,env:{...process.env,...env},encoding:'utf8'});fs.writeFileSync(path.join(root,label+'.json'),JSON.stringify({argv:[process.execPath,...args],env,rc:result.status,signal:result.signal,stdout:result.stdout,stderr:result.stderr},null,2));return result;}
test('formal release entry rejects Windows component producers before any SDK download',t=>{
 const root=fixture(t,'windows');
 for(const key of ['win32-x64','win32-x64-android','win32-x64-ohos']){
  const output=path.join(root,key+'.env');const result=run(root,key,argv,{RELEASE_PLATFORM:'windows-x64',RELEASE_KEY:key,GITHUB_ENV:output});
  console.log('WHOLE_SDK_PRODUCER_TARGET_REACHED '+key);
  assert.equal(result.status,1,result.stdout+result.stderr);assert.match(result.stderr,/NATIVE_SDK_PRODUCER_MISSING windows-x64/);assert.equal(fs.existsSync(output),false);
 }
});
test('formal release entry preserves independent Linux producer and host-key identity control',t=>{
 const root=fixture(t,'linux'),output=path.join(root,'github.env');
 const ok=run(root,'linux',argv,{RELEASE_PLATFORM:'linux-x64',RELEASE_KEY:'linux-x64',GITHUB_ENV:output});assert.equal(ok.status,0,ok.stderr);assert.equal(fs.readFileSync(output,'utf8'),'PACKAGE_KEY=linux-x64\n');
 const bad=run(root,'host-key-conflict',argv,{RELEASE_PLATFORM:'linux-x64',RELEASE_KEY:'darwin-arm64',GITHUB_ENV:output});assert.equal(bad.status,1);assert.match(bad.stderr,/release key\/host mismatch/);assert.equal(fs.readFileSync(output,'utf8'),'PACKAGE_KEY=linux-x64\n');
});
test('formal plan exposes missing Windows whole SDK and keeps Linux cross-std comparison source',t=>{
 const root=fixture(t,'plan'),output=path.join(root,'output');
 const result=run(root,'plan',['ci/release/platform-matrix.mjs','plan','--platforms','win32-x64,linux-x64','--github-output',output]);assert.equal(result.status,0,result.stderr);
 const rows=Object.fromEntries(fs.readFileSync(output,'utf8').trim().split('\n').map(row=>{const at=row.indexOf('=');return[row.slice(0,at),row.slice(at+1)];}));
 console.log('WHOLE_SDK_PLAN_TARGET_REACHED');
 assert.deepEqual(JSON.parse(rows.package_matrix).include.map(row=>row.release_key),['linux-x64']);
 assert.deepEqual(JSON.parse(rows.source_matrix).include,[{target:'linux-x64'}]);
 const blocked=JSON.parse(rows.blocked_matrix).include;assert.equal(blocked.length,1);assert.equal(blocked[0].release_key,'win32-x64');assert.match(blocked[0].reasons,/native SDK windows-x64: no source cell runs package-install/);
 assert.deepEqual(JSON.parse(JSON.parse(rows.package_matrix).include[0].cross_std_artifacts),[{tuple:'windows_x86_64_cjnative',artifact:'final-std-windows-x64'}]);
});

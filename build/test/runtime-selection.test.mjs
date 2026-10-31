import test from 'node:test';import assert from 'node:assert/strict';import fs from 'node:fs/promises';import path from 'node:path';
import {resolveRuntimeSource,writeRuntimeSelection} from '../../ci/runtime-pin.mjs';
import {spawnSync} from 'node:child_process';
const pins=Object.fromEntries((await fs.readFile(new URL('../../ci/runtime_pin.env',import.meta.url),'utf8')).trim().split('\n').map(s=>s.split('=')));
const root=process.env.RELEASE_EVIDENCE_TEST_ROOT;if(!root)throw new Error('RELEASE_EVIDENCE_TEST_ROOT required');
await fs.mkdir(root,{recursive:true});
test('formal runtime source resolves to repository pin',async()=>{const r=await resolveRuntimeSource({});assert.equal(r.runtimeRef,pins.RUNTIME_REF);assert.equal(r.sourceUrl,pins.RUNTIME_SRC_URL);});
test('runtime ref, source URL and override authorization are independently checked',async()=>{
 await assert.rejects(resolveRuntimeSource({CJCJ_NATIVE_RUNTIME_REF:'a'.repeat(40)}),/NATIVE_RUNTIME_EXPLICIT_PAIR_REQUIRED/);
 await assert.rejects(resolveRuntimeSource({RUNTIME_SRC_URL:'https://invalid/runtime'}),/URL mismatch/);
 await assert.rejects(resolveRuntimeSource({CJCJ_RUNTIME_REF_OVERRIDE:'a'.repeat(40)}),/explicit/);
 await assert.rejects(resolveRuntimeSource({CJCJ_RUNTIME_REF_OVERRIDE:'short',CJCJ_ALLOW_RUNTIME_OVERRIDE:'1'}),/40-character/);
 const r=await resolveRuntimeSource({CJCJ_RUNTIME_REF_OVERRIDE:'a'.repeat(40),CJCJ_ALLOW_RUNTIME_OVERRIDE:'true'});assert.equal(r.runtimeRef,'a'.repeat(40));
});
test('transported pin cannot grant an override and source selection round trips',async()=>{
 const file=path.join(await fs.mkdtemp(path.join(root,'runtime-selection-')),'runtime.env');
 await writeRuntimeSelection(file,{});assert.equal((await resolveRuntimeSource({},file)).runtimeRef,pins.RUNTIME_REF);
 await fs.writeFile(file,`RUNTIME_REF=${'b'.repeat(40)}\nRUNTIME_SRC_URL=${pins.RUNTIME_SRC_URL}\n`);
 await assert.rejects(resolveRuntimeSource({},file),/selection pin mismatch/);
 const env={CJCJ_RUNTIME_REF_OVERRIDE:'b'.repeat(40),CJCJ_ALLOW_RUNTIME_OVERRIDE:'1'};assert.equal((await resolveRuntimeSource(env,file)).runtimeRef,'b'.repeat(40));
});
test('formal loader carries the explicit component pair through handoff and rejects a conflicting runtime',async()=>{
 const work=await fs.mkdtemp(path.join(root,'native-runtime-selection-'));
 const env={...process.env,GITHUB_ENV:work+'/github.env',
  CJCJ_NATIVE_LLVM_REF:'db51a4c7ebb6903e9f997d3b35d52f3577810385',
  CJCJ_NATIVE_RUNTIME_REF:'79b34798d0f4696f9fe5a3708981539466ecd35b',
  CJCJ_NATIVE_HOST_VERSION:'1.3.0-alpha.20260925001050'};
 for(const key of ['RUNTIME_REF','CJCJ_RUNTIME_REF_OVERRIDE','CJCJ_ALLOW_RUNTIME_OVERRIDE','CJCJ_BOOTSTRAP_RUNTIME_PIN'])delete env[key];
 const run=async label=>{const r=spawnSync(process.execPath,[new URL('../../ci/load_runtime_pin.mjs',import.meta.url).pathname],{env,encoding:'utf8'});
  await fs.writeFile(work+'/'+label+'.json',JSON.stringify({rc:r.status,signal:r.signal,stdout:r.stdout,stderr:r.stderr}));return r;};
 const normal=await run('normal');assert.equal(normal.status,0,normal.stderr);
 // A source pair also drives the runtime-only producer, without an SDK artifact.
 assert.equal((await resolveRuntimeSource({...env,CJCJ_NATIVE_RUNTIME_ARTIFACT:''})).runtimeRef,env.CJCJ_NATIVE_RUNTIME_REF);
 await assert.rejects(resolveRuntimeSource({CJCJ_NATIVE_RUNTIME_ARTIFACT:'frozen-runtime'}),/COMPONENT_SELECTION_REQUIRED/);
 assert.equal((await resolveRuntimeSource({...env,CJCJ_NATIVE_RUNTIME_ARTIFACT:'frozen-runtime'})).runtimeRef,env.CJCJ_NATIVE_RUNTIME_REF);
 const handed=Object.fromEntries((await fs.readFile(env.GITHUB_ENV,'utf8')).trim().split('\n').map(s=>s.split('=')));
 assert.equal(handed.CJCJ_NATIVE_RUNTIME_REF,env.CJCJ_NATIVE_RUNTIME_REF);
 assert.equal(handed.CJCJ_NATIVE_LLVM_REF,env.CJCJ_NATIVE_LLVM_REF);
 assert.equal(handed.CJCJ_NATIVE_HOST_VERSION,env.CJCJ_NATIVE_HOST_VERSION);
 assert.equal(handed.CJCJ_ALLOW_RUNTIME_OVERRIDE,undefined);
 assert.equal((await resolveRuntimeSource(handed)).runtimeRef,env.CJCJ_NATIVE_RUNTIME_REF);
 env.CJCJ_RUNTIME_REF_OVERRIDE='c'.repeat(40);const rejected=await run('conflict');assert.equal(rejected.status,1);assert.match(rejected.stderr,/NATIVE_RUNTIME_OVERRIDE_CONFLICT/);
 delete env.CJCJ_RUNTIME_REF_OVERRIDE;assert.equal((await run('restored')).status,0);
});

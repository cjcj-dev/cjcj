import fs from 'node:fs'; import os from 'node:os'; import path from 'node:path';
import {spawnSync} from 'node:child_process'; import assert from 'node:assert/strict'; import {test} from 'node:test';
import yaml from './vendor/js-yaml/js-yaml.mjs';
const llvm='db51a4c7ebb6903e9f997d3b35d52f3577810385', runtime='79b34798d0f4696f9fe5a3708981539466ecd35b';
function fixture(check) {
 const root=fs.mkdtempSync(path.join(os.tmpdir(),'native-llvm-input-'));
 try {
  const output=path.join(root,'environment');
  const run=extra=>spawnSync(process.execPath,['ci/native-llvm-inputs.mjs'],{encoding:'utf8',env:{...process.env,
   NATIVE_LLVM_REF:'',NATIVE_RUNTIME_REF:'',GITHUB_ENV:output,GITHUB_OUTPUT:path.join(root,'outputs'),...extra}});
  check({run,output});
 } finally {fs.rmSync(root,{recursive:true,force:true});}
}
test('native LLVM default preserves the repository source pair',()=>fixture(({run,output})=>{
 const result=run();assert.equal(result.status,0,result.stderr);
 for(const [file,key,outKey] of [['ci/llvm_pin.env','LLVM_SHA','LLVM_SHA'],['ci/runtime_pin.env','RUNTIME_REF','CJCJ_NATIVE_RUNTIME_REF']]) {
  const ref=new RegExp(`^${key}=([a-f0-9]{40})$`,'m').exec(fs.readFileSync(file,'utf8'))[1];
  assert.ok(fs.readFileSync(output,'utf8').includes(`${outKey}=${ref}\n`));
 }
 assert.doesNotMatch(result.stdout,/CJCJ_LLVM_RUNTIME_MODE/);
}));
test('native LLVM explicit complete pair reaches producer environment',()=>fixture(({run,output})=>{
 const result=run({NATIVE_LLVM_REF:llvm,NATIVE_RUNTIME_REF:runtime});assert.equal(result.status,0,result.stderr);
 const env=fs.readFileSync(output,'utf8');assert.ok(env.includes(`LLVM_SHA=${llvm}\n`));
 assert.ok(env.includes(`CJCJ_LLVM_RUNTIME_SHA=${runtime}\n`));assert.match(env,/CJCJ_LLVM_RUNTIME_MODE=private/);
}));
for(const [name,extra,reason] of [['partial',{NATIVE_LLVM_REF:llvm},'NATIVE_LLVM_PAIR_REQUIRED'],
 ['abbreviated',{NATIVE_LLVM_REF:'db51',NATIVE_RUNTIME_REF:runtime},'NATIVE_LLVM_REF_INVALID']]) {
 test(`native LLVM rejects ${name} pair before export`,()=>fixture(({run,output})=>{
  const result=run(extra);assert.equal(result.status,1);assert.ok(result.stderr.includes(reason));assert.equal(fs.existsSync(output),false);
 }));
}
test('formal native workflow passes source pair through cache and layout producer',()=>{
 const entry=yaml.load(fs.readFileSync('.github/workflows/build-fixed-llc.yml','utf8'));
 const producer=yaml.load(fs.readFileSync('.github/workflows/build-llvm-tools.yml','utf8'));
 for(const key of ['llvm_ref','runtime_ref']) assert.equal(entry.jobs.tuple.with[key],`\${{ inputs.${key} }}`);
 for(const job of ['build-tools','static-tuple']) {
  const load=producer.jobs[job].steps.find(step=>step.run==='node ci/native-llvm-inputs.mjs');assert.ok(load,job);
  assert.equal(load.env.NATIVE_LLVM_REF,'${{ inputs.llvm_ref }}');assert.equal(load.env.NATIVE_RUNTIME_REF,'${{ inputs.runtime_ref }}');
 }
 const cache=producer.jobs['build-tools'].steps.find(step=>step.id==='cache');assert.match(cache.with.key,/steps\.llvm-pin\.outputs\.runtime_sha/);
 const layout=producer.jobs['static-tuple'].steps.find(step=>step.name==='Publish the shared ten-payload layout');
 assert.doesNotMatch(layout.run,/source ci\/llvm_pin.env/);assert.match(layout.run,/ci\/llvm-tuple-layout.mjs/);
});
test('formal native entry passes the complete pair and platform subset to the dylib producer',()=>{
 const producer=yaml.load(fs.readFileSync('.github/workflows/build-llvm-tools.yml','utf8'));
 const dylib=yaml.load(fs.readFileSync('.github/workflows/build-llvm-dylib.yml','utf8'));
 for(const key of ['llvm_ref','runtime_ref','platforms','platform_set']) {
  assert.equal(producer.jobs['in-process-dylib'].with[key],`\${{ inputs.${key} }}`);
  assert.ok(dylib.on.workflow_call.inputs[key]);
 }
 const load=dylib.jobs.dylib.steps.find(step=>step.id==='pin');
 assert.equal(load.run,'node ci/native-llvm-inputs.mjs');
 assert.equal(load.env.NATIVE_LLVM_REF,'${{ inputs.llvm_ref }}');
 assert.equal(load.env.NATIVE_RUNTIME_REF,'${{ inputs.runtime_ref }}');
 const build=dylib.jobs.dylib.steps.find(step=>step.name==='Build three-target shared LLVM');
 assert.match(build.run,/ci\/fetch-llvm-runtime.mjs paired-runtime/);
 assert.match(build.run,/ci\/llvm-dylib\/record-manifest.mjs depot\/dylib llvm-fork paired-runtime/);
 assert.match(dylib.jobs.dylib.steps.find(step=>step.uses==='./.github/actions/sccache').with.pin,/runtime_sha/);
});
test('dylib matrix selects only requested native producers and uses native library names',()=>fixture(({output})=>{
 const run=requested=>spawnSync(process.execPath,['ci/llvm-tools-matrix.mjs'],{encoding:'utf8',
  env:{...process.env,REQUESTED:requested,PLATFORM_SET:'',GITHUB_OUTPUT:output}});
 const selected=run('linux_aarch64,darwin_x86_64');assert.equal(selected.status,0,selected.stderr);
 const matrix=JSON.parse(/^dylib_matrix=(.+)$/m.exec(fs.readFileSync(output,'utf8'))[1]);
 assert.deepEqual(matrix.include,[{runner:'ubuntu-22.04-arm',platform:'linux_aarch64',library:'libLLVM-15.so'},
  {runner:'macos-15-intel',platform:'darwin_x86_64',library:'libLLVM.dylib'}]);
 fs.rmSync(output);
 const windows=run('windows_x86_64');assert.equal(windows.status,0,windows.stderr);
 assert.match(fs.readFileSync(output,'utf8'),/^dylib_matrix=\{"include":\[\]\}$/m);
}));

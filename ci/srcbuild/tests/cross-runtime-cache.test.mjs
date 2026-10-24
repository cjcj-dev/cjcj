import fs from 'node:fs';
import path from 'node:path';
import os from 'node:os';
import {spawnSync} from 'node:child_process';
import assert from 'node:assert/strict';
import {test} from 'node:test';
import {load} from '../../vendor/js-yaml/js-yaml.mjs';
const root=path.resolve(import.meta.dirname,'../../..');
const workflow=load(fs.readFileSync(path.join(root,'.github/workflows/srcbuild-target.yml'),'utf8'));
// This is a workflow environment/CMake initialization contract. No runtime,
// final std, Apple SDK or target compiler is built by this small configuration.
for(const family of ['android','ohos','ios']) test(`${family} cross workflow selects sccache in real CMake initialization`,()=>{
 const job=workflow.jobs[`source-${family}`];
 const index=job.steps.findIndex(step=>step.run?.includes(`ci/srcbuild/steps/build-${family}-final-std.mjs`));
 assert.ok(index>0);
 assert.ok(job.steps.slice(0,index).some(step=>step.uses==='./.github/actions/sccache'));
 const declared=job.steps[index].env;
 const temp=fs.mkdtempSync(path.join(os.tmpdir(),'cross-runtime-cache-'));
 try {
  const cache=path.join(temp,'sccache');fs.writeFileSync(cache,'fixture executable, never run\n',{mode:0o755});
  fs.writeFileSync(path.join(temp,'CMakeLists.txt'),`cmake_minimum_required(VERSION 3.20)
project(CrossRuntimeCache NONE)
foreach(key CANGJIE_COMPILER_CACHE CMAKE_C_COMPILER_LAUNCHER CMAKE_CXX_COMPILER_LAUNCHER)
  if(NOT "\${\${key}}" STREQUAL "$ENV{SCCACHE_PATH}")
    message(FATAL_ERROR "CROSS_RUNTIME_CACHE_SELECTION_FAILED: \${key}")
  endif()
endforeach()
`);
  const env={...process.env,SCCACHE_PATH:cache,CMAKE_TOOLCHAIN_FILE:'',
   CMAKE_C_COMPILER_LAUNCHER:'',CMAKE_CXX_COMPILER_LAUNCHER:''};
  if(declared.CMAKE_TOOLCHAIN_FILE)env.CMAKE_TOOLCHAIN_FILE=declared.CMAKE_TOOLCHAIN_FILE.replace('${{ github.workspace }}',root);
  const result=spawnSync('cmake',['-S',temp,'-B',path.join(temp,'build')],{env,encoding:'utf8',timeout:20000});
  assert.equal(result.status,0,result.stdout+result.stderr);
  const actual=fs.readFileSync(path.join(temp,'build/CMakeCache.txt'),'utf8');
  assert.ok(actual.includes(`CANGJIE_COMPILER_CACHE:FILEPATH=${cache}`));
 } finally {fs.rmSync(temp,{recursive:true,force:true});}
});

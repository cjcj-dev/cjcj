import assert from 'node:assert/strict';
import {spawnSync} from 'node:child_process';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import test from 'node:test';
import {requiredStdOutputs,stdlibBuildFlags} from '../../build/build-stdlib.mjs';
import {crossTuples,loadPins,repo} from '../../build/common.mjs';

const tuple='linux_x86_64_cjnative';
const modules=`modules/${tuple}/std`;
const coreOutputs=[`${modules}/std.core.cjo`,`lib/${tuple}/libcangjie-std-core.a`,
  `runtime/lib/${tuple}/libcangjie-std-core.so`,'lib/libstdFFI.so'];
const bc=`${modules}/libstd.core.bc`,ast=`${modules}/std.ast.cjo`;
const fastFlags=['--stdlib-debug-info','off','--stdlib-build-lto-bc','off'];

// Run the real build wrapper with a Python stand-in that records argv and installs only the requested fixture files.
function runStd(t,stage,outputs,{include=false,cross}={}){
  const dir=fs.mkdtempSync(path.join(os.tmpdir(),'cjcj-std-options-'));
  t.after(()=>fs.rmSync(dir,{recursive:true,force:true}));
  const put=(file,content='fixture',mode)=>{
    const dest=path.join(dir,file);
    fs.mkdirSync(path.dirname(dest),{recursive:true});
    fs.writeFileSync(dest,content,{mode});
  };
  for(const file of ['sources/bounds/header','sources/pcre2/header',`sdk/lib/${tuple}/libcangjie-ast-support.a`,
    'sdk/schema/StdAstFormat.fbs','sdk/include/flatbuffers/StdAstFormat_generated.h',
    'sdk/third_party/flatbuffers/bin/flatc',`runtime/lib/${tuple}/input.a`,
    `runtime/runtime/lib/${tuple}/libboundscheck.so`])put(file);
  const args=['--stage',stage,'--platform','linux-x64','--sources','sources','--sdk','sdk','--runtime','runtime','--out','out','--jobs','1'];
  const env={...process.env,CANGJIE_HOME:''};
  if(include){
    put('include/cangjie/CHIR/IR/AttributeInfo.h','class AttributeInfo {};');
    args.push('--include','include');
  }
  if(cross){
    args.push('--cross',cross);
    put('sources/flatbuffers/header');
    env.PATH=path.join(dir,'bin')+path.delimiter+env.PATH;
    env.ANDROID_NDK_ROOT=path.join(dir,'ndk');
    env.AST_ARCHIVE=path.join(dir,`out.work/ast/lib/${crossTuples[cross]}/libcangjie-ast-support.a`);
    put('bin/cmake',`#!/bin/sh
set -eu
if [ "$1" = --install ]; then
  mkdir -p "$(dirname "$AST_ARCHIVE")"
  printf ast > "$AST_ARCHIVE"
fi
`,0o755);
  }
  const stdlib='sources/runtime/stdlib';
  put(`${stdlib}/build.py`,`import json, pathlib, sys
with open('argv.jsonl', 'a') as log:
    print(json.dumps(sys.argv[1:]), file=log)
if sys.argv[1] == 'install':
    for rel in ${JSON.stringify(outputs)}:
        dest = pathlib.Path(sys.argv[-1]) / rel
        dest.parent.mkdir(parents=True, exist_ok=True)
        dest.write_text('fixture')
`);
  const child=spawnSync(process.execPath,[path.join(repo,'build/build-stdlib.mjs'),...args],{cwd:dir,env,encoding:'utf8'});
  assert.ifError(child.error);
  assert.equal(child.signal,null,child.stderr);
  const log=path.join(dir,stdlib,'argv.jsonl');
  assert.ok(fs.existsSync(log),child.stderr);
  const calls=fs.readFileSync(log,'utf8').trim().split('\n').map(JSON.parse);
  assert.deepEqual(calls.map(call=>call[0]),['clean','build','install'],child.stderr);
  return {child,buildArgs:calls[1]};
}

function toggleArgs(args){
  return args.flatMap((arg,i)=>{
    if(!/^--stdlib-(debug-info|build-lto-bc)(=|$)/.test(arg))return [];
    return arg.includes('=')?[arg]:args.slice(i,i+2);
  });
}

test('runtime pin supplies the stdlib build switches',()=>{
  assert.equal(loadPins().repos.runtime.sha,'cebfdebd7528069b2d3c9b56cc46c08ba6c67652');
});

for(const [stage,flags] of [['std-bootstrap',fastFlags],['stage1-std',fastFlags],['stage3-std',[]]]){
  test(`${stage}: build.py receives the expected stdlib switches`,t=>{
    if(process.platform==='linux'){
      const {child,buildArgs}=runStd(t,stage,[...coreOutputs,bc,ast],{include:true});
      assert.equal(child.status,0,child.stderr);
      assert.deepEqual(toggleArgs(buildArgs),flags);
    }
    assert.deepEqual(stdlibBuildFlags(stage),flags);
  });

  test(`${stage}: validates the expected Linux stdlib outputs`,t=>{
    const final=stage==='stage3-std';
    if(process.platform==='linux'){
      const {child}=runStd(t,stage,[...coreOutputs,ast],{include:true});
      assert.equal(child.status,final?1:0,child.stderr);
      if(final)assert.match(child.stderr,/ENOENT.*modules\/linux_x86_64_cjnative\/std\/libstd\.core\.bc/);
    }
    const inputs={stage,tuple,shared:'.so',os:'linux'};
    const expected=final?[...coreOutputs,bc]:coreOutputs;
    assert.deepEqual(requiredStdOutputs(inputs),expected);
    assert.deepEqual(requiredStdOutputs({...inputs,include:'/headers'}),[...expected,ast]);
  });
}

test('stage3-std: Darwin validation requires dylibs without Linux bitcode',()=>{
  const tuple='darwin_aarch64_cjnative';
  assert.deepEqual(requiredStdOutputs({stage:'stage3-std',tuple,os:'darwin',shared:'.dylib'}),[
    `modules/${tuple}/std/std.core.cjo`,`lib/${tuple}/libcangjie-std-core.a`,
    `runtime/lib/${tuple}/libcangjie-std-core.dylib`,'lib/libstdFFI.dylib',
  ]);
});

for(const cross of Object.keys(crossTuples)){
  test(`${cross}: cross stdlib leaves debug and LTO defaults in place`,t=>{
    const tuple=crossTuples[cross],modules=`modules/${tuple}/std`;
    const shared=cross.startsWith('ios-')?'.dylib':'.so';
    const outputs=[`${modules}/std.core.cjo`,`lib/${tuple}/libcangjie-std-core.a`,
      `runtime/lib/${tuple}/libcangjie-std-core${shared}`,`${modules}/std.ast.cjo`];
    if(cross==='android-aarch64'&&process.platform==='linux'){
      const {child,buildArgs}=runStd(t,'stage1-std',outputs,{cross,include:true});
      assert.equal(child.status,0,child.stderr);
      assert.deepEqual(toggleArgs(buildArgs),[]);
    }
    for(const stage of [undefined,'std-bootstrap','stage1-std','stage3-std']){
      assert.deepEqual(stdlibBuildFlags(stage,cross),[]);
    }
    // WASI uses its own producer. Windows/Linux release overlays come from prebuilt SDKs.
    if(!['wasm32-wasi','windows-x64','linux-x64'].includes(cross)){
      assert.deepEqual(requiredStdOutputs({stage:'stage3-std',cross,tuple,os:'linux',shared:'.so',include:'/headers'}),outputs);
    }
  });
}

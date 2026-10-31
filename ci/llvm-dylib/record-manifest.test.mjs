import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import crypto from 'node:crypto';
import {spawnSync} from 'node:child_process';
import assert from 'node:assert/strict';
import {test} from 'node:test';
function fixture(check) {
  const root=fs.mkdtempSync(path.join(os.tmpdir(),'dylib-record-'));
  try {
    const source=path.join(root,'source'), depot=path.join(root,'depot');
    fs.mkdirSync(source);fs.mkdirSync(depot);
    fs.writeFileSync(path.join(source,'input'),'source identity');
    const git=args=>{
      const result=spawnSync('git',['-C',source,...args],{encoding:'utf8'});
      assert.equal(result.status,0,result.stderr);return result.stdout.trim();
    };
    git(['init','-q']);git(['add','.']);
    git(['-c','user.name=Zxilly','-c','user.email=zxilly@outlook.com','commit','-qm','native producer fixture']);
    const commit=git(['rev-parse','HEAD']);
    for(const file of ['libLLVM-15.so','libLLVM.dylib'])fs.writeFileSync(path.join(depot,file),'test library bytes');
    const env={...process.env,CJCJ_NATIVE_LLVM_REF:commit,CJCJ_NATIVE_RUNTIME_REF:commit,
      LLVM_DYLIB_PLATFORM:'linux_aarch64',LLVM_DYLIB_LIBRARY:'libLLVM-15.so',
      GITHUB_RUN_ID:'123',GITHUB_RUN_ATTEMPT:'2',GITHUB_ENV:path.join(root,'environment')};
    const run=extra=>spawnSync(process.execPath,['ci/llvm-dylib/record-manifest.mjs',depot,source,source],
      {encoding:'utf8',env:{...env,...extra}});
    check({run,depot,commit});
  } finally {fs.rmSync(root,{recursive:true,force:true});}
}
for(const [platform,library] of [['linux_aarch64','libLLVM-15.so'],['darwin_x86_64','libLLVM.dylib']]) {
  test(`${platform} manifest records checked-out sources and actual library digest`,()=>fixture(({run,depot,commit})=>{
    const result=run({LLVM_DYLIB_PLATFORM:platform,LLVM_DYLIB_LIBRARY:library});assert.equal(result.status,0,result.stderr);
    const manifest=JSON.parse(fs.readFileSync(path.join(depot,'manifest.json')));
    assert.equal(manifest.llvm_sha,commit);assert.equal(manifest.runtime_sha,commit);
    assert.equal(manifest.platform,platform);assert.equal(manifest.library,library);
    assert.equal(manifest.sha256,crypto.createHash('sha256').update('test library bytes').digest('hex'));
  }));
}
for(const [name,extra,reason] of [['runtime checkout',{CJCJ_NATIVE_RUNTIME_REF:'f'.repeat(40)},'LLVM_DYLIB_CHECKOUT_MISMATCH'],
  ['LLVM checkout',{CJCJ_NATIVE_LLVM_REF:'e'.repeat(40)},'LLVM_DYLIB_CHECKOUT_MISMATCH'],
  ['platform library',{LLVM_DYLIB_LIBRARY:'libLLVM.dylib'},'LLVM_DYLIB_PLATFORM_MISMATCH']]) {
  test(`manifest refuses mismatched ${name} before publishing`,()=>fixture(({run,depot})=>{
    const result=run(extra);assert.equal(result.status,1);assert.ok(result.stderr.includes(reason),result.stderr);
    assert.equal(fs.existsSync(path.join(depot,'manifest.json')),false);
  }));
}

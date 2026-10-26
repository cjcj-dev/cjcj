#!/usr/bin/env zx
import fs from 'node:fs';
import path from 'node:path';
import assert from 'node:assert/strict';
import {spawnSync} from 'node:child_process';
import {darwinConsumerHost} from './consume_darwin_inputs.mjs';
import {copyDarwinControlSource, repository, writeCut} from './darwin_control_inputs.mjs';
const out = path.resolve(process.argv[2]); fs.mkdirSync(out,{recursive:true});
const normal = JSON.parse(fs.readFileSync(path.join(path.dirname(out),'darwin-consumer.json'), 'utf8'));
darwinConsumerHost(normal.target);
const relative = 'ci/release/darwin_llvm.mjs';
const original = fs.readFileSync(path.join(repository,relative),'utf8');
const cuts = [
  ['source-cut', "assert.equal(manifest.llvm_sha, llvmSha, 'LLVM_DYLIB_SOURCE_MISMATCH');", 'DARWIN_REJECT_llvm_sha'],
  ['platform-cut', "assert.equal(manifest.platform, platform, 'LLVM_DYLIB_PLATFORM_MISMATCH');", 'DARWIN_REJECT_platform'],
  ['cpu-cut', "assert.equal(header.readUInt32LE(4), cpu, `DARWIN_INPUT_CPU: ${file}`);", 'DARWIN_REJECT_DARWIN_INPUT_CPU'],
];
const results = {};
for (const [arm,bearing,rule] of [['candidate'],...cuts,['restored']]) {
  const root = path.join(out,arm); copyDarwinControlSource(root);
  let changed = original;
  if (bearing) {
    assert.equal(original.split(bearing).length - 1,1);
    changed = original.replace(bearing,'/* controlled omission */');
    writeCut(out,original,changed,arm);
    const diff=spawnSync('diff',['-u',path.join(out,`${arm}.original`),path.join(out,`${arm}.changed`)],{encoding:'utf8'});
    fs.writeFileSync(path.join(out,`${arm}.diff`),diff.stdout); assert.equal(diff.status,1);
  }
  const source=path.join(root,relative); fs.writeFileSync(source,changed);
  const child=spawnSync(process.execPath,['--test',path.join(repository,'ci/release/darwin_llvm.test.mjs')],{
    encoding:'utf8',env:{...process.env, PLATFORM:normal.platform, CJCJ_NATIVE_LLVM_REF:normal.sources.llvm,
      DARWIN_LLVM_NATIVE_SOURCE:normal.inputs.colour_llvm, DARWIN_LLVM_PRODUCT:source}});
  fs.writeFileSync(path.join(out,`${arm}.stdout`),child.stdout||'');
  fs.writeFileSync(path.join(out,`${arm}.stderr`),child.stderr||'');
  results[arm]={rc:child.status,signal:child.signal,error:child.error?.message||null};
  fs.writeFileSync(path.join(out,'results.json'),JSON.stringify(results,null,2)+'\n');
  if(child.error)throw child.error;
  assert.equal(child.signal,null);
  assert.equal(child.status,bearing?1:0,child.stdout+child.stderr);
  if(bearing) {
    assert.match(child.stdout,new RegExp(rule));
    assert.match(child.stdout,/^# fail 1$/m);
    assert.match(child.stdout,/^# pass 9$/m);
  }
  console.log(`DARWIN_LLVM_CONTROL ${arm} rc=${child.status}`);
}

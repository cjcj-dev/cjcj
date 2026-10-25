#!/usr/bin/env zx
import fs from 'node:fs';
import path from 'node:path';
import assert from 'node:assert/strict';
import {spawnSync} from 'node:child_process';
import {darwinConsumerHost} from './consume_darwin_inputs.mjs';
import {copyDarwinControlSource, repository, writeCut} from './darwin_control_inputs.mjs';
const work = path.resolve(process.argv[2]);
const normal = JSON.parse(fs.readFileSync(path.join(work, 'darwin-consumer.json'), 'utf8'));
darwinConsumerHost(normal.target);
const out = path.join(work, 'loader-controls'); fs.mkdirSync(out, {recursive:true});
const relative = 'ci/release/consume_darwin_inputs.mjs';
const original = fs.readFileSync(path.join(repository, relative), 'utf8');
const bearing = 'execute(stage, loader, [binary.file, symbol, mode])';
assert.equal(original.split(bearing).length - 1, 1, 'DARWIN_LOADER_CUT_BEARING');
const env = {...process.env, CJCJ_SRCBUILD_TARGET:normal.target,
  CJCJ_BOOTSTRAP_HOST_LLVM_ARTIFACT:normal.inputs.host_llvm,
  CJCJ_BOOTSTRAP_DYLIB_ARTIFACT:normal.inputs.colour_llvm,
  CJCJ_BOOTSTRAP_COLOUR_RT:normal.inputs.runtime,
  LLVM_SHA:normal.sources.llvm, RUNTIME_REF:normal.sources.runtime};
const results = {};
for (const arm of ['candidate', 'cut', 'restored']) {
  const root = path.join(out, arm); copyDarwinControlSource(root);
  const source = path.join(root, relative);
  const changed = arm === 'cut' ? original.replace(bearing,
    "execute(stage, loader, [stage === 'colour-llvm' ? hostBinary.file : binary.file, symbol, mode])") : original;
  fs.writeFileSync(source, changed);
  if (arm === 'cut') {
    writeCut(out, original, changed, 'loader');
    const diff = spawnSync('diff', ['-u', path.join(out,'loader.original'), path.join(out,'loader.changed')], {encoding:'utf8'});
    fs.writeFileSync(path.join(out, 'cut.diff'), diff.stdout);
    assert.equal(diff.status, 1);
  }
  const child = spawnSync(process.execPath, [source, path.join(root,'work'), normal.target], {env, encoding:'utf8'});
  fs.writeFileSync(path.join(out, `${arm}.stdout`), child.stdout || '');
  fs.writeFileSync(path.join(out, `${arm}.stderr`), child.stderr || '');
  results[arm] = {rc:child.status, signal:child.signal, error:child.error?.message || null};
  fs.writeFileSync(path.join(out,'results.json'), JSON.stringify(results,null,2)+'\n');
  if (child.error) throw child.error;
  assert.equal(child.signal, null);
  if (arm === 'cut') {
    assert.equal(child.status, 1, 'DARWIN_LOADER_TARGET_CUT_RC');
    assert.match(child.stderr, /DARWIN_CONSUMER_LOADED_ORIGIN/);
    // Independent host LLVM called successfully, and the wrong image also
    // made its real C API call before the colour-origin assertion turned red.
    assert.equal((child.stdout.match(/DARWIN_LLVM_CONTEXT_OK/g) || []).length, 2);
    assert.doesNotMatch(child.stderr, /DARWIN_DLOPEN_FAILED|DARWIN_LOADED_SYMBOL_MISSING|ERR_MODULE_NOT_FOUND/);
  } else {
    assert.equal(child.status, 0, child.stderr);
    const observed = JSON.parse(fs.readFileSync(path.join(root,'work/darwin-consumer.json'), 'utf8'));
    assert.deepEqual(observed.loaded.map(row=>[row.mode,row.symbol,row.platform]), normal.loaded.map(row=>[row.mode,row.symbol,row.platform]));
  }
  console.log(`DARWIN_LOADER_CONTROL ${arm} rc=${child.status}`);
}

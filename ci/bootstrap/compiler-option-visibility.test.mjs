import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs/promises';
import path from 'node:path';
import os from 'node:os';
import {visibleOptionsOnly,configureOptionVisibility,requireOptionVisibility} from './compiler-option-visibility.mjs';
import {prepareNativeInputs} from './sdk-inputs.mjs';

test('visible-only defaults and explicit build settings reject ambiguous inputs',async()=>{
  assert.equal(visibleOptionsOnly(),true);
  for(const value of [true,'true'])assert.equal(visibleOptionsOnly(value),true);
  for(const value of [false,'false'])assert.equal(visibleOptionsOnly(value),false);
  for(const value of ['',0,1,null,'FALSE','off'])assert.throws(()=>visibleOptionsOnly(value),/EXPECTED_BOOLEAN/);
  await assert.rejects(prepareNativeInputs({visibleOptionsOnly:0}),/EXPECTED_BOOLEAN/);
  requireOptionVisibility(undefined,true);requireOptionVisibility(false,false);
  assert.throws(()=>requireOptionVisibility(undefined,false),/CONFIGURATION_MISMATCH/);
  assert.throws(()=>requireOptionVisibility(false,true),/CONFIGURATION_MISMATCH/);
});

test('development builds select the option package and restore after failure',async()=>{
  const root=await fs.mkdtemp(path.join(process.env.RELEASE_EVIDENCE_TEST_ROOT||os.tmpdir(),'option-visibility-'));
  const file=path.join(root,'packages/option/cjpm.toml');await fs.mkdir(path.dirname(file),{recursive:true});
  const original=await fs.readFile(new URL('../../packages/option/cjpm.toml',import.meta.url),'utf8');
  await fs.writeFile(file,original);
  const restore=await configureOptionVisibility(root,false);
  try {assert.match(await fs.readFile(file,'utf8'),/--cfg CANGJIE_VISIBLE_OPTIONS_ONLY=false/);throw Error('producer failed');}
  catch(error){assert.equal(error.message,'producer failed');}finally{await restore();}
  assert.equal(await fs.readFile(file,'utf8'),original);
  await (await configureOptionVisibility(root,true))();
  assert.equal(await fs.readFile(file,'utf8'),original);
  await fs.writeFile(file,'compile-option = ""\n');
  await assert.rejects(configureOptionVisibility(root,false),/CONFIGURATION_UNSUPPORTED/);
  assert.equal(await fs.readFile(file,'utf8'),'compile-option = ""\n');
});

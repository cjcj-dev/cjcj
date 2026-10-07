#!/usr/bin/env zx
import fs from 'node:fs';
import path from 'node:path';
import os from 'node:os';
import assert from 'node:assert/strict';
import {pathToFileURL} from 'node:url';
import {spawnSync} from 'node:child_process';
const product=process.env.BOOTSTRAP_PRODUCT?.replace(/\.sh$/,'.mjs') || new URL('./bootstrap.mjs',import.meta.url).pathname;
const {Bootstrap}=await import(pathToFileURL(product));
const scratch=fs.mkdtempSync(path.join(process.env.TMPDIR||os.tmpdir(),'stage0-cache-'));
try {
  const bootstrap=new Bootstrap([]); bootstrap.STAGE0_CACHE_ROOT=scratch+'/cache';
  fs.copyFileSync('/usr/bin/true',scratch+'/compiler');fs.mkdirSync(scratch+'/restored');
  bootstrap.cachePublish('test-key',scratch+'/compiler');assert.equal(bootstrap.cacheRestore('test-key',scratch+'/restored/cjcj-stage1'),true);
  assert.deepEqual(fs.readFileSync(scratch+'/compiler'),fs.readFileSync(scratch+'/restored/cjcj-stage1'));
  assert.equal(spawnSync(scratch+'/restored/cjcj-stage1').status,0); console.log('PASS cache roundtrip preserves executable bytes');
  const manifest=bootstrap.STAGE0_CACHE_ROOT+'/test-key/MANIFEST';
  fs.writeFileSync(manifest,fs.readFileSync(manifest,'utf8').replace('stage0-cache-v2','stage0-cache-v1'));
  assert.equal(bootstrap.cacheRestore('test-key',scratch+'/restored/cjcj-stage1'),false);console.log('PASS obsolete cache rejected');
  fs.writeFileSync(manifest,fs.readFileSync(manifest,'utf8').replace('stage0-cache-v1','stage0-cache-v2'));
  fs.appendFileSync(bootstrap.STAGE0_CACHE_ROOT+'/test-key/cjcj-stage1','changed\n');
  assert.equal(bootstrap.cacheRestore('test-key',scratch+'/restored/cjcj-stage1'),false);
  assert.deepEqual(fs.readFileSync(scratch+'/compiler'),fs.readFileSync(scratch+'/restored/cjcj-stage1'));console.log('PASS corrupt cache rejected before replacing compiler');
} finally {fs.rmSync(scratch,{recursive:true,force:true});}

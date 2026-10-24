#!/usr/bin/env zx
// Resource-gated actual environment CLI. Requires a real target-tool SDK; this
// never synthesizes ELF/source facts or starts the 96-CPU language suite.
import fs from 'node:fs/promises';
import path from 'node:path';
import {fileURLToPath} from 'node:url';
import {spawnSync} from 'node:child_process';
import assert from 'node:assert/strict';
import {TOOL_NAMES,TOOL_PUBLIC_NAMES} from '../../build/srcbuild/tool-layout.mjs';
const [source,work]=process.argv.slice(2);
if(!source||!work)throw Error('usage: verify-target-tools.integration.mjs REAL_TARGET_SDK NEW_PRIVATE_WORK');
await fs.mkdir(work,{recursive:false});
const sdk=path.resolve(work,'sdk'),out=path.resolve(work,'environment');
const command=['python3',fileURLToPath(new URL('./environment.py',import.meta.url)),path.resolve(source),sdk,out,'--arm','bootstrap'];
const result=spawnSync(command[0],command.slice(1),{encoding:'utf8',maxBuffer:4*1024*1024});
await fs.writeFile(path.join(work,'command.json'),JSON.stringify({argv:command,rc:result.status,signal:result.signal,error:result.error?.message,stdout:result.stdout,stderr:result.stderr},null,2)+'\n');
assert.equal(result.status,0,result.stderr);
const manifest=JSON.parse(await fs.readFile(path.join(out,'environment.json'),'utf8'));
for(const name of TOOL_NAMES) {
  const publicName=TOOL_PUBLIC_NAMES[name]??name;
  assert.equal(manifest.tools[publicName]?.ready,true,publicName+': '+manifest.tools[publicName]?.reason);
  assert.equal(manifest.tools[publicName].rc,0);
  console.log('PUBLIC_TARGET_TOOL_INPUT_AND_PROBE_REACHED '+publicName);
}
// Preserve output and SDK for registered semantic/package tests; probes alone
// do not grant language, macro, JNI behavior or complete SDK qualification.

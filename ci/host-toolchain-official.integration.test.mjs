import assert from 'node:assert/strict';
import fs from 'node:fs/promises';
import path from 'node:path';
import {spawnSync} from 'node:child_process';
import {fileURLToPath} from 'node:url';
import test from 'node:test';
import {hostToolchainFromCjcVersion} from './host-toolchain-pin.mjs';
const repository=fileURLToPath(new URL('..',import.meta.url));
test('the real workflow selector chooses the independently measured Linux publisher identity',async()=>{
  const input=JSON.parse(await fs.readFile(process.env.SDK_OFFICIAL_INPUT,'utf8'));
  assert.ok(input.root&&input.compilerSha256,'fixed original H input required');
  const {fileDigest}=await import('./bootstrap/sdk-io.mjs');
  assert.equal(await fileDigest(path.join(input.root,'bin/cjc')),input.compilerSha256,'independent original H compiler bytes');
  const cjc=spawnSync(path.join(input.root,'bin/cjc'),['-v'],{encoding:'utf8'});
  assert.equal(cjc.status,0,cjc.stderr);
  const expected=hostToolchainFromCjcVersion(cjc.stdout+cjc.stderr);
  const selected=spawnSync(process.execPath,[path.join(repository,'ci/host-toolchain-pin.mjs'),'--github-env','--platform','linux_x86_64'],{encoding:'utf8'});
  assert.equal(selected.status,0,selected.stderr);
  console.log(`HOST_PLATFORM_IDENTITY_ASSERT_REACHED actual=${selected.stdout.trim()} measured=${expected}`);
  assert.equal(selected.stdout.trim(),`CJCJ_TOOLCHAIN=${expected}`,'workflow value must select the independently measured new Linux publisher');
});
test('the workflow selector uses the independently downloaded ARM release identity',()=>{
  const selected=spawnSync(process.execPath,[path.join(repository,'ci/host-toolchain-pin.mjs'),'--github-env','--platform','linux_aarch64'],{encoding:'utf8'});
  assert.equal(selected.status,0,selected.stderr);
  assert.equal(selected.stdout.trim(),'CJCJ_TOOLCHAIN=nightly-'+'1.3.0-alpha.20261025001053');
});

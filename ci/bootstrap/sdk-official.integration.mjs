import assert from 'node:assert/strict';
import fs from 'node:fs/promises';
import path from 'node:path';
import {spawnSync} from 'node:child_process';
import {fileURLToPath} from 'node:url';
import test from 'node:test';
import {buildIdentities} from './sdk-manifest.mjs';

const repository = fileURLToPath(new URL('../..', import.meta.url));
async function resolveOfficial() {
  assert.ok(process.env.SDK_OFFICIAL_PLAN && process.env.SDK_OFFICIAL_EVIDENCE, 'actual privately verified official input and evidence root required');
  const root = await fs.mkdtemp(path.join(process.env.SDK_OFFICIAL_EVIDENCE, 'official-'));
  const plan = JSON.parse(await fs.readFile(process.env.SDK_OFFICIAL_PLAN, 'utf8'));
  plan.buildRoot = path.join(root, 'builds');
  const component = plan.components[0];
  const head = spawnSync('/usr/bin/git', ['-C', repository, 'rev-parse', 'HEAD'], {encoding: 'utf8'});
  assert.equal(head.status, 0, head.stderr);
  component.producer = {adapter: 'official', repository, version: head.stdout.trim()};
  const input = path.join(root, 'plan.json'); await fs.writeFile(input, JSON.stringify(plan));
  const child = spawnSync(process.execPath, [path.join(repository, 'ci/bootstrap/toolchain-sdk.mjs'), '--plan', input, '--resolve'], {encoding: 'utf8', maxBuffer: 32 * 1024 * 1024});
  await fs.writeFile(path.join(root, 'resolver.log'), child.stdout + child.stderr);
  await fs.writeFile(path.join(root, 'result.json'), JSON.stringify({rc: child.status, signal: child.signal, repository, head: head.stdout.trim()}));
  assert.equal(child.status, 0, child.stdout + child.stderr);
  const output = JSON.parse(await fs.readFile(path.join(buildIdentities(plan).get(component.id).directory, 'output.json'), 'utf8'));
  return {root, output, manifest: JSON.parse(child.stdout.trimEnd().split('\n').at(-1))};
}

test('official producer preserves the real publisher cjdb alias', async () => {
  const {root, output} = await resolveOfficial();
  console.log(`OFFICIAL_PRODUCER_ALIAS_ASSERT_REACHED evidence=${root}`);
  assert.equal(output.files['tools/bin/cjdb'].type, 'symlink', 'actual official producer must retain the publisher link type');
  assert.equal(output.files['tools/bin/cjdb'].target, '../../third_party/llvm/bin/lldb');
  assert.equal(await fs.readlink(path.join(output.artifacts, 'tools/bin/cjdb')), '../../third_party/llvm/bin/lldb');
  assert.equal(output.component.source.version, '1.3.0-alpha.20261009001050');
});

test('official aliases reach the real resolver install map', async () => {
  const {root, manifest} = await resolveOfficial();
  console.log(`OFFICIAL_CONSUMER_ALIAS_ASSERT_REACHED evidence=${root}`);
  assert.equal(manifest.files['tools/bin/cjdb'].type, 'symlink', 'actual resolver must preserve the authenticated publisher alias');
  assert.equal(manifest.files['tools/bin/cjdb'].target, '../../third_party/llvm/bin/lldb');
  assert.equal(manifest.files['tools/bin/cjdb'].sha256, manifest.files['third_party/llvm/bin/lldb'].sha256);
  assert.equal(manifest.files['bin/cjc'].type, 'file', 'physical compiler control remains a file');
});

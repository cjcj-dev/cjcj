import assert from 'node:assert/strict';
import fs from 'node:fs/promises';
import path from 'node:path';
import {fileURLToPath} from 'node:url';
import {spawnSync} from 'node:child_process';
import test from 'node:test';
import {buildIdentities, fileDigest} from './sdk-manifest.mjs';

const repository = fileURLToPath(new URL('../..', import.meta.url));

test('fixed compiler schema reaches the real SDK resolver with its source bytes', async () => {
  assert.ok(process.env.SDK_EXPORT_PLAN && process.env.SDK_EXPORT_ROOT, 'explicit private sealed input plan and evidence parent required');
  const plan = JSON.parse(await fs.readFile(process.env.SDK_EXPORT_PLAN, 'utf8'));
  const root = await fs.mkdtemp(path.join(process.env.SDK_EXPORT_ROOT, 'schema-resolver-'));
  plan.buildRoot = path.join(root, 'builds');
  const component = plan.components.find(c => c.id === 'compiler-schema');
  assert.equal(component?.producer.adapter, 'compiler-schema');
  assert.equal(component.source.commit, '174db8f40d5efddee63c47a3162bbf676bc227a0');
  const git = spawnSync(component.config.tools.git.path, ['-C', repository, 'rev-parse', 'HEAD'], {encoding: 'utf8'});
  assert.equal(git.status, 0, git.stderr);
  component.producer = {adapter: 'compiler-schema', repository, version: git.stdout.trim()};
  const input = path.join(root, 'plan.json'); await fs.writeFile(input, JSON.stringify(plan));
  const child = spawnSync(component.config.tools.node.path, [path.join(repository, 'ci/bootstrap/toolchain-sdk.mjs'), '--plan', input, '--resolve'], {encoding: 'utf8', maxBuffer: 32 * 1024 * 1024});
  await fs.writeFile(path.join(root, 'resolver.log'), child.stdout + child.stderr);
  await fs.writeFile(path.join(root, 'resolver-result.json'), JSON.stringify({rc: child.status, signal: child.signal, repository, producer: component.producer}));
  const directory = buildIdentities(plan).get(component.id).directory;
  const output = JSON.parse(await fs.readFile(path.join(directory, 'output.json'), 'utf8'));
  console.log(`SCHEMA_SOURCE_ASSERT_REACHED evidence=${root} producer=${component.producer.version} resolver_rc=${child.status}`);
  assert.equal(output.files['schema/StdxChirFormat.fbs']?.sha256,
    await fileDigest(path.join(component.source.repo, 'schema/StdxChirFormat.fbs')),
    'real producer must export the fixed StdxChir schema, not another source file');
  assert.equal(child.status, 0, child.stdout + child.stderr);
  const manifest = JSON.parse(child.stdout.trimEnd().split('\n').at(-1));
  console.log(`SCHEMA_INSTALL_ASSERT_REACHED evidence=${root}`);
  assert.equal(manifest.files['schema/StdxChirFormat.fbs']?.sha256, output.files['schema/StdxChirFormat.fbs'].sha256,
    'real SDK resolver must retain the schema in the install map');
  assert.equal(manifest.files['schema/StdxChirFormat.fbs'].buildId, output.buildId);
});

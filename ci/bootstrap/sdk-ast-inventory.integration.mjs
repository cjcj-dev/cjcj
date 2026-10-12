#!/usr/bin/env zx
import fs from 'node:fs/promises';
import path from 'node:path';
import {fileURLToPath} from 'node:url';
import {spawnSync} from 'node:child_process';
import assert from 'node:assert/strict';
import test from 'node:test';
import {readJson, readOutput, buildIdentities, fileDigest, canonical} from './sdk-manifest.mjs';

const repository = fileURLToPath(new URL('../..', import.meta.url));
const planFile = process.env.SDK_AST_PLAN, evidence = process.env.SDK_AST_EVIDENCE;
assert.ok(planFile && evidence, 'genuine frozen AST plan and exclusively owned evidence directory required');
const plan = await readJson(planFile), identities = buildIdentities(plan);
const official = plan.components.find(c => c.producer.adapter === 'official');
const ast = plan.components.find(c => c.producer.adapter === 'ast-support');
const seed = await readOutput(identities.get(official.id).directory, official, identities.get(official.id));
const product = process.env.SDK_AST_PRODUCT || repository;
const {produceComponent} = await import(path.join(product, 'ci/bootstrap/sdk-producers.mjs'));
const head = spawnSync('/usr/bin/git', ['-C', product, 'rev-parse', 'HEAD'], {encoding: 'utf8'});
assert.equal(head.status, 0, head.stderr);
await fs.mkdir(evidence, {recursive: true});
const subset = 'third_party/flatbuffers', dirRel = `${subset}/include/flatbuffers/pch`;
const fileRel = `${subset}/include/flatbuffers/base.h`;

async function invocation(name, dependency = seed, producer = ast) {
  const arm = structuredClone(plan);
  arm.buildRoot = path.join(evidence, name, 'builds');
  const retained = arm.components.find(c => c.id === official.id);
  retained.producer = {...retained.producer, receipt: seed.directory, receiptSha256: seed.receiptSha256, originBuildRoot: plan.buildRoot};
  const component = arm.components.find(c => c.id === producer.id);
  if (producer.id === official.id) {
    delete component.producer.receipt;
    delete component.producer.receiptSha256;
    delete component.producer.originBuildRoot;
  }
  component.producer = {...component.producer, repository: product, version: head.stdout.trim()};
  const identity = buildIdentities(arm).get(component.id);
  let output, error;
  try { output = await produceComponent(arm, component, identity, new Map([[official.id, dependency]])); }
  catch (e) { error = e; }
  let log = '';
  try {
    for (const file of await fs.readdir(path.join(identity.directory, 'logs'))) {
      if (file.endsWith('.log')) log += await fs.readFile(path.join(identity.directory, 'logs', file), 'utf8');
    }
  } catch (e) { if (e.code !== 'ENOENT') throw e; }
  const result = {rc: output ? 0 : error?.rc ?? null, error: error?.message, log,
    product, head: head.stdout.trim(), directory: identity.directory, receiptSha256: output?.receiptSha256};
  await fs.writeFile(path.join(evidence, `${name}.json`), canonical(result));
  return result;
}

test('AST real normal receipt preserves complete readonly FlatBuffers deployment', async () => {
  const output = await readOutput(identities.get(ast.id).directory, ast, identities.get(ast.id));
  const rows = Object.entries(seed.files).filter(([rel]) => rel === subset || rel.startsWith(`${subset}/`));
  console.log(`AST_NORMAL_TARGET_ASSERT_REACHED members=${rows.length} receipt=${output.receiptSha256}`);
  assert.ok(rows.some(([, row]) => row.type === 'directory'), 'genuine directories must be exercised');
  for (const [rel, row] of rows) {
    const installed = output.files[rel];
    assert.equal(installed?.type, row.type, `complete member/type ${rel}`);
    assert.equal(installed.mode, row.mode, `deployment mode ${rel}`);
    assert.equal(installed.sha256, row.sha256, `bytes ${rel}`);
    if (row.type === 'directory') assert.equal(row.mode, row.sourceMode & ~0o222, `readonly projection ${rel}`);
  }
});

for (const kind of ['missing-member', 'directory-mode', 'file-bytes', 'receipt-source-mode', 'receipt-member', 'receipt-deployed-mode']) {
  test(`AST adapter precisely refuses ${kind}`, async () => {
    const dependency = structuredClone(seed), directory = path.join(seed.artifacts, dirRel), file = path.join(seed.artifacts, fileRel);
    const savedDirectory = path.join(evidence, 'saved-flatbuffers-pch');
    const mode = (await fs.stat(directory)).mode & 0o777, bytes = await fs.readFile(file), fileMode = (await fs.stat(file)).mode & 0o777;
    try {
      if (kind === 'missing-member') await fs.rename(directory, savedDirectory);
      if (kind === 'directory-mode') await fs.chmod(directory, mode | 0o200);
      if (kind === 'file-bytes') { await fs.chmod(file, fileMode | 0o200); await fs.writeFile(file, Buffer.concat([bytes, Buffer.from('\n// sdk945 mutation\n')])); await fs.chmod(file, fileMode); }
      if (kind === 'receipt-source-mode') dependency.files[dirRel].sourceMode ^= 0o200;
      if (kind === 'receipt-member') delete dependency.files[dirRel];
      if (kind === 'receipt-deployed-mode') dependency.files[dirRel].mode |= 0o200;
      const result = await invocation(kind, dependency);
      console.log(`AST_REJECTION_TARGET_ASSERT_REACHED case=${kind} actual_rc=${result.rc} directory=${result.directory}`);
      assert.equal(result.rc, 1, `${kind}: real AST adapter must reject the illegal dependency`);
      assert.match(result.log, /SDK_MANIFEST_REJECT rule=DEPENDENCY_DIGEST/, `${kind}: rejection must reach the dependency assertion`);
      assert.doesNotMatch(result.log, /"command".*cmake/, 'illegal dependency must be rejected before CMake');
    } finally {
      if (kind === 'missing-member') await fs.rename(savedDirectory, directory);
      if (kind === 'directory-mode') await fs.chmod(directory, mode);
      if (kind === 'file-bytes') { await fs.chmod(file, fileMode | 0o200); await fs.writeFile(file, bytes); await fs.chmod(file, fileMode); }
    }
  });
}

test('official producer target retains authenticated directory source modes', async () => {
  const result = await invocation('official-producer', seed, official);
  console.log(`OFFICIAL_DIRECTORY_TARGET_ASSERT_REACHED actual_rc=${result.rc} directory=${result.directory}`);
  assert.equal(result.rc, 0, 'regular official producer must seal and read its directory receipt');
  const output = await readJson(path.join(result.directory, 'output.json'));
  const lock = await readJson(official.source.lock);
  for (const [rel, row] of Object.entries(lock.source_layout).filter(([, row]) => row.type === 'directory')) {
    assert.equal(output.files[rel]?.sourceMode, row.mode, `publisher source mode ${rel}`);
    assert.equal(output.files[rel]?.mode, row.mode & ~0o222, `readonly deployed mode ${rel}`);
  }
});

test('unrelated genuine official compiler remains an independent control', async () => {
  const child = spawnSync(path.join(seed.artifacts, 'bin/cjc'), ['--version'], {encoding: 'utf8'});
  await fs.writeFile(path.join(evidence, 'compiler-control.json'), canonical({rc: child.status, stdout: child.stdout, stderr: child.stderr}));
  console.log(`AST_INDEPENDENT_CONTROL_ASSERT_REACHED actual_rc=${child.status}`);
  assert.equal(child.status, 0, child.stderr);
  assert.match(child.stdout, /1\.3\.0-alpha\.20261009001050/);
  assert.equal(await fileDigest(path.join(seed.artifacts, 'bin/cjc')), seed.files['bin/cjc'].sha256);
});

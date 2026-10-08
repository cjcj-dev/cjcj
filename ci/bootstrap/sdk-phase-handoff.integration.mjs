#!/usr/bin/env zx
// Run against a retained complete-plan fixture; every observation comes from
// the production CLI, without rebuilding the already completed producers.
import assert from 'node:assert/strict';
import fs from 'node:fs/promises';
import path from 'node:path';
import {fileURLToPath} from 'node:url';
import {execFile} from 'node:child_process';
import {promisify} from 'node:util';
import test from 'node:test';

const exec = promisify(execFile);
const here = path.dirname(fileURLToPath(import.meta.url));
const product = process.env.SDK_PHASE_PRODUCT_ROOT || here;
const fixture = process.env.SDK_PHASE_OBSERVATION;
if (!fixture) throw new Error('SDK_PHASE_OBSERVATION must name the retained complete-plan fixture');
const observation = JSON.parse(await fs.readFile(fixture, 'utf8'));
const original = JSON.parse(await fs.readFile(path.join(path.dirname(fixture), 'bundle.frozen.json'), 'utf8'));
const root = await fs.mkdtemp(path.join(path.dirname(fixture), 'handoff-'));
const command = async (...args) => {
  try { const result = await exec(process.execPath, args); return {...result, rc: 0}; }
  catch (error) { return {rc: error.code, stdout: error.stdout, stderr: error.stderr}; }
};
const directories = result => Object.fromEntries(JSON.parse(result.stdout.trim().split('\n').at(-1)).components
  .map(component => [component.component, component.directory]));
const expected = Object.fromEntries(Object.entries(observation.expected).map(([id, identity]) => [id, identity.directory]));

test('direct complete plan retains the independent producer identity control', async () => {
  const plan = path.join(root, 'direct.json'); await fs.writeFile(plan, JSON.stringify(observation.plan));
  const result = await command(path.join(product, 'toolchain-sdk.mjs'), '--plan', plan, '--out', path.join(root, 'direct-sdk'), '--dry-run');
  assert.equal(result.rc, 0, result.stderr);
  console.log(`TARGET_ASSERTION_EXECUTED direct-identities actual=${JSON.stringify(directories(result))}`);
  assert.deepEqual(directories(result), expected, 'direct producer identities');
});

test('generated complete bundle delivers the selected phase identities to the real SDK entry', async () => {
  const input = path.join(root, 'complete.json'), bundle = path.join(root, 'generated.json');
  const phases = structuredClone(original);
  phases.phases.stage2.buildRoot = path.join(root, 'stage2-distinct-producers');
  await fs.writeFile(input, JSON.stringify(phases));
  const prepared = await command(path.join(product, 'prepare-bootstrap-plans.mjs'), '--plans', input, '--out', bundle);
  assert.equal(prepared.rc, 0, prepared.stderr);
  const selected = await command(path.join(product, 'bootstrap-sdk.mjs'), '--plans', bundle,
    '--phase', 'stage1-initial', '--out', path.join(root, 'phase-sdk'), '--dry-run');
  assert.equal(selected.rc, 0, selected.stderr);
  const actual = directories(selected);
  console.log(`TARGET_ASSERTION_EXECUTED phase-identities actual=${JSON.stringify(actual)}`);
  assert.deepEqual(actual, expected, 'generated bundle must deliver the frozen stage1 producer directories');
  await assert.rejects(fs.access(path.join(root, 'phase-sdk')));
});

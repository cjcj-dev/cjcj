#!/usr/bin/env zx
// Exercise the actual frozen-plan qualification entry; this never mints outputs.
import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs/promises';
import {buildIdentities} from './sdk-manifest.mjs';
import {qualificationRecipe} from './sdk-cjdb-qualification.mjs';
const template = JSON.parse(await fs.readFile(process.env.SDK_CJDB_GRAPH_PLAN, 'utf8'));
const component = plan => plan.components.find(row => row.producer.adapter === 'llvm-cjdb');
const accepted = () => {
  const plan = structuredClone(template);
  component(plan).source.commit = '872b162de7a8806760fb1194764b4b8f0c605e1a';
  component(plan).source.tree = '5c1ec3863e64f3f3db2977991394e2183779d5b7';
  return plan;
};
test('frozen identity entry accepts exactly the new fixed native graph', () => {
  const plan = accepted(), row = component(plan);
  const identities = buildIdentities(plan), recipe = qualificationRecipe(row);
  console.log('CJDB_NEW_GRAPH_ASSERT_REACHED', JSON.stringify(recipe.llvm), identities.get(row.id).buildId);
  assert.deepEqual(recipe.llvm, {commit: row.source.commit, tree: row.source.tree});
  assert.equal(recipe.compiler.commit, '174db8f40d5efddee63c47a3162bbf676bc227a0');
  assert.equal(recipe.bounds.commit, '2ae82839ecaaa7d031e66ccbd2076d671acfd615');
  assert.ok(identities.get(row.id).buildId.includes(row.source.commit));
});
for (const [name, change] of [
  ['wrong LLVM commit', row => {row.source.commit = '0'.repeat(40);}],
  ['wrong LLVM tree', row => {row.source.tree = '0'.repeat(40);}],
  ['wrong compiler commit', row => {row.config.options.compilerSource.commit = '0'.repeat(40);}],
  ['wrong bounds commit', row => {row.config.options.boundscheckSource.commit = '0'.repeat(40);}],
  ['historical graph cannot produce a new recipe', row => {row.source.commit = '53ce96a7b9d243dc7fa05ff6a9b56ea0ef94c057'; row.source.tree = '3d80836504be22f5b06228db0e2c39c2d0d11c81';}],
]) test(`frozen identity entry refuses ${name}`, () => {
  const plan = accepted(); change(component(plan));
  console.log('CJDB_SCOPE_REFUSAL_ASSERT_REACHED', name);
  assert.throws(() => buildIdentities(plan), /CJDB_QUALIFICATION_SCOPE/);
});

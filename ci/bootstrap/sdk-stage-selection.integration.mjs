#!/usr/bin/env zx
import assert from 'node:assert/strict';
import fs from 'node:fs/promises';
import path from 'node:path';
import {fileURLToPath} from 'node:url';
import {execFile} from 'node:child_process';
import {promisify} from 'node:util';
import test from 'node:test';

const exec = promisify(execFile);
const here = path.dirname(fileURLToPath(import.meta.url));
if (!process.env.SDK_STAGE_PLAN) throw new Error('SDK_STAGE_PLAN must identify the genuine retained stage compiler input plan');
const original = JSON.parse(await fs.readFile(process.env.SDK_STAGE_PLAN, 'utf8'));
const root = await fs.mkdtemp(path.join(path.dirname(process.env.SDK_STAGE_PLAN), 'selection-'));
const stage = original.components.find(component => component.producer.adapter === 'bootstrap-compiler');
if (!stage) throw new Error('stage compiler producer absent');
async function invoke(plan, name, dry = true) {
  const input = path.join(root, `${name}.json`); await fs.writeFile(input, JSON.stringify(plan));
  const argv = [path.join(here, 'toolchain-sdk.mjs'), '--plan', input, '--out', path.join(root, `${name}-sdk`), ...(dry ? ['--dry-run'] : [])];
  try { return {...await exec(process.execPath, argv), rc: 0}; }
  catch (error) { return {stdout: error.stdout, stderr: error.stderr, rc: error.code}; }
}
test('host distribution and installed target compiler select one native stage input', async () => {
  const result = await invoke(original, 'normal');
  console.log(`TARGET_ASSERTION_EXECUTED stage-normal rc=${result.rc}`);
  assert.equal(result.rc, 0, result.stderr);
  assert.equal(JSON.parse(result.stdout).components.find(component => component.component === stage.id).adapter, 'bootstrap-compiler');
});
test('two installed typed target compiler inputs are rejected by the real entry', async () => {
  const plan = structuredClone(original), compiler = plan.components.find(component => component.id === stage.config.options.sdkComponents.find(id => plan.components.find(row => row.id === id)?.roles.includes('compiler') && plan.components.find(row => row.id === id)?.domain === 'target'));
  const second = structuredClone(compiler); second.id = 'second-compiler'; plan.components.push(second);
  const producer = plan.components.find(component => component.id === stage.id);
  producer.dependencies.push(second.id); producer.config.options.sdkComponents.push(second.id);
  const result = await invoke(plan, 'two-targets');
  console.log(`TARGET_ASSERTION_EXECUTED stage-two-targets rc=${result.rc} diagnostic=${result.stderr.trim()}`);
  assert.notEqual(result.rc, 0); assert.match(result.stderr, /DEPENDENCY_ROLE.*exactly one installed compiler/);
});
test('stage3 rejects the stage1 adapter as its parent through the real entry', async () => {
  const plan = structuredClone(original); plan.stage = 'final';
  plan.components.find(component => component.id === stage.id).config.options.stage = 'stage3';
  const result = await invoke(plan, 'wrong-parent');
  console.log(`TARGET_ASSERTION_EXECUTED stage-wrong-parent rc=${result.rc} diagnostic=${result.stderr.trim()}`);
  assert.notEqual(result.rc, 0); assert.match(result.stderr, /DEPENDENCY_ROLE.*actual stage2 compiler/);
});
test('noncompiler role cannot install a second physical compiler through authenticated assembly', async () => {
  const plan = structuredClone(original);
  plan.components = plan.components.filter(component => component.id !== stage.id);
  for (const component of plan.components) delete component.inputOnly;
  const runtime = plan.components.find(component => component.roles.includes('runtime') && component.domain === 'target');
  runtime.install.push({from: `install/runtime/lib/${plan.platform}_cjnative/libcangjie-runtime.so`, to: 'bin/cjc'});
  const result = await invoke(plan, 'physical-conflict', false);
  console.log(`TARGET_ASSERTION_EXECUTED stage-physical-conflict rc=${result.rc} diagnostic=${result.stderr.trim()}`);
  assert.notEqual(result.rc, 0); assert.match(result.stderr, /DUPLICATE_INSTALL.*bin\/cjc/);
  await assert.rejects(fs.access(path.join(root, 'physical-conflict-sdk')));
});

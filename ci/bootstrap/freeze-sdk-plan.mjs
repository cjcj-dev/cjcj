#!/usr/bin/env zx
// Resolve mutable selectors once, before the production entry sees a plan.
import fs from 'node:fs/promises';
import path from 'node:path';
import {parseArgs} from 'node:util';
import {fileURLToPath} from 'node:url';
import {PLAN_SCHEMA, validatePlan, buildIdentities, readJson, execute, fileDigest,
  canonical, reject, absolute} from './sdk-manifest.mjs';

async function gitInput(input, label) {
  absolute(input.repo, label);
  if (!input.ref && (!input.commit || !input.tree)) reject('FREEZE_INPUT', label, 'explicit Git ref or complete commit/tree required');
  const ref = input.ref || input.commit;
  if (typeof ref !== 'string' || !ref || ref.startsWith('-') || /[\0\r\n]/.test(ref)) reject('FREEZE_INPUT', label, 'invalid Git selector');
  const read = async suffix => (await execute('git', ['-C', input.repo, 'rev-parse', '--verify', `${ref}${suffix}`])).stdout.trim();
  const commit = await read('^{commit}'), tree = await read('^{tree}');
  if ((input.commit && input.commit !== commit) || (input.tree && input.tree !== tree)) reject('FREEZE_INPUT', label, 'provided source identity differs from repository');
  return {repo: await fs.realpath(input.repo), commit, tree};
}
async function frozenFile(input, label) {
  absolute(input.path, label);
  const file = await fs.realpath(input.path), digest = await fileDigest(file);
  if (input.sha256 && input.sha256 !== digest) reject('FREEZE_INPUT', label, 'provided digest differs from actual input');
  return {path: file, sha256: digest};
}
export async function freezeSdkPlan(intent) {
  if (intent.schema !== 'toolchain-sdk-intent-v1') reject('FREEZE_INPUT', 'intent', 'unknown intent version');
  const plan = structuredClone(intent); plan.schema = PLAN_SCHEMA;
  for (const component of plan.components || []) {
    if (component.source.kind === 'git') component.source = {kind: 'git', ...await gitInput(component.source, component.id)};
    else if (component.source.kind === 'distribution') {
      const locked = await frozenFile({path: component.source.lock, sha256: component.source.lockSha256}, component.id);
      const lock = await readJson(locked.path);
      if (component.source.version !== lock.version) reject('FREEZE_INPUT', component.id, 'distribution version differs from pre-existing lock');
      component.source.lock = locked.path; component.source.lockSha256 = locked.sha256;
      component.source.root = await fs.realpath(component.source.root);
    }
    const producer = component.producer;
    if (producer.repository) {
      const identity = await gitInput({repo: producer.repository, ref: producer.ref || producer.version}, `${component.id}/producer`);
      if (producer.version && producer.version !== identity.commit) reject('FREEZE_INPUT', component.id, 'producer version differs');
      if ((await execute('git', ['-C', identity.repo, 'status', '--porcelain', '--untracked-files=all'])).stdout.trim()) reject('FREEZE_INPUT', component.id, 'producer repository is dirty');
      producer.repository = identity.repo; producer.version = identity.commit;
      delete producer.ref;
    }
    if (producer.engine) {
      const locked = await frozenFile({path: producer.engine, sha256: producer.engineSha256}, `${component.id}/engine`);
      producer.engine = locked.path; producer.engineSha256 = locked.sha256;
    }
    for (const [name, value] of Object.entries(component.config.tools || {})) component.config.tools[name] = await frozenFile(value, `${component.id}/${name}`);
    for (const name of ['compilerSource', 'flatbuffersSource']) {
      if (component.config.options[name]) component.config.options[name] = await gitInput(component.config.options[name], `${component.id}/${name}`);
    }
  }
  for (const [name, value] of Object.entries(plan.verification || {})) {
    if (value?.path) plan.verification[name] = await frozenFile(value, name);
  }
  validatePlan(plan);
  return {plan, identities: Object.fromEntries(buildIdentities(plan))};
}
export async function main(args = process.argv.slice(2)) {
  const {values} = parseArgs({args, options: {intent: {type: 'string'}, out: {type: 'string'}}});
  if (!values.intent || !values.out) throw new Error('usage: freeze-sdk-plan.mjs --intent INPUT_JSON --out NEW_FROZEN_JSON');
  const {plan, identities} = await freezeSdkPlan(await readJson(values.intent));
  await fs.writeFile(values.out, canonical(plan), {flag: 'wx'});
  console.log(canonical({plan: path.resolve(values.out), identities}).trim());
}
if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  try { await main(); } catch (error) { console.error(error.message); process.exitCode = 1; }
}

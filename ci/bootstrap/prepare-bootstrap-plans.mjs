#!/usr/bin/env zx
// Resolve every phase once at the production boundary, before any build.
import fs from 'node:fs/promises';
import path from 'node:path';
import {parseArgs} from 'node:util';
import {fileURLToPath} from 'node:url';
import {freezeBootstrapPlans} from './freeze-bootstrap-plans.mjs';
import {readBootstrapPlans} from './bootstrap-sdk.mjs';
import {readJson, canonical, reject, objectId, withLock} from './sdk-manifest.mjs';

export async function prepareBootstrapPlans({plans, intents, out}) {
  if (Boolean(plans) === Boolean(intents)) reject('BOOTSTRAP_PHASES', 'input', 'exactly one complete frozen bundle or complete intent bundle is required');
  const bundle = plans ? await readBootstrapPlans(plans) : await freezeBootstrapPlans(await readJson(intents));
  if (!out) reject('BOOTSTRAP_PHASES', 'output', 'explicit bundle destination required');
  out = path.resolve(out);
  await fs.mkdir(path.dirname(out), {recursive: true});
  // A job retry may reuse its already frozen selectors. It may not overwrite
  // a different graph under the same path or regenerate a stage silently.
  await withLock(`${out}.lock`, async () => {
    try {
      const existing = await readBootstrapPlans(out);
      if (canonical(existing) !== canonical(bundle)) reject('BOOTSTRAP_PHASES', 'output', 'existing bundle differs; choose a new identity directory');
    } catch (error) {
      if (error.code !== 'ENOENT') throw error;
      await fs.writeFile(out, canonical(bundle), {flag: 'wx'});
    }
  });
  return {plans: out, sha256: objectId(bundle), phases: Object.keys(bundle.phases)};
}

export async function prepareBootstrapEnvironment(env = process.env) {
  const result = await prepareBootstrapPlans({plans: env.CJCJ_BOOTSTRAP_SDK_PLANS,
    intents: env.CJCJ_BOOTSTRAP_SDK_INTENTS, out: env.CJCJ_BOOTSTRAP_SDK_BUNDLE_OUT
      || (env.CANGJIE_WORKSPACE && path.join(env.CANGJIE_WORKSPACE, 'sdk-plans', 'bootstrap.json'))});
  if (env.GITHUB_ENV) await fs.appendFile(env.GITHUB_ENV, `CJCJ_BOOTSTRAP_SDK_PLANS=${result.plans}\nCJCJ_BOOTSTRAP_SDK_INTENTS=\n`);
  return result;
}
if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  try {
    const {values} = parseArgs({options: {plans: {type: 'string'}, intents: {type: 'string'}, out: {type: 'string'}, env: {type: 'boolean'}, 'path-only': {type: 'boolean'}}});
    const result = values.env ? await prepareBootstrapEnvironment() : await prepareBootstrapPlans(values);
    console.log(values['path-only'] ? result.plans : `BOOTSTRAP_PLANS_PREPARED ${canonical(result).trim()}`);
  } catch (error) { console.error(error.message); process.exitCode = 1; }
}

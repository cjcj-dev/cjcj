#!/usr/bin/env zx
import path from 'node:path';
import fs from 'node:fs/promises';
import {parseArgs} from 'node:util';
import {fileURLToPath} from 'node:url';
import {assembleSdk, verifyManifestSdk} from './toolchain-sdk.mjs';
import {readJson, objectId, fileDigest, reject, validatePlan} from './sdk-manifest.mjs';
import {validateBootstrapPlans, BOOTSTRAP_PHASES} from './freeze-bootstrap-plans.mjs';
export async function readBootstrapPlans(plans) {
  let input;
  if ((await fs.stat(plans)).isDirectory()) {
    const phases = {};
    for (const name of BOOTSTRAP_PHASES) {
      try { phases[name] = await readJson(path.join(plans, `${name}.json`)); }
      catch (error) { if (error.code !== 'ENOENT') throw error; reject('BOOTSTRAP_PHASES', name, 'frozen phase file missing'); }
    }
    input = {schema: 'bootstrap-sdk-plans-v1', phases};
  } else input = await readJson(plans);
  return validateBootstrapPlans(input);
}
export async function assembleBootstrapPhase({plans, phase, out, dryRun = false}) {
  if (!BOOTSTRAP_PHASES.includes(phase)) reject('BOOTSTRAP_PHASE', phase, 'unknown stage');
  const bundle = await readBootstrapPlans(plans), plan = bundle.phases[phase];
  validatePlan(plan);
  if (dryRun) return assembleSdk(plan, out, {dryRun});
  try {
    const lock = await readJson(path.join(out, 'SDK.lock.json'));
    if (lock.plan_sha256 !== objectId(plan)) reject('BOOTSTRAP_PHASE', phase, 'existing SDK belongs to another frozen plan; use a distinct destination');
    await verifyManifestSdk(out, plan, await readJson(path.join(out, 'SDK.manifest.json')));
    return {out, reused: true, planSha256: objectId(plan), lockSha256: await fileDigest(path.join(out, 'SDK.lock.json'))};
  } catch (error) { if (error.code !== 'ENOENT') throw error; }
  return assembleSdk(plan, out);
}
if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  try {
    const {values} = parseArgs({options: {plans: {type: 'string'}, phase: {type: 'string'}, out: {type: 'string'}, 'dry-run': {type: 'boolean', default: false}}});
    if (!values.plans || !values.phase || !values.out) throw new Error('usage: bootstrap-sdk.mjs --plans DIR --phase PHASE --out DIR [--dry-run]');
    console.log(JSON.stringify(await assembleBootstrapPhase({plans: values.plans, phase: values.phase, out: values.out, dryRun: values['dry-run']})));
  } catch (error) { console.error(error.message); process.exitCode = 1; }
}

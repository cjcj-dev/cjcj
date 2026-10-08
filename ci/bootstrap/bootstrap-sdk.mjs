#!/usr/bin/env zx
import path from 'node:path';
import fs from 'node:fs/promises';
import {parseArgs} from 'node:util';
import {fileURLToPath} from 'node:url';
import {assembleSdk, verifyManifestSdk} from './toolchain-sdk.mjs';
import {readJson, objectId, fileDigest, reject, validatePlan} from './sdk-manifest.mjs';
export async function assembleBootstrapPhase({plans, phase, out, dryRun = false}) {
  if (!['stage0', 'stage0-run', 'std-bootstrap', 'stage1-initial', 'stage1-std', 'stage3'].includes(phase)) reject('BOOTSTRAP_PHASE', phase, 'unknown stage');
  let plan;
  if ((await fs.stat(plans)).isDirectory()) plan = await readJson(path.join(plans, `${phase}.json`));
  else {
    const bundle = await readJson(plans);
    if (bundle.schema !== 'bootstrap-sdk-plans-v1' || !bundle.phases?.[phase]) reject('BOOTSTRAP_PHASE', phase, 'complete frozen phase plan missing');
    plan = bundle.phases[phase];
  }
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

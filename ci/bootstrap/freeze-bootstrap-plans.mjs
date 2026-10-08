#!/usr/bin/env zx
// Freeze the complete phase bundle before bootstrap can start any producer.
import fs from 'node:fs/promises';
import path from 'node:path';
import {parseArgs} from 'node:util';
import {fileURLToPath} from 'node:url';
import {freezeSdkPlan} from './freeze-sdk-plan.mjs';
import {canonical, readJson, reject, validatePlan} from './sdk-manifest.mjs';

export const BOOTSTRAP_PHASES = Object.freeze([
  'stage0', 'stage0-run', 'std-bootstrap', 'stage1-initial', 'stage1-std', 'stage2', 'stage3-std', 'stage3',
]);
export function validateBootstrapPlans(bundle) {
  if (bundle?.schema !== 'bootstrap-sdk-plans-v1' || !bundle.phases
    || Object.keys(bundle).some(key => !['schema', 'phases'].includes(key))
    || canonical(Object.keys(bundle.phases).sort()) !== canonical([...BOOTSTRAP_PHASES].sort())) {
    reject('BOOTSTRAP_PHASES', 'bundle', 'the complete eight-phase frozen bundle is required');
  }
  const identities = new Map();
  for (const phase of BOOTSTRAP_PHASES) {
    const plan = validatePlan(bundle.phases[phase]);
    const owner = `${plan.lane}:${plan.platform}`;
    if (identities.size && !identities.has(owner)) reject('BOOTSTRAP_PHASES', phase, 'phase owner/platform differs');
    identities.set(owner, true);
    const expectedRole = ['stage0', 'stage0-run', 'std-bootstrap'].includes(phase) ? 'host' : 'target';
    if (plan.role !== expectedRole) reject('BOOTSTRAP_PHASES', phase, `requires ${expectedRole} domain`);
    if (phase === 'stage3' && plan.stage !== 'final') reject('BOOTSTRAP_PHASES', phase, 'stage3 requires a final-stage plan');
    if (phase !== 'stage3' && plan.stage === 'final') reject('BOOTSTRAP_PHASES', phase, 'an intermediate SDK cannot declare final qualification');
    if (['stage2', 'stage3-std'].includes(phase) && plan.stage !== 'stage2') reject('BOOTSTRAP_PHASES', phase, 'requires a stage2 consumer plan');
  }
  return bundle;
}
export async function freezeBootstrapPlans(intent) {
  if (intent?.schema !== 'bootstrap-sdk-intents-v1' || !intent.phases
    || Object.keys(intent).some(key => !['schema', 'phases'].includes(key))
    || canonical(Object.keys(intent.phases).sort()) !== canonical([...BOOTSTRAP_PHASES].sort())) {
    reject('BOOTSTRAP_PHASES', 'intent', 'all eight phase intents must be declared before freezing');
  }
  const phases = {};
  // Resolve all selectors now. Build adapters still own their normal DAGs;
  // freezing never executes a producer or backfills an artifact identity.
  for (const phase of BOOTSTRAP_PHASES) phases[phase] = (await freezeSdkPlan(intent.phases[phase])).plan;
  return validateBootstrapPlans({schema: 'bootstrap-sdk-plans-v1', phases});
}
if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  try {
    const {values} = parseArgs({options: {intent: {type: 'string'}, out: {type: 'string'}}});
    if (!values.intent || !values.out) throw new Error('usage: freeze-bootstrap-plans.mjs --intent SIX_PHASE_INTENTS --out NEW_BUNDLE');
    const bundle = await freezeBootstrapPlans(await readJson(values.intent));
    await fs.writeFile(values.out, canonical(bundle), {flag: 'wx'});
    console.log(`BOOTSTRAP_PLANS_FROZEN phases=${BOOTSTRAP_PHASES.length} out=${path.resolve(values.out)}`);
  } catch (error) { console.error(error.message); process.exitCode = 1; }
}

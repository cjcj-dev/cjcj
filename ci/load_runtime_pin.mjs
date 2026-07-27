#!/usr/bin/env zx

import fs from 'node:fs/promises';
import {resolveRuntimeSource} from './runtime-pin.mjs';

const githubEnv = process.env.GITHUB_ENV;
if (!githubEnv) throw new Error('GITHUB_ENV is required');

const pins = await resolveRuntimeSource();
const environment = [
  `RUNTIME_REF=${pins.runtimeRef}`,
  `RUNTIME_VERSION=${pins.RUNTIME_VERSION}`,
  `RUNTIME_SRC_URL=${pins.sourceUrl}`,
];
if (pins.overrideRef) {
  environment.push(`CJCJ_RUNTIME_REF_OVERRIDE=${pins.overrideRef}`);
  environment.push('CJCJ_ALLOW_RUNTIME_OVERRIDE=true');
}
await fs.appendFile(githubEnv, `${environment.join('\n')}\n`);
console.log(`[runtime] selected ref=${pins.runtimeRef} pin=${pins.pinRef} `
  + `override=${pins.overrideRef || '<none>'}`);

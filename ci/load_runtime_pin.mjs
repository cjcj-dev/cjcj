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
if (pins.nativePair) {
  environment.push(`CJCJ_NATIVE_LLVM_REF=${pins.nativePair.llvm}`);
  environment.push(`CJCJ_NATIVE_RUNTIME_REF=${pins.nativePair.runtime}`);
  environment.push(`CJCJ_NATIVE_HOST_VERSION=${pins.nativePair.hostVersion}`);
}
await fs.appendFile(githubEnv, `${environment.join('\n')}\n`);
console.log(`[runtime] selected ref=${pins.runtimeRef} pin=${pins.pinRef} `
  + `override=${pins.overrideRef || '<none>'} native_pair=${pins.nativePair?.llvm || '<none>'}`);

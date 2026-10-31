#!/usr/bin/env zx
import fs from 'node:fs';
import {nativePair} from '../runtime-pin.mjs';
import {getReleasePlatform, getTarget, releasePlatformReadiness} from '../../build/lib/targets.mjs';
const host = process.env.RELEASE_PLATFORM;
if (!host) throw new Error('RELEASE_PLATFORM is required');
const key = process.env.RELEASE_KEY;
let archiveKey = host;
if (key) {
  const release = getReleasePlatform(key);
  if (release.host !== host) throw new Error('release key/host mismatch');
  archiveKey = release.archiveKey;
}
const readiness = releasePlatformReadiness(key || getTarget(host).spec.packageHost.join('-'),{nativeInputs:Boolean(process.env.CJCJ_NATIVE_RUNTIME_ARTIFACT && nativePair())});
if (!readiness.sdkSourceTarget) throw new Error('NATIVE_SDK_PRODUCER_MISSING ' + host + ': ' + readiness.reasons.join('; '));
if (!process.env.GITHUB_ENV) throw new Error('GITHUB_ENV is required');
fs.appendFileSync(process.env.GITHUB_ENV, `PACKAGE_KEY=${archiveKey}\n`);
console.log(`PACKAGE_KEY=${archiveKey}`);

#!/usr/bin/env node
import fs from 'node:fs';
import {getReleasePlatform} from '../../build/lib/targets.mjs';
const host = process.env.RELEASE_PLATFORM;
if (!host) throw new Error('RELEASE_PLATFORM is required');
const key = process.env.RELEASE_KEY;
let archiveKey = host;
if (key) {
  const release = getReleasePlatform(key);
  if (release.host !== host) throw new Error('release key/host mismatch');
  archiveKey = release.archiveKey;
}
if (!process.env.GITHUB_ENV) throw new Error('GITHUB_ENV is required');
fs.appendFileSync(process.env.GITHUB_ENV, `PACKAGE_KEY=${archiveKey}\n`);
console.log(`PACKAGE_KEY=${archiveKey}`);

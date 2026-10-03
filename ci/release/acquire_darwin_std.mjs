#!/usr/bin/env node
import fs from 'node:fs';
import path from 'node:path';
import {spawnSync} from 'node:child_process';
import assert from 'node:assert/strict';
import {acquire} from './bootstrap_store.mjs';
import {digest} from './colour_runtime.mjs';
import {verifyDarwinStd} from './darwin_std.mjs';

const [root, platform] = process.argv.slice(2);
const release = JSON.parse(fs.readFileSync(new URL('../colour-runtime/release.json', import.meta.url)));
const pin = release.platforms?.[platform]?.std;
assert.ok(pin, `COLOUR_RT_STD_PROVENANCE_MISSING: ${platform}`);
const work = path.join(process.env.RUNNER_TEMP, `darwin-std-${platform}`);
const input = await acquire(pin.transport, work);
const unpacked = path.join(work, 'unpacked');
fs.mkdirSync(unpacked, {recursive: true});
const result = spawnSync('tar', ['-xzf', path.join(input, pin.archive), '-C', unpacked], {stdio: 'inherit'});
assert.equal(result.status, 0, 'COLOUR_RT_STD_ARCHIVE');
verifyDarwinStd(unpacked, platform, pin, digest(path.join(root, 'manifest.json')));
const manifest = JSON.parse(fs.readFileSync(path.join(unpacked, 'std-manifest.json')));
for (const file of [...Object.keys(manifest.files), 'std-manifest.json']) {
  const output = path.join(root, file);
  fs.mkdirSync(path.dirname(output), {recursive: true});
  fs.copyFileSync(path.join(unpacked, file), output);
}
verifyDarwinStd(root, platform, pin, digest(path.join(root, 'manifest.json')));

// Real runtime artifacts only; this does not qualify final std or a release SDK.
import assert from 'node:assert/strict';
import crypto from 'node:crypto';
import fs from 'node:fs/promises';
import path from 'node:path';
import {iosTargets} from '../srcbuild/lib/ios-runtime.mjs';
import {installCrossRuntime} from './cross-runtime.mjs';
const target = iosTargets.find(entry => entry.target === process.env.IOS_TARGET);
assert.ok(target, 'known iOS target');
const source = path.join(process.env.CANGJIE_WORKSPACE, 'cangjie_runtime');
const root = path.join(source, 'runtime-install');
const digest = async file => crypto.createHash('sha256').update(await fs.readFile(file)).digest('hex');
const expected = await digest(path.join(source, 'runtime', 'CMakebuild', 'runtime-staging', 'lib', `${target.runtimeArch}_Release`, 'libboundscheck.dylib'));
const actual = await digest(path.join(root, 'runtime', 'lib', target.tuple, 'libboundscheck.dylib'));
console.log(`IOS_BOUNDSCHECK_OBSERVED actual=${actual} expected=${expected}`);
assert.equal(actual, expected, 'IOS_BOUNDSCHECK_SAME_BUILD_BYTES');
const stage = path.join(source, 'installed-sdk');
const record = await installCrossRuntime({root, stage, tuple: target.tuple, runtimeRef: process.env.RUNTIME_REF});
const produced = [], installed = [];
for (const file of record.files) {
  produced.push({path: file.path, sha256: await digest(path.join(root, file.path))});
  installed.push({path: file.path, sha256: await digest(path.join(stage, file.path)).catch(() => 'MISSING')});
}
console.log(`IOS_INSTALLED_OBSERVED ${JSON.stringify({produced, installed})}`);
assert.deepEqual(installed, produced, 'IOS_INSTALLED_RUNTIME_BYTES');
console.log(`IOS_RUNTIME_BYTES_PASS tuple=${target.tuple}`);

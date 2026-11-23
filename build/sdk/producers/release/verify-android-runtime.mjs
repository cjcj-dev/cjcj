// Run after the real Android producer; compare its installed bytes with this build.
import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import fs from 'node:fs/promises';
import path from 'node:path';
const runtime = path.join(process.env.CANGJIE_WORKSPACE, 'cangjie_runtime', 'runtime');
const tuple = 'linux_android_aarch64_cjnative';
const root = path.join(runtime, 'output', 'common', 'linux_android_release_aarch64');
const digest = async file => createHash('sha256').update(await fs.readFile(file)).digest('hex');
const expected = await digest(path.join(runtime, 'CMakebuild', 'runtime-staging', 'lib', 'aarch64_Release', 'libboundscheck.so'));
const actual = await digest(path.join(root, 'runtime', 'lib', tuple, 'libboundscheck.so'));
console.log(`ANDROID_BOUNDSCHECK_OBSERVED actual=${actual} expected=${expected}`);
assert.equal(actual, expected, 'ANDROID_BOUNDSCHECK_SAME_BUILD_BYTES');
console.log('ANDROID_BOUNDSCHECK_SAME_BUILD_BYTES PASS');

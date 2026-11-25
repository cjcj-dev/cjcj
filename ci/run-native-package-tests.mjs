#!/usr/bin/env zx
import fs from 'node:fs/promises';
import path from 'node:path';
import os from 'node:os';
import {command} from './bootstrap/sdk-flow.mjs';
import {selectBuildResources} from './build-resources.mjs';
import {colourEnvironment} from './prepare-colour-sdk.mjs';
import {resolveProductBinary} from '../build/sdk/producers/srcbuild/lib/product-binary.mjs';
try {
  const env = await colourEnvironment('build');
  const work = env.RUNNER_TEMP;
  if (!work) throw new Error('RUNNER_TEMP required');
  await command(['npx', '--yes', 'zx@8', 'runtime_shim/build_shim.mjs'], {env});
  const output = path.join(work, 'objc-producer');
  // The producer is the compiler itself; build it with the same heap selection as sdk-native-stage, since
  // the compiler-only 4GB default cannot hold packages such as cjcj::chir. Tests keep their own environment.
  const {heap} = await selectBuildResources();
  await command(['cjpm', 'build', `-j${os.availableParallelism()}`, '--target-dir', output], {env: {...env, cjHeapSize: heap}});
  const product = await resolveProductBinary(path.join(output, 'release/bin'), 'ObjC preamble');
  env.OBJC_PREAMBLE_PRODUCER = path.join(work, 'cjcj-stage1');
  await fs.copyFile(product, env.OBJC_PREAMBLE_PRODUCER);
  await command([process.execPath, 'ci/run-registered-tests.mjs', 'cj', path.join(work, 'package-tests')], {env});
} catch (error) { console.error(error.stack); process.exitCode = error.rc || 1; }

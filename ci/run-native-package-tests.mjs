#!/usr/bin/env zx
import fs from 'node:fs/promises';
import path from 'node:path';
import os from 'node:os';
import {command} from './bootstrap/sdk-flow.mjs';
import {colourEnvironment} from './prepare-colour-sdk.mjs';
import {PRODUCT_NAMES} from './srcbuild/lib/product-binary.mjs';
try {
  const env = await colourEnvironment('build');
  const work = env.RUNNER_TEMP;
  if (!work) throw new Error('RUNNER_TEMP required');
  await command(['npx', '--yes', 'zx@8', 'runtime_shim/build_shim.mjs'], {env});
  const output = path.join(work, 'objc-producer');
  await command(['cjpm', 'build', `-j${os.availableParallelism()}`, '--target-dir', output], {env});
  const products = [];
  for (const name of PRODUCT_NAMES) {
    const file = path.join(output, 'release/bin', name);
    if (await fs.stat(file).then(row => row.isFile(), () => false)) products.push(file);
  }
  if (products.length !== 1) throw new Error(`OBJC_PRODUCER_COUNT ${products.length}`);
  env.OBJC_PREAMBLE_PRODUCER = path.join(work, 'cjcj-stage1');
  await fs.copyFile(products[0], env.OBJC_PREAMBLE_PRODUCER);
  await command([process.execPath, 'ci/run-registered-tests.mjs', 'cj', path.join(work, 'package-tests')], {env});
} catch (error) { console.error(error.stack); process.exitCode = error.rc || 1; }

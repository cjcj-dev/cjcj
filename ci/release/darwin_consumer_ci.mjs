#!/usr/bin/env zx
import path from 'node:path';
import {darwinConsumerHost, loadDarwinPins, consumeDarwinInputs} from './consume_darwin_inputs.mjs';
import {darwinCommand} from './darwin_commands.mjs';
try {
  const host = darwinConsumerHost();
  loadDarwinPins(host.platform);
  const work = path.resolve(process.argv[2]);
  if (process.env.DARWIN_BUILD_RUNTIME === 'true') {
    process.env.PLATFORM_CI_ROOT = path.join(work, 'platform-ci');
    darwinCommand(path.join(work, 'commands'), 'runtime-build', 'npx',
      ['--yes', 'zx@8', 'ci/platform_matrix/build_runtime.mjs']);
    process.env.CJCJ_BOOTSTRAP_COLOUR_RT = path.join(process.env.PLATFORM_CI_ROOT, 'runtime-install');
  }
  consumeDarwinInputs(work);
} catch (error) { console.error(error.stack); process.exitCode = error.exitCode || 1; }

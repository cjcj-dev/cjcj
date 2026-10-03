#!/usr/bin/env node
// Seed-only producer entry. Source SDK consumers retain verifyRuntime's std guard.
import assert from 'node:assert/strict';
import {prepareBootstrapInputs} from './prepare_bootstrap_inputs.mjs';
import {darwinRuntime} from './darwin_runtime.mjs';

const platforms = {'darwin-arm64': 'darwin_aarch64', 'darwin-x64': 'darwin_x86_64'};
const platform = platforms[process.env.CJCJ_SRCBUILD_TARGET];
assert.ok(platform, 'DARWIN_STD_NATIVE_TARGET_REQUIRED');
assert.equal(process.platform, 'darwin', 'DARWIN_STD_NATIVE_HOST_REQUIRED');
await prepareBootstrapInputs(() => darwinRuntime('verify', process.env.CJCJ_BOOTSTRAP_COLOUR_RT, platform));

#!/usr/bin/env zx
// Byte-only admission fixture, produced by the public SDK flow. No compiler runs.
import assert from 'node:assert/strict';
import fs from 'node:fs/promises';
import path from 'node:path';
import {fileURLToPath} from 'node:url';
import {spawnSync} from 'node:child_process';
const [sdkArgument, producerArgument] = process.argv.slice(2);
assert.ok(sdkArgument && producerArgument, 'usage: install_identity_fixture.mjs SDK PRODUCER');
const sdk = path.resolve(sdkArgument), producer = path.resolve(producerArgument);
const root = path.dirname(sdk), config = path.join(root, 'identity-fixture.json');
await fs.writeFile(config, JSON.stringify({
  work: path.join(root, 'identity-work'), install: sdk, repos: {}, finalStage: 'fixture',
  stages: [{id: 'fixture', output: sdk,
    copies: [{from: producer, to: 'bin/cjcj-stage1'},
      {from: path.join(sdk, 'envsetup.sh'), to: 'envsetup.sh'}],
    links: {'bin/cjc': 'cjcj-stage1', 'bin/cjc-frontend': 'cjcj-stage1'},
    metadata: {compilerFile: 'bin/cjcj-stage1'}}],
}));
const result = spawnSync(process.execPath, [fileURLToPath(new URL('../bootstrap/sdk-build.mjs', import.meta.url)),
  '--config', config, '--no-package'], {stdio: 'inherit'});
if (result.error) throw result.error;
if (result.signal) process.kill(process.pid, result.signal);
else process.exitCode = result.status;

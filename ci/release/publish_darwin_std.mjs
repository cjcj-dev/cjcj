#!/usr/bin/env node
import fs from 'node:fs';
import path from 'node:path';
import {spawnSync} from 'node:child_process';
import assert from 'node:assert/strict';
import {digest} from './bootstrap_store.mjs';

const platform = process.env.STD_PLATFORM;
assert.ok(['darwin_aarch64', 'darwin_x86_64'].includes(platform));
const root = process.env.STD_PACKAGE;
const archive = `darwin-std-${platform}.tar.gz`;
const files = [archive, 'std-manifest.json'].map(name => ({path: name, mode: 0o644,
  sha256: digest(fs.readFileSync(path.join(root, name)))}));
const list = path.join(process.env.RUNNER_TEMP, 'std-files.json');
const output = path.join(process.env.RUNNER_TEMP, 'std-transport-pin.json');
fs.writeFileSync(list, JSON.stringify(files));
const result = spawnSync(process.execPath, ['ci/release/publish_bootstrap_inputs.mjs', root, list, output],
  {env: process.env, stdio: 'inherit'});
assert.equal(result.status, 0, 'Darwin std publication/readback must complete');
const identity = JSON.parse(fs.readFileSync(path.join(process.env.RUNNER_TEMP, 'darwin-std-identity.json')));
identity.archive = archive;
identity.transport = JSON.parse(fs.readFileSync(output));
fs.writeFileSync(path.join(process.env.RUNNER_TEMP, 'darwin-std-pin.json'), JSON.stringify(identity, null, 2) + '\n');

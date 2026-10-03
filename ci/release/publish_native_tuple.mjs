#!/usr/bin/env node
import fs from 'node:fs';
import path from 'node:path';
import {spawnSync} from 'node:child_process';
import {api, digest} from './bootstrap_store.mjs';
import assert from 'node:assert/strict';

const platform = process.env.TUPLE_PLATFORM;
assert.ok(['darwin_aarch64', 'darwin_x86_64'].includes(platform));
const root = process.env.STATIC_TUPLE;
const manifest = fs.readFileSync(path.join(root, 'MANIFEST'), 'utf8');
assert.ok(manifest.split('\n').includes(`PLATFORM=${platform}`));
const sums = fs.readFileSync(path.join(root, 'SHA256SUMS'));
const files = sums.toString().trim().split('\n').map(line => {
  const match = /^([a-f0-9]{64})  \.\/(.+)$/.exec(line);
  assert.ok(match, 'invalid tuple manifest');
  return {path: match[2], sha256: match[1], mode: ['bin/llc', 'bin/opt', 'bin/ld64.lld'].includes(match[2]) ? 0o755 : 0o644};
});
files.push({path: 'SHA256SUMS', mode: 0o644, sha256: digest(sums)});
const artifactList = await (await api(`/repos/${process.env.GITHUB_REPOSITORY}/actions/runs/${process.env.GITHUB_RUN_ID}/artifacts?per_page=100`)).json();
const artifacts = artifactList.artifacts.filter(a => a.name === `static-llvm-tuple-${platform}` && !a.expired);
assert.equal(artifacts.length, 1, 'native tuple artifact must be unique');
const list = path.join(process.env.RUNNER_TEMP, 'bootstrap-files.json');
const output = path.join(process.env.RUNNER_TEMP, 'bootstrap-inputs-pin.json');
fs.writeFileSync(list, JSON.stringify(files));
const result = spawnSync(process.execPath, ['ci/release/publish_bootstrap_inputs.mjs', root, list, output], {
  env: {...process.env, BOOTSTRAP_ARTIFACT_ID: String(artifacts[0].id)}, stdio: 'inherit',
});
assert.equal(result.status, 0, 'native tuple prerelease and readback must complete');
const pin = JSON.parse(fs.readFileSync(output));
pin.platform = platform;
pin.sums_sha256 = digest(sums);
fs.writeFileSync(output, JSON.stringify(pin, null, 2) + '\n');

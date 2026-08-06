import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import test from 'node:test';
import {shallowClone} from '../lib/git.mjs';

test('shallowClone fetches a full commit SHA without treating it as a branch', async () => {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), 'source-build-git-'));
  const destination = path.join(root, 'checkout');
  const sha = '27d23ffbe2ba3ec28719c30977832816370c8231';
  const previousDryRun = process.env.CANGJIE_BUILD_DRY_RUN;
  const originalWrite = process.stderr.write;
  let output = '';
  process.env.CANGJIE_BUILD_DRY_RUN = '1';
  process.stderr.write = chunk => { output += String(chunk); return true; };
  try {
    await shallowClone('https://example.invalid/runtime.git', destination, {tag: sha});
  } finally {
    process.stderr.write = originalWrite;
    if (previousDryRun === undefined) delete process.env.CANGJIE_BUILD_DRY_RUN;
    else process.env.CANGJIE_BUILD_DRY_RUN = previousDryRun;
    fs.rmSync(root, {recursive: true, force: true});
  }
  assert.match(output, /git init/);
  assert.match(output, new RegExp(`git -C .* fetch --depth 1 origin ${sha}`));
  assert.match(output, /git -C .* checkout --detach FETCH_HEAD/);
  assert.doesNotMatch(output, new RegExp(`clone .* --branch ${sha}`));
});

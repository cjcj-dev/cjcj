import assert from 'node:assert/strict';
import fs from 'node:fs';
import net from 'node:net';
import os from 'node:os';
import path from 'node:path';
import test from 'node:test';
import {download} from '../lib/archive.mjs';

test('download gives IPv4 fallback enough time on dual-stack hosts', async t => {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), 'source-build-archive-'));
  const destination = path.join(root, 'fixture.bin');
  const originalTimeout = net.getDefaultAutoSelectFamilyAttemptTimeout();
  fs.writeFileSync(destination, 'cached archive fixture');
  t.after(() => {
    net.setDefaultAutoSelectFamilyAttemptTimeout(originalTimeout);
    fs.rmSync(root, {recursive: true, force: true});
  });

  await download('https://example.invalid/fixture.bin', destination);

  assert.equal(net.getDefaultAutoSelectFamilyAttemptTimeout(), 2_000);
  assert.equal(fs.readFileSync(destination, 'utf8'), 'cached archive fixture');
});

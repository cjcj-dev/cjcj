import assert from 'node:assert/strict';
import fs from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';
import {execFileSync} from 'node:child_process';
import test from 'node:test';
import {assertNoCanonicalWorkloads, CANONICAL_WORKLOADS} from '../lib/canonical-workloads.mjs';

test('canonical package exclusion checks actual tar and zip members', async t => {
  const root = await fs.mkdtemp(path.join(os.tmpdir(), 'canonical-package-'));
  t.after(() => fs.rm(root, {recursive: true, force: true}));
  const sdk = path.join(root, 'sdk');
  await fs.mkdir(path.join(sdk, 'bin'), {recursive: true});
  await fs.writeFile(path.join(sdk, 'bin/cjc'), 'ordinary SDK member');
  for (const format of ['tar.gz', 'zip']) {
    const archive = path.join(root, `sdk.${format}`);
    const pack = async () => {
      await fs.rm(archive, {force: true});
      if (format === 'zip') execFileSync('zip', ['-qr', archive, 'sdk'], {cwd: root});
      else execFileSync('tar', ['-czf', archive, 'sdk'], {cwd: root});
    };
    await pack();
    await assertNoCanonicalWorkloads(archive);
    for (const {name} of CANONICAL_WORKLOADS) {
      const injected = path.join(sdk, 'bin', name);
      await fs.copyFile(path.join(sdk, 'bin/cjc'), injected);
      await pack();
      await assert.rejects(assertNoCanonicalWorkloads(archive), new RegExp(`canonical-workload-in-package: sdk/bin/${name}`));
      await fs.rm(injected);
      await pack();
      await assertNoCanonicalWorkloads(archive);
    }
  }
});

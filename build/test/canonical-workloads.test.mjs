import assert from 'node:assert/strict';
import fs from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';
import {execFileSync} from 'node:child_process';
import test from 'node:test';
import {fileSha256} from '../lib/package-lineage.mjs';
import {assertNoCanonicalWorkloads, CANONICAL_WORKLOADS, validateCanonicalWorkloads} from '../lib/canonical-workloads.mjs';

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

for (const {name} of CANONICAL_WORKLOADS) {
  test(`canonical identity rejects a changed hash for only ${name}`, async t => {
    const root = await fs.mkdtemp(path.join(os.tmpdir(), 'canonical-identity-'));
    t.after(() => fs.rm(root, {recursive: true, force: true}));
    const record = {
      schema: 1, compiler: {kind: 'cjcj-stage2', sha256: 'a'.repeat(64)},
      final_std_sha256: 'b'.repeat(64), cjcj_head_sha: 'c'.repeat(40),
      runtime_source_sha: 'd'.repeat(40), flags: ['-O2', '--static-std'], workloads: [],
    };
    for (const item of CANONICAL_WORKLOADS) {
      const file = path.join(root, item.name);
      // Identity-parser fixture only: this is not a compiler acceptance ELF.
      await fs.writeFile(file, `identity parser fixture ${item.name}`);
      record.workloads.push({...item, file: item.name, source_sha256: 'e'.repeat(64), elf_sha256: await fileSha256(file)});
    }
    const manifest = path.join(root, 'CANONICAL_WORKLOADS.json');
    const save = () => fs.writeFile(manifest, JSON.stringify(record));
    await save();
    assert.equal((await validateCanonicalWorkloads(root)).workloads.length, 2);
    const row = record.workloads.find(item => item.name === name);
    const original = row.elf_sha256;
    row.elf_sha256 = (original[0] === '0' ? '1' : '0') + original.slice(1);
    await save();
    await assert.rejects(validateCanonicalWorkloads(root), new RegExp(`canonical-workload-elf-sha256:${name}`));
    row.elf_sha256 = original;
    await save();
    assert.equal((await validateCanonicalWorkloads(root)).workloads.length, 2);
    await fs.rm(path.join(root, name));
    await assert.rejects(validateCanonicalWorkloads(root), error => error.code === 'ENOENT' && error.path === path.join(root, name));
  });
}

import assert from 'node:assert/strict';
import fs from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';
import test from 'node:test';
import {produceFinalCompiler, consumeFinalCompiler, fileSha256, stdIdentity} from '../../ci/srcbuild/lib/final-compiler.mjs';

for (const platform of ['linux-x64', 'linux-aarch64', 'darwin-x64', 'darwin-arm64', 'windows-x64']) {
  test(`final compiler producer/consumer identity: ${platform}`, async t => {
    const root = await fs.mkdtemp(path.join(os.tmpdir(), 'final-compiler-'));
    t.after(() => fs.rm(root, {recursive: true, force: true}));
    const binary = path.join(root, 'producer');
    const std = path.join(root, 'std');
    await fs.mkdir(std);
    await fs.writeFile(path.join(std, 'PROVENANCE.txt'), 'source std manifest');
    await fs.writeFile(path.join(std, 'core.a'), 'source static std');
    await fs.writeFile(binary, 'final compiler fixture');
    await fs.writeFile(path.join(root, 'decoy'), 'old workspace compiler fixture');
    const common = {platform, repository: 'https://github.com/cjcj-dev/cjcj.git', commit: 'a'.repeat(40), runId: '12', runAttempt: '1', std};
    const outdir = path.join(root, 'artifact');
    const installed = await produceFinalCompiler({...common, binary, outdir, lineage: {
      compilerSha256: await fileSha256(binary), parentSha256: 'b'.repeat(64), stdSha256: await stdIdentity(std), stage: 'stage3',
    }});
    const options = {...common, directory: outdir};
    const selected = await consumeFinalCompiler(options);
    assert.equal(selected, installed);
    assert.equal(await fs.readFile(selected, 'utf8'), 'final compiler fixture');
    await assert.rejects(consumeFinalCompiler({...options, runId: '13'}), /run\/std mismatch/);
    await assert.rejects(consumeFinalCompiler({...options, commit: 'c'.repeat(40)}), /source mismatch/);
    await fs.writeFile(path.join(std, 'core.a'), 'host static std');
    await assert.rejects(consumeFinalCompiler(options), /run\/std mismatch/);
    await fs.writeFile(path.join(std, 'core.a'), 'source static std');
    await fs.writeFile(installed, 'unrelated workspace compiler');
    await assert.rejects(consumeFinalCompiler(options), /binary SHA-256 mismatch/);
  });
}

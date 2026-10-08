// Run against one retained, successful real CLI fixture. Every control arm
// consumes the same frozen plan, producer receipts and compiled input bytes.
import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs/promises';
import path from 'node:path';
import {fileURLToPath} from 'node:url';
import {buildIdentities, readJson, objectId, execute, fileDigest} from './sdk-manifest.mjs';

const here = path.dirname(fileURLToPath(import.meta.url));
const planFile = process.env.SDK_BOUNDARY_PLAN;
const evidence = process.env.SDK_BOUNDARY_ROOT;
assert.ok(planFile && evidence, 'SDK_BOUNDARY_PLAN and SDK_BOUNDARY_ROOT must name retained private inputs');
const invoke = async out => {
  try { return {rc: 0, ...await execute(process.execPath,
    [path.join(here, 'toolchain-sdk.mjs'), '--plan', planFile, '--out', out], {maxBuffer: 8 * 1024 * 1024})}; }
  catch (error) { return {rc: error.code, stdout: error.stdout, stderr: error.stderr}; }
};

for (const boundary of ['producer', 'consumer']) {
  test(`original ordinary digest survives the ${boundary} boundary`, async () => {
    const plan = await readJson(planFile), planSha256 = objectId(plan);
    const identities = buildIdentities(plan), std = plan.components.find(row => row.roles.includes('std'));
    const directory = identities.get(std.id).directory;
    const receipt = await readJson(path.join(directory, 'output.json'));
    const module = `modules/${plan.platform}_cjnative/std/core/core.Int64.ti`;
    assert.ok(receipt.files[module], 'retained fixture must contain the actual std module');
    const root = await fs.mkdtemp(path.join(evidence, `${boundary}-`));
    const normal = await invoke(path.join(root, 'normal'));
    await fs.writeFile(path.join(root, 'normal.json'), JSON.stringify(normal, null, 2));
    console.log(`BOUNDARY_NORMAL ${boundary} rc=${normal.rc} plan=${planSha256}`);
    assert.equal(normal.rc, 0, normal.stderr);
    const source = boundary === 'consumer' ? path.join(directory, 'artifacts', module)
      : path.join(plan.buildRoot, 'shared-cache', receipt.execution.producerBuildId, 'artifacts', module);
    const bytes = await fs.readFile(source), sourceSha256 = await fileDigest(source);
    assert.equal(sourceSha256, receipt.files[module].sha256, 'input must match its original producer seal');
    const backup = path.join(root, 'original-std');
    if (boundary === 'producer') await fs.rename(directory, backup);
    const replacement = Buffer.from(bytes); replacement[0] ^= 1;
    let result;
    try {
      await fs.writeFile(source, replacement);
      result = await invoke(path.join(root, 'substituted'));
      await fs.writeFile(path.join(root, 'substituted.json'), JSON.stringify(result, null, 2));
      console.log(`TARGET_ASSERTION_EXECUTED original-digest-${boundary} rc=${result.rc} plan=${planSha256}`);
      assert.notEqual(result.rc, 0, `the ${boundary} must preserve the original producer digest`);
      assert.match(result.stderr, /PAYLOAD_DIGEST[^\n]*core.Int64.ti/);
      await assert.rejects(fs.access(path.join(root, 'substituted')));
    } finally {
      await fs.writeFile(source, bytes);
      if (boundary === 'producer') {
        // Retain the real failed producer/install attempt, then put back the
        // original successful receipt for the next arm's identical input.
        try { await fs.rename(directory, path.join(root, 'attempt-std')); }
        catch (error) { if (error.code !== 'ENOENT') throw error; }
        await fs.rename(backup, directory);
      }
      assert.equal(await fileDigest(source), sourceSha256, 'restore exact original input bytes');
      assert.equal(objectId(await readJson(planFile)), planSha256, 'the plan must remain frozen');
    }
    const restored = await invoke(path.join(root, 'restored'));
    await fs.writeFile(path.join(root, 'restored.json'), JSON.stringify(restored, null, 2));
    console.log(`BOUNDARY_RESTORED ${boundary} rc=${restored.rc} plan=${planSha256}`);
    assert.equal(restored.rc, 0, restored.stderr);
  });
}

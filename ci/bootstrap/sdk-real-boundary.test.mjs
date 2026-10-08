// Integration against a retained genuine Cangjie SDK, not the small C fixtures.
import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs/promises';
import path from 'node:path';
import {fileURLToPath} from 'node:url';
import {spawn} from 'node:child_process';
import {readJson, buildIdentities, fileDigest, objectId} from './sdk-manifest.mjs';
import {verifyManifestSdk} from './toolchain-sdk.mjs';

const here = path.dirname(fileURLToPath(import.meta.url));
const planFile = process.env.SDK_REAL_PLAN, sdk = process.env.SDK_REAL_SDK, evidence = process.env.SDK_REAL_EVIDENCE;
assert.ok(planFile && sdk && evidence, 'SDK_REAL_PLAN/SDK_REAL_SDK/SDK_REAL_EVIDENCE must name genuine private products');
const product = process.env.SDK_MANIFEST_PRODUCT || path.join(here, 'toolchain-sdk.mjs');
const plan = await readJson(planFile), manifest = await readJson(path.join(sdk, 'SDK.manifest.json'));
const identities = buildIdentities(plan), planSha = objectId(plan);
async function invoke(root, name) {
  const out = path.join(root, name), log = path.join(root, `${name}.log`), fd = await fs.open(log, 'wx');
  const started = new Date().toISOString(), start = performance.now();
  const args = [product, '--plan', planFile, '--out', out];
  const result = await new Promise((resolve, reject) => {
    const child = spawn(process.execPath, args, {stdio: ['ignore', fd.fd, fd.fd]});
    child.once('error', reject); child.once('exit', (rc, signal) => resolve({rc, signal}));
  });
  await fd.close();
  await fs.writeFile(path.join(root, `${name}.json`), JSON.stringify({command: process.execPath, args,
    started, finished: new Date().toISOString(), wall: (performance.now() - start) / 1000, ...result, log, planSha}, null, 2) + '\n');
  return {...result, out, log, text: await fs.readFile(log, 'utf8')};
}

for (const boundary of ['ordinary-module', 'mixed-llvm']) {
  test(`genuine SDK ${boundary} refuses publication and restores through the actual assembler`, async () => {
    await verifyManifestSdk(sdk, plan, manifest);
    console.log(`REAL_BOUNDARY_NORMAL ${boundary} plan=${planSha}`);
    const rel = boundary === 'ordinary-module' ? `modules/${plan.platform}_cjnative/std/std.core.cjo`
      : 'third_party/llvm/lib/libLLVM-15.so';
    const row = manifest.files[rel]; assert.ok(row, `genuine native output ${rel}`);
    const directory = identities.get(row.component).directory, source = path.join(directory, 'artifacts', row.source);
    const root = await fs.mkdtemp(path.join(evidence, `${boundary}-`)), backup = path.join(root, 'original-payload');
    const originalSha = await fileDigest(source);
    assert.equal(originalSha, row.sha256, 'original producer bytes match the presealed inventory');
    await fs.rename(source, backup);
    try {
      if (boundary === 'mixed-llvm') {
        const official = plan.components.find(component => component.source.kind === 'distribution');
        await fs.copyFile(path.join(official.source.root, rel), source);
      } else {
        const bytes = await fs.readFile(backup); bytes[0] ^= 1; await fs.writeFile(source, bytes);
      }
      await fs.chmod(source, row.mode);
      const rejected = await invoke(root, 'rejected');
      console.log(`TARGET_ASSERTION_EXECUTED real-${boundary} rc=${rejected.rc} file=${rel}`);
      assert.notEqual(rejected.rc, 0, 'the actual assembler must refuse the substituted payload');
      assert.match(rejected.text, new RegExp(`rule=PAYLOAD_DIGEST[^\\n]*${rel.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')}`));
      if (boundary === 'mixed-llvm') {
        console.log(`TARGET_ASSERTION_EXECUTED real-llvm-source-stamp observed=${/rule=LLVM_TUPLE[^\n]*libLLVM-15.so/.test(rejected.text)}`);
        assert.match(rejected.text, /rule=LLVM_TUPLE[^\n]*libLLVM-15.so/);
      }
      await assert.rejects(fs.access(rejected.out));
    } finally {
      await fs.rm(source, {force: true}); await fs.rename(backup, source);
      assert.equal(await fileDigest(source), originalSha, 'restore the same genuine producer bytes');
      assert.equal(objectId(await readJson(planFile)), planSha, 'the input plan stayed frozen');
    }
    const restored = await invoke(root, 'restored');
    console.log(`TARGET_ASSERTION_EXECUTED real-${boundary}-restored rc=${restored.rc}`);
    assert.equal(restored.rc, 0, restored.text);
    // Retain successful metadata and logs. The original genuine SDK and all
    // producer artifacts remain inputs; this duplicate SDK has no consumer.
    for (const name of ['SDK.plan.json', 'SDK.manifest.json', 'SDK.lock.json']) {
      await fs.copyFile(path.join(restored.out, name), path.join(root, `restored-${name}`));
    }
    await fs.rm(restored.out, {recursive: true});
  });
}

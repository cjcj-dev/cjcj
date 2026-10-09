#!/usr/bin/env zx
// Actual native producer receipts and the SDK CLI are required inputs.
import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs/promises';
import path from 'node:path';
import {spawn} from 'node:child_process';
import {fileDigest, readJson} from './sdk-manifest.mjs';
const planFile = process.env.SDK_READER_PLAN;
const evidence = process.env.SDK_READER_EVIDENCE;
assert.ok(planFile && evidence, 'SDK_READER_PLAN/SDK_READER_EVIDENCE require actual native receipts');
const cli = process.env.SDK_READER_PRODUCT || new URL('./toolchain-sdk.mjs', import.meta.url).pathname;
await fs.mkdir(evidence, {recursive: true});
async function assemble(name, input) {
  const directory = path.join(evidence, name), log = `${directory}.log`;
  const output = await fs.open(log, 'wx');
  const started = new Date().toISOString(), begin = performance.now();
  const argv = [cli, '--plan', input, '--out', directory];
  const result = await new Promise((resolve, reject) => {
    const child = spawn(process.execPath, argv, {stdio: ['ignore', output.fd, output.fd]});
    child.once('error', reject); child.once('exit', (rc, signal) => resolve({rc, signal}));
  });
  await output.close();
  await fs.writeFile(`${directory}.result.json`, JSON.stringify({argv, started, wall: (performance.now()-begin)/1000, ...result})+'\n');
  return {...result, directory, text: await fs.readFile(log, 'utf8')};
}
test('native bitcode readers reach the SDK CLI with sealed target and executable identities', async () => {
  const result = await assemble('native-readers', planFile);
  // This single target assertion observes the CLI's publication decision,
  // including semantic reader qualification. No earlier existence assertion
  // can hide it on a faulty producer arm.
  console.log(`READER_PUBLICATION_TARGET_ASSERT_REACHED rc=${result.rc} diagnostic=${result.text.match(/rule=LLVM_READERS[^\n]*/)?.[0] || 'none'}`);
  assert.equal(result.rc, 0, `native reader publication must preserve its sealed identities\n${result.text}`);
  const plan = await readJson(planFile), manifest = await readJson(path.join(result.directory, 'SDK.manifest.json'));
  const component = plan.components.find(c => c.config.options.bitcodeReadersOnly);
  const receipt = await readJson(path.join(component.producer.receipt, 'output.json'));
  const metadata = await readJson(path.join(result.directory, 'third_party/llvm/bitcode-readers.json'));
  for (const name of ['llvm-dis', 'llvm-as']) {
    const rel = `third_party/llvm/bin/${name}`, row = manifest.files[rel];
    console.log(`READER_IDENTITY_TARGET_ASSERT_REACHED tool=${name} build=${row.buildId} digest=${row.sha256}`);
    assert.equal(row.component, component.id);
    assert.equal(row.sha256, receipt.files[`bin/${name}`].sha256);
    assert.equal(row.sha256, metadata.tools[name].sha256);
    assert.equal(await fileDigest(path.join(result.directory, rel)), row.sha256);
  }
});
if (process.env.SDK_READER_INVALID_PLAN) {
  test('SDK CLI rejects a native receipt whose reader semantic digest disagrees with its sealed executable', async () => {
    const result = await assemble('invalid-reader-digest', process.env.SDK_READER_INVALID_PLAN);
    const rejected = result.rc !== 0 && /rule=LLVM_READERS[^\n]*missing\/mismatched reader: llvm-dis/.test(result.text);
    console.log(`READER_DIGEST_TARGET_ASSERT_REACHED rejected=${rejected} rc=${result.rc}`);
    assert.equal(rejected, true, `reader digest must be checked by the real SDK CLI\n${result.text}`);
  });
}

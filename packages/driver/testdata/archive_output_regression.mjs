#!/usr/bin/env zx
import { $ } from 'zx';
import assert from 'node:assert/strict';
import { mkdtemp, mkdir, readFile, writeFile, stat } from 'node:fs/promises';
import { resolve, join } from 'node:path';

// Run on Linux with a compiler built from the candidate and its matching SDK.
// The supplied fixture parent must be an isolated task directory. Keep evidence.
const [compilerArg, parentArg, ar = 'ar'] = process.argv.slice(2);
assert(compilerArg && parentArg, 'usage: zx archive_output_regression.mjs <cjc> <fixture-parent> [ar]');
assert.equal(process.platform, 'linux');
const compiler = resolve(compilerArg);
const root = await mkdtemp(join(resolve(parentArg), 'archive-output-'));
console.log(`FIXTURE=${root}`);
const pkg = join(root, 'pkg');
await mkdir(pkg);
await writeFile(join(pkg, 'foo.cj'), 'package foo\npublic func archiveValue(): Int64 { return 42 }\n');
const results = [];
async function run(label, exe, args) {
  const result = await $({ nothrow: true, timeout: 300_000 })`${exe} ${args}`;
  results.push({ label, exe, args, rc: result.exitCode });
  await writeFile(join(root, `${label}.stdout`), result.stdout);
  await writeFile(join(root, `${label}.stderr`), result.stderr);
  await writeFile(join(root, 'results.json'), JSON.stringify(results, null, 2) + '\n');
  return result;
}
async function compile(label, out) {
  return run(label, compiler, ['-p', pkg, '--output-type=staticlib', '--apc-split-num=1', '-o', out]);
}
async function members(label, archive) {
  const result = await run(label, ar, ['t', archive]);
  assert.equal(result.exitCode, 0, `${label}: archive must be readable`);
  assert(result.stdout.trim().length > 0, `${label}: archive must have members`);
  return result.stdout.trim().split(/\r?\n/);
}
const normal = join(root, 'normal');
await mkdir(normal);
assert.equal((await compile('normal-create', normal)).exitCode, 0, 'healthy source-to-archive control');
const archive = join(normal, 'libfoo.a');
await members('normal-members', archive);
const obsolete = join(root, 'obsolete-member');
await writeFile(obsolete, 'must not survive replacement\n');
assert.equal((await run('seed-old-member', ar, ['r', archive, obsolete])).exitCode, 0);
assert((await members('seeded-members', archive)).includes('obsolete-member'));
assert.equal((await compile('normal-replace', normal)).exitCode, 0);
assert(!(await members('replaced-members', archive)).includes('obsolete-member'), 'old archive members must be removed');
for (const kind of ['populated', 'empty', 'fifo']) {
  const out = join(root, kind);
  const output = join(out, 'libfoo.a');
  await mkdir(out);
  if (kind === 'fifo') {
    assert.equal((await run('create-fifo', 'mkfifo', [output])).exitCode, 0);
  } else {
    await mkdir(output);
    if (kind === 'populated') {
      await mkdir(join(output, 'nested'));
      await writeFile(join(output, 'nested', 'keep.txt'), 'user data\n');
    }
  }
  const result = await compile(`reject-${kind}`, out);
  if (kind === 'populated') {
    assert.equal(await readFile(join(output, 'nested', 'keep.txt'), 'utf8'), 'user data\n', 'archive output directory data was lost');
  }
  assert(kind === 'fifo' ? (await stat(output)).isFIFO() : (await stat(output)).isDirectory(), `${kind} output must remain`);
  assert.notEqual(result.exitCode, 0, `${kind} output must fail compilation`);
  assert.match(result.stderr, kind === 'fifo' ? /cannot remove existing archive output/ : /archive output .* is a directory/, 'must reach archive output rejection, not fail earlier');
}
console.log('PASS: archive creation/replacement, directory preservation, and removal failure propagation');

#!/usr/bin/env zx
// Fault arms for the scripts themselves; no LLVM execution claim.
import fs from 'node:fs';
import path from 'node:path';
import assert from 'node:assert/strict';
import {spawnSync} from 'node:child_process';
import {createHash} from 'node:crypto';
import {fileURLToPath} from 'node:url';
const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const index = process.argv.findIndex((arg, i) => i > 0 && path.resolve(arg) === fileURLToPath(import.meta.url));
const work = path.resolve(process.argv[index + 1] || '');
assert.ok(process.argv[index + 1], 'expected EMPTY_WORK_DIRECTORY');
fs.mkdirSync(work);
const producer = path.join(root, 'ci/llvm-tuple-layout.mjs');
const consumer = path.join(root, 'ci/release/prepare_bootstrap_inputs.mjs');
const saved = new Map([producer, consumer].map(file => [file, fs.readFileSync(file)]));
for (const [file, bytes] of saved) fs.writeFileSync(path.join(work, `${path.basename(file)}.saved`), bytes);
const restore = () => { for (const [file, bytes] of saved) fs.writeFileSync(file, bytes); };
const hashes = () => [...saved.keys()].map(file => `${createHash('sha256').update(fs.readFileSync(file)).digest('hex')}  ${file}\n`).join('');
const pattern = '^(?!ast ).*(tuple|depot|persistent)';
function run(name, args) {
  const result = spawnSync(args[0], args.slice(1), {cwd: root, env: {...process.env, LC_ALL: 'C'}, encoding: 'utf8'});
  fs.writeFileSync(path.join(work, `${name}.log`), (result.stdout || '') + (result.stderr || ''));
  fs.writeFileSync(path.join(work, `${name}.rc`), `${result.status}\n`);
  assert.equal(result.error, undefined);
  assert.equal(result.signal, null);
  return result;
}
const layout = name => run(name, ['bash', 'ci/test-llvm-tuple-layout.sh', path.join(work, name)]);
const consume = name => run(name, ['node', '--test', '--test-reporter=tap', `--test-name-pattern=${pattern}`, 'ci/release/prepare_bootstrap_inputs.test.mjs']);
function cut(file, before, after, name) {
  const source = fs.readFileSync(file, 'utf8');
  assert.equal(source.split(before).length, 2, `unique cut: ${name}`);
  fs.writeFileSync(file, source.replace(before, after));
  const diff = spawnSync('diff', ['-u', path.join(work, `${path.basename(file)}.saved`), file], {encoding: 'utf8'});
  assert.equal(diff.status, 1);
  fs.writeFileSync(path.join(work, `${name}.diff`), diff.stdout);
  fs.writeFileSync(path.join(work, `${name}.sha256`), hashes());
}
const greenHashes = hashes();
fs.writeFileSync(path.join(work, 'green.sha256'), greenHashes);
try {
  assert.equal(layout('producer-green').status, 0);
  assert.equal(consume('consumer-green').status, 0);
  // Redirect the actual publisher output to the wrong payload. The script still
  // succeeds; the ten-file contract, not a command failure, must turn red.
  cut(producer, "`${depot}/lib/STATIC_LLVM.txt`])).exitCode", "`${depot}/lib/WRONG_STATIC_LLVM.txt`])).exitCode", 'producer-cut');
  const red = layout('producer-cut');
  assert.notEqual(red.status, 0);
  assert.match(red.stdout + red.stderr, /STATIC_LLVM\.txt/);
  restore();
  cut(consumer, "mode: process.env.CJCJ_BOOTSTRAP_SOURCE || 'release',", "mode: process.env.CJCJ_BOOTSTRAP_SOURCE || 'depot',", 'consumer-cut');
  const consumerRed = consume('consumer-cut');
  assert.notEqual(consumerRed.status, 0);
  assert.match(consumerRed.stdout, /ERR_ASSERTION/);
  assert.match(consumerRed.stdout, /^# pass 4$/m);
  assert.match(consumerRed.stdout, /^# fail 2$/m);
  restore();
  const source = fs.readFileSync(consumer, 'utf8');
  const start = source.indexOf('if (!/^[0-9a-f]{64}$/.test(process.env.LLVM_TUPLE_SUMS_SHA');
  const end = source.indexOf('\nconst colourRt', start);
  assert.ok(start >= 0 && end > start);
  cut(consumer, source.slice(start, end), '', 'pin-cut');
  const pinRed = consume('pin-cut');
  assert.notEqual(pinRed.status, 0);
  assert.match(pinRed.stdout, /ERR_ASSERTION/);
  assert.match(pinRed.stdout, /^# pass 5$/m);
  assert.match(pinRed.stdout, /^# fail 1$/m);
  restore();
  assert.equal(layout('producer-restored').status, 0);
  assert.equal(consume('consumer-restored').status, 0);
  fs.writeFileSync(path.join(work, 'restored.sha256'), hashes());
  assert.equal(hashes(), greenHashes);
  console.log(`WIRING producer green=0 cut=${red.status} restored=0; consumer green=0 cut=${consumerRed.status} restored=0`);
  console.log(`WIRING reviewed-pin green=0 cut=${pinRed.status} restored=0`);
} finally { restore(); }

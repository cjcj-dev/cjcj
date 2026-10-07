#!/usr/bin/env zx
// Fault arms for the scripts themselves; no LLVM execution claim.
import {fs, path, assert, repo, required, run, hash, diff, replace, equalFiles, zxCommand} from './script-common.mjs';
process.env.LC_ALL = 'C';
const work = path.resolve(required(0, 'EMPTY_WORK_DIRECTORY'));
fs.mkdirSync(work);
const producer = 'ci/llvm-tuple-layout.mjs';
const consumer = 'ci/release/prepare_bootstrap_inputs.mjs';
for (const [file, name] of [[producer, 'producer'], [consumer, 'consumer']]) fs.copyFileSync(path.join(repo, file), path.join(work, `${name}.saved`));
function restore() {
  fs.copyFileSync(path.join(work, 'producer.saved'), path.join(repo, producer));
  fs.copyFileSync(path.join(work, 'consumer.saved'), path.join(repo, consumer));
}
const layout = arm => run([...zxCommand(path.join(repo, 'ci/test-llvm-tuple-layout.mjs')), path.join(work, `producer-${arm}`)], {log: path.join(work, `producer-${arm}.log`), check: false});
const consume = arm => run(['node', '--test', '--test-reporter=tap', '--test-name-pattern=^(?!ast ).*(tuple|depot|persistent)', consumer.replace('.mjs', '.test.mjs')], {log: path.join(work, `${arm}.log`), check: false});
try {
  await hash([producer, consumer], path.join(work, 'green.sha256'));
  assert.equal((await layout('green')).exitCode, 0);
  assert.equal((await consume('consumer-green')).exitCode, 0);
  replace(path.join(repo, producer), "  fs.copyFileSync(path.join(depot, 'MANIFEST'), path.join(depot, 'lib/STATIC_LLVM.txt'));", '  // fault arm: omit static tuple payload');
  await diff(path.join(work, 'producer.saved'), path.join(repo, producer), path.join(work, 'producer-cut.diff'));
  await hash([producer], path.join(work, 'producer-cut.sha256'));
  const producerCut = await layout('cut');
  assert.notEqual(producerCut.exitCode, 0);
  assert.match(producerCut.stdall, /lib\/STATIC_LLVM.txt/);
  process.stdout.write(producerCut.stdall.split('\n').filter(line => line.includes('lib/STATIC_LLVM.txt')).join('\n') + '\n');
  restore();
  replace(path.join(repo, consumer), "mode: process.env.CJCJ_BOOTSTRAP_SOURCE || 'release',", "mode: process.env.CJCJ_BOOTSTRAP_SOURCE || 'depot',");
  await diff(path.join(work, 'consumer.saved'), path.join(repo, consumer), path.join(work, 'consumer-cut.diff'));
  await hash([consumer], path.join(work, 'consumer-cut.sha256'));
  const consumerCut = await consume('consumer-cut');
  assert.notEqual(consumerCut.exitCode, 0);
  for (const pattern of [/ERR_ASSERTION/, /^# pass 4$/m, /^# fail 2$/m]) assert.match(consumerCut.stdall, pattern);
  restore();
  const source = fs.readFileSync(path.join(repo, consumer), 'utf8');
  const a = source.indexOf("if (!/^[0-9a-f]{64}$/.test(process.env.LLVM_TUPLE_SUMS_SHA");
  const b = source.indexOf('\nconst colourRt', a);
  assert(a >= 0 && b > a);
  fs.writeFileSync(path.join(repo, consumer), source.slice(0, a) + source.slice(b));
  await diff(path.join(work, 'consumer.saved'), path.join(repo, consumer), path.join(work, 'pin-cut.diff'));
  await hash([consumer], path.join(work, 'pin-cut.sha256'));
  const pinCut = await consume('pin-cut');
  assert.notEqual(pinCut.exitCode, 0);
  for (const pattern of [/ERR_ASSERTION/, /^# pass 5$/m, /^# fail 1$/m]) assert.match(pinCut.stdall, pattern);
  restore();
  assert.equal((await layout('restored')).exitCode, 0);
  assert.equal((await consume('consumer-restored')).exitCode, 0);
  await hash([producer, consumer], path.join(work, 'restored.sha256'));
  equalFiles(path.join(work, 'green.sha256'), path.join(work, 'restored.sha256'));
  console.log(`WIRING producer green=0 cut=${producerCut.exitCode} restored=0; consumer green=0 cut=${consumerCut.exitCode} restored=0`);
  console.log(`WIRING reviewed-pin green=0 cut=${pinCut.exitCode} restored=0`);
} finally { restore(); }

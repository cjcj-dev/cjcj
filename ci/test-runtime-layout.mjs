#!/usr/bin/env zx
// Exercise the real pinned generator and the pairing entry with isolated copies.
import {fs, path, assert, repo, pin, requireArgument, commandsAt, equalFiles, zxCommand, entry, requireSuccess} from './entry-common.mjs';
const {run, hash, redirect} = commandsAt(process.cwd());
const requiredArguments = {"0": [5, "work directory"], "1": [6, "runtime repository"], "2": [7, "LLVM repository"]};
const required = index => requireArgument(index, ...requiredArguments[index]);
await entry(async () => {
const work = required(0, 'work directory');
const runtime = required(1, 'runtime repository'), llvm = required(2, 'LLVM repository');
const {RUNTIME_REF} = pin(path.join(repo, 'ci/runtime_pin.env'));
const {LLVM_SHA} = pin(path.join(repo, 'ci/llvm_pin.env'));
fs.mkdirSync(path.join(work, 'runtime'), {recursive: true});
fs.mkdirSync(path.join(work, 'llvm/llvm/include/llvm/CodeGen'), {recursive: true});
// Preserve the real pipeline: pipefail reports the rightmost failing command,
// and tar's diagnostic remains visible when Git cannot produce the archive.
$.prefix = 'set -euo pipefail; ' + $.prefix;
const archive = await $({cwd: process.cwd(), nothrow: true, quiet: true})
  `git -C ${runtime} archive ${RUNTIME_REF} runtime | tar -x -C ${path.join(work, 'runtime')}`;
process.stdout.write(archive.stdout);
process.stderr.write(archive.stderr);
requireSuccess(archive);
const header = 'llvm/include/llvm/CodeGen/CangjieRuntimeLayout.h';
await redirect(['git', '-C', llvm, 'show', `${LLVM_SHA}:${header}`], path.join(work, 'llvm', header));
async function commit(side, message) {
  await run(['git', '-C', path.join(work, side), 'add', '.']);
  await run(['git', '-C', path.join(work, side), '-c', 'user.name=Zxilly', '-c', 'user.email=zxilly@outlook.com', 'commit', '-qm', message]);
}
for (const side of ['runtime', 'llvm']) {
  await run(['git', '-C', path.join(work, side), 'init', '-q']);
  await commit(side, 'test: pinned layout snapshot');
}
const check = arm => run([...zxCommand(path.join(repo, 'ci/check-llvm-runtime-abi.mjs')),
  '--runtime-repo', path.join(work, 'runtime'), '--runtime-ref', 'HEAD',
  '--llvm-repo', path.join(work, 'llvm'), '--llvm-ref', 'HEAD'], {log: path.join(work, `${arm}.log`), check: false});
requireSuccess(await check('candidate'));
console.log('ASSERT layout candidate rc=0');
const output = path.join(work, 'llvm', header);
fs.copyFileSync(output, path.join(work, 'original.h'));
await hash([output], path.join(work, 'candidate.sha256'));
function bump(file, regex) {
  const source = fs.readFileSync(file, 'utf8');
  let count = 0;
  fs.writeFileSync(file, source.replace(regex, (_, a, b, c = '') => { count++; return a + (Number(b) + 8) + c; }));
  assert.equal(count, 1);
}
bump(output, /(ObjectStateWordOffset = )(\d+)()/g);
await commit('llvm', 'test: wrong consumer offset');
await run(['git', '-C', path.join(work, 'llvm'), 'diff', 'HEAD~', 'HEAD'], {log: path.join(work, 'consumer-cut.diff')});
await hash([output], path.join(work, 'consumer-cut.sha256'));
async function mismatch(arm, side) {
  const result = await check(arm);
  console.log(`ASSERT layout ${side} mismatch actual_rc=${result.exitCode} expected_rc=1`);
  assert.equal(result.exitCode, 1);
  assert.match(result.stdall, /differs from runtime assertions/);
  process.stdout.write(result.stdall.split('\n').filter(line => line.includes('differs from runtime assertions')).join('\n') + '\n');
  console.log(`ASSERT layout ${side} mismatch rc=1`);
}
await mismatch('consumer-cut', 'consumer');
fs.copyFileSync(path.join(work, 'original.h'), output);
await commit('llvm', 'test: restore consumer offset');
requireSuccess(await check('restored'));
await hash([output], path.join(work, 'restored.sha256'));
equalFiles(path.join(work, 'candidate.sha256'), path.join(work, 'restored.sha256'));
console.log('ASSERT layout restored rc=0');
bump(path.join(work, 'runtime/runtime/src/Common/BaseObject.h'), /(sizeof\(BaseObject\) == )(\d+)(, "compiler layout ObjectHeaderSize")/g);
await commit('runtime', 'test: wrong producer layout');
await run(['git', '-C', path.join(work, 'runtime'), 'diff', 'HEAD~', 'HEAD'], {log: path.join(work, 'producer-cut.diff')});
await mismatch('producer-cut', 'producer');
await run(['git', '-C', path.join(work, 'runtime'), 'restore', '--source=HEAD~', '--staged', '--worktree', 'runtime/src/Common/BaseObject.h']);
await commit('runtime', 'test: restore producer layout');
requireSuccess(await check('producer-restored'));
console.log('ASSERT layout producer restored rc=0');
});

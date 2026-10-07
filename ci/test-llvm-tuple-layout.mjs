#!/usr/bin/env zx
// Layout contract only: fixture bytes are not LLVM/compiler acceptance evidence.
import {fs, path, assert, repo, pin, requireArgument, run, capture, equalFiles, cliArgs, isMain} from './entry-common.mjs';
const requiredArguments = {"0": [7, "usage: test-llvm-tuple-layout.mjs EMPTY_WORK_DIRECTORY"]};
const required = index => requireArgument(index, ...requiredArguments[index]);
import {spawnSync} from 'node:child_process';
process.env.LC_ALL = 'C';
const work = path.resolve(required(0, 'EMPTY_WORK_DIRECTORY'));
fs.mkdirSync(work);
let tuple;
if (cliArgs[1]) {
  await run(['cp', '-a', cliArgs[1], path.join(work, 'tuple')]);
  tuple = path.join(work, 'tuple');
} else {
  const fixed = path.join(work, 'fixed');
  fs.mkdirSync(fixed);
  for (const tool of ['llc', 'opt', 'ld.lld']) {
    // gzip -n has the same reproducible bytes as the old fixture arm.
    const compressed = spawnSync('gzip', ['-n'], {input: `fixture ${tool}\n`});
    assert.equal(compressed.status, 0);
    fs.writeFileSync(path.join(fixed, `${tool}.gz`), compressed.stdout);
  }
  fs.writeFileSync(path.join(fixed, 'cjselfhost_llvmshim.o'), 'fixture shim\n');
  fs.writeFileSync(path.join(fixed, 'llvm-tools.manifest'), 'fixture manifest\n');
  const identities = pin(path.join(repo, 'ci/llvm_pin.env'));
  await run(['npx', '--yes', 'zx@8', path.join(repo, 'ci/llvm-tuple-layout.mjs'), path.join(work, 'depot')],
    {env: {...process.env, ...identities, REPO_ROOT: repo, CJCJ_FIXED_LLVM_DIR: fixed}});
  tuple = path.join(work, 'depot', identities.LLVM_SHA, identities.CANGJIE_COMPILER_SHA);
}
const check = log => run(['sha256sum', '--strict', '-c', 'SHA256SUMS'], {cwd: tuple, log: path.join(work, log), check: false});
assert.equal((await check('green.log')).exitCode, 0);
assert.equal(fs.readFileSync(path.join(tuple, 'SHA256SUMS'), 'utf8').trimEnd().split('\n').length, 10);
const marker = path.join(tuple, 'lib/STATIC_LLVM.txt');
fs.copyFileSync(marker, path.join(work, 'static.saved'));
fs.unlinkSync(marker);
const cut = await check('cut.log');
assert.notEqual(cut.exitCode, 0);
assert.equal((cut.stdall.match(/: OK$/gm) || []).length, 9);
assert.equal((cut.stdall.match(/^\.\/lib\/STATIC_LLVM.txt: FAILED/gm) || []).length, 1);
fs.copyFileSync(path.join(work, 'static.saved'), marker);
assert.equal((await check('restored.log')).exitCode, 0);
equalFiles(path.join(work, 'green.log'), path.join(work, 'restored.log'));
console.log(`layout target executed: green_rc=0 cut_rc=${cut.exitCode} restored_rc=0; cut OK=9 FAILED=1`);

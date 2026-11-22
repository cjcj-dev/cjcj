import assert from 'node:assert/strict';
import test from 'node:test';
import {checkPair, targetRef, tuple} from '../lib/ohos-split-sdk.mjs';

const host = '9991cf4f4c9cb3465bb5aec28a5590f6c529be4e';
const compiler = 'ea6d3b5fc73b5e4cc2926535005a46a92109b2b9';
const stage = {phase:'stage2', platform:'linux_x86_64', runtimeCommit:host, compilerCommit:compiler,
  compilerSha256:'ab8e03d32d95b8a84da42a4d11520b2644796cc339e50825426bb38bf5c33be0',
  sources:{compiler:{commit:compiler}, llvm:{commit:'f2a8e33d2dbb6797d65813cd20f529d9567843a1'},
    runtime:{commit:host}, std:{commit:host}}};
test('OHOS split runtime is bound to the host stage, compiler bytes and target tuple', () => {
  checkPair(stage, host, targetRef, targetRef, tuple);
  for (const changed of [{phase:'stage3'}, {compilerSha256:'0'.repeat(64)}, {compilerCommit:targetRef},
    {runtimeCommit:targetRef}, {sources:{...stage.sources,llvm:{commit:compiler}}}, {llvmCommit:compiler}])
    assert.throws(() => checkPair({...stage,...changed}, host, targetRef, targetRef, tuple), /OHOS split source mismatch/);
  for (const args of [[host, targetRef, host, tuple], [host, host, host, tuple],
    [targetRef, targetRef, targetRef, tuple], [host, targetRef, targetRef, 'linux_ohos_x86_64_cjnative']])
    assert.throws(() => checkPair(stage, ...args), /OHOS split source mismatch/);
});

import assert from 'node:assert/strict';
import test from 'node:test';
import {inspectWriteBarriers} from '../../ci/srcbuild/lib/write-barrier.mjs';

// objdump -drwC shape: address, raw bytes, mnemonic, and (wide) the relocation
// appended to the same line.
function line(address, bytes, text, relocation) {
  const parts = [`   ${address}:`, bytes, text];
  const body = relocation ? `${parts.slice(1).join('\t')}\t${relocation}` : parts.slice(1).join('\t');
  return `   ${address}:\t${body}`;
}

// The off shape from CJBarrierLowering.cpp SplitFastPathAndSlowPath: phase check,
// fast arm inlines the store, slow arm calls the runtime.
const guarded = callee => [
  '0000000000000340 <_CNat4Test1fHv>:',
  line('347', '49 8b 47 08', 'mov    0x8(%r15),%rax'),
  line('34b', '8b 00', 'mov    (%rax),%eax'),
  line('34d', '83 f8 09', 'cmp    $0x9,%eax'),
  line('350', '7d 05', 'jge    357 <_CNat4Test1fHv+0x17>'),
  line('352', '4c 89 22', 'mov    %r12,(%rdx)'),
  line('355', 'eb 0b', 'jmp    362 <_CNat4Test1fHv+0x22>'),
  line('357', '4c 89 e7', 'mov    %r12,%rdi'),
  line('35d', 'e8 00 00 00 00', 'call   362 <_CNat4Test1fHv+0x22>', `35e: R_X86_64_PLT32\t${callee}-0x4`),
  line('362', 'c3', 'ret'),
].join('\n');

// The on shape: the same write, called unconditionally.
const unguarded = [
  '0000000000000340 <_CNat4Test1fHv>:',
  line('347', '4c 89 e7', 'mov    %r12,%rdi'),
  line('34a', 'e8 00 00 00 00', 'call   34f <_CNat4Test1fHv+0xf>', '34b: R_X86_64_PLT32\tCJ_MCC_WriteRefField-0x4'),
  line('34f', 'c3', 'ret'),
].join('\n');

test('a phase-guarded heap write counts as bypassed', () => {
  const counts = inspectWriteBarriers(guarded('CJ_MCC_WriteRefField'));
  assert.deepEqual(counts, {phaseChecks: 1, staticGuarded: 0, bypassed: 1, unresolved: 0});
});

test('a phase-guarded static write is the intended fast path, not a bypass', () => {
  // cj_gcwrite_static_ref is not in the list fastBarrier() blocks, so it keeps the
  // fast path even with the flag on. Counting it would reject a correct std.
  const counts = inspectWriteBarriers(guarded('CJ_MCC_WriteStaticRef'));
  assert.deepEqual(counts, {phaseChecks: 1, staticGuarded: 1, bypassed: 0, unresolved: 0});
});

test('an unconditional heap write is what the barrier looks like when it is on', () => {
  const counts = inspectWriteBarriers(unguarded);
  assert.deepEqual(counts, {phaseChecks: 0, staticGuarded: 0, bypassed: 0, unresolved: 0});
});

test('addresses do not resolve across function boundaries', () => {
  // Two functions whose addresses overlap: the branch in the first must not land
  // on an instruction belonging to the second.
  const counts = inspectWriteBarriers(`${guarded('CJ_MCC_WriteRefField')}\n${unguarded}`);
  assert.equal(counts.bypassed, 1);
  assert.equal(counts.phaseChecks, 1);
});
